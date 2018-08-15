#!/bin/false

set -o xtrace
set -o errexit
set -o nounset
set -o pipefail
shopt -s failglob
shopt -s nullglob

mountpoint -q /proc || mount -t proc  none /proc
mountpoint -q /sys  || mount -t sysfs none /sys

if false # if true, drop to shell for debugging purposes
then
  bash -i
fi

###
### CLEAN UP /tmp/dg/initramfs/classical
###

if mountpoint -q           /tmp/dg/initramfs/classical
then
  rm -rf --one-file-system /tmp/dg/initramfs/classical || true
  # lazy unmount needed because in a stageF boot the rootfs stored on
  # classical remains referenced and is not ever cleaned up
  umount -l                /tmp/dg/initramfs/classical
fi

###
### DETERMINE OS
###

OS_RELEASE_ID="$( . /etc/os-release ; echo "$ID" )"

###
### MODULE LOADING
###

# for the arm platform, a complete set of kernel modules is not
# included to speed up the boot. thus it's useful to know what the
# kernel is trying (and perhaps failing) to autoload. UPDATE: no
# longer true; whether all modules are available depends on the type
# of boot. UPDATE: now all modules will be available in preinit even
# in FEL boot.

# on x64 it can be interesting to look at these files as well, though
# all module loading should succeed.

mkdir -p  /sbin
rm -f     /sbin/modprobe
touch     /sbin/modprobe
chmod a+x /sbin/modprobe
cat >/sbin/modprobe <<'EOF'
#!/bin/busybox sh
echo "modprobe '$*' (attempt)" >>/tmp/dg/modprobe.early
busybox modprobe "$@"
RETV="$?"
echo "modprobe '$*' ==> $RETV" >>/tmp/dg/modprobe.early
exit "$RETV"
EOF

# on buildroot systems, also hook /bin/kmod. (UPDATE:
# disabled. actually this is not so easy to do)

:<<'DBLEOF'
if [ "$OS_RELEASE_ID" == "buildroot" ]
then
  mkdir -p            /bin/kmod.real
  cp -a     /bin/kmod /bin/kmod.real/
  rm -f     /bin/kmod
  touch     /bin/kmod
  chmod a+x /bin/kmod
  cat      >/bin/kmod <<'EOF'
#!/bin/busybox sh
echo "kmod '$0' '$*' (attempt)" >>/tmp/dg/modprobe.early
BN="$(basename "$0")"
/bin/kmod.real/"$BN" "$@"
RETV="$?"
echo "kmod '$0' '$*' ==> $RETV" >>/tmp/dg/modprobe.early
exit "$RETV"
EOF
  for i in lsmod rmmod insmod modinfo depmod
  do
    ln -vsfT ./kmod /bin/kmod.real/"$i"
  done
fi
DBLEOF

mkdir -p /etc/modprobe.d
cat >>/etc/modprobe.d/blacklist.conf <<'EOF'
blacklist evbug
EOF

###
### SSHD
###

# disable moduli shorter than 8190 bits
awk '$5 >= 8190' </etc/ssh/moduli >/etc/ssh/moduli.tmp
mv /etc/ssh/moduli{.tmp,}

###
### FIREWALL
###

echo 1 >/proc/sys/net/ipv4/conf/default/rp_filter

# the order things are done in here is pretty critical, since if we
# accidentally cut the nbd connection we will not be able to code load
# additional code that might be needed for subsequent commands that
# would re-enable nbd and thus we might not come back on at all
# (obviously, this concern applies only on x64, not on arm where all
# code is supplied in the initramfs)

# so while we would usually set the policies to DROP first and then
# add rules that ACCEPT, we will do things the other way around and
# add the rules that ACCEPT first and then set the policies to DROP

# allow anything to/from loopback

# switching to nftables. leaving old iptables rules in the file, but
# disabled.

function nft()
{
  echo "$@" >>/tmp/dg/vars/nft.cmds
}

:<<'EOF'
for j in "" 6
do
  ip"$j"tables -A INPUT  -i lo -j ACCEPT
  ip"$j"tables -A OUTPUT -o lo -j ACCEPT
done
EOF

for j in "" 6
do
  nft add table ip"$j" filter
  nft add chain ip"$j" filter INPUT   '{' type filter hook input   priority 0 ';' '}'
  nft add chain ip"$j" filter OUTPUT  '{' type filter hook output  priority 0 ';' '}'
  nft add chain ip"$j" filter FORWARD '{' type filter hook forward priority 0 ';' '}'
  nft add rule  ip"$j" filter INPUT  iifname lo counter accept
  nft add rule  ip"$j" filter OUTPUT oifname lo counter accept
done

# set up drop of non-UDP/TCP packets and selection through
# sel_INPUT/FORWARD/OUTPUT before drop. but do not add the drop rules
# yet

:<<'EOF'
for j in ""
do
  ip"$j"tables -N         all_drop_strange
  for k in UDP TCP
  do
    ip"$j"tables -A       all_drop_strange -p "$k" -j RETURN
  done
  ip"$j"tables   -A       all_drop_strange -j DROP
  
  for i in INPUT FORWARD OUTPUT
  do
    ip"$j"tables -A "$i" -j all_drop_strange
    ip"$j"tables -N         sel_"$i"
    ip"$j"tables -A "$i" -j sel_"$i"
  done
done
EOF

for j in ""
do
  nft   add chain ip"$j" filter all_drop_strange
  for k in udp tcp
  do
    nft add rule  ip"$j" filter all_drop_strange ip protocol "$k" counter return
  done
  nft   add rule  ip"$j" filter all_drop_strange counter drop
  
  for i in INPUT FORWARD OUTPUT
  do
    nft add rule  ip"$j" filter "$i" counter jump all_drop_strange
    nft add chain ip"$j" filter                   sel_"$i"
    nft add rule  ip"$j" filter "$i" counter jump sel_"$i"
  done
done

. /usr/local/src/dg_firewall.so.sh

# allow established connections

:<<'EOF'
ipt_inp established
ipt_sudo_ iptables -A inp_established -m state --state ESTABLISHED -j ACCEPT

ipt_fwd established
ipt_sudo_ iptables -A fwd_established -m state --state ESTABLISHED -j ACCEPT

ipt_out established
ipt_sudo_ iptables -A out_established -m state --state ESTABLISHED -j ACCEPT
EOF

for i in inp fwd out
do
  dg_firewall_"$i" established
  dg_firewall_sudo_ nft add rule ip filter "$i"_established ct state established counter accept
done

# allow our nbd client

if [ -f /tmp/dg/vars/using-nbd-hyperbolic ]
then
  # not needed for iptables to work but better to reserve the gid anyways
  GID_NBD_HYPERBOLIC="$(cat /tmp/dg/vars/gid-nbd-hyperbolic)"
  echo dg_nbd_hyperbolic:x:"$GID_NBD_HYPERBOLIC": >>/etc/group
  
  :<<'EOF'
  ipt_out dg_nbd_hyp
  ipt_sudo_ iptables -A out_dg_nbd_hyp -p TCP -m owner --gid-owner "$GID_NBD_HYPERBOLIC" -j ACCEPT
EOF
  
  dg_firewall_out dg_nbd_hyp
  dg_firewall_sudo_ nft add rule ip filter out_dg_nbd_hyp ip protocol tcp skgid "$GID_NBD_HYPERBOLIC" counter accept
fi

# add drop rules

for i in INPUT:INP FORWARD:FWD OUTPUT:OUT
do
  i_chain="$(echo "$i" | cut -d ":" -f 1)"
  i_short="$(echo "$i" | cut -d ":" -f 2)"
  
  for j in ""{,6}
  do
    :<<'EOF'
    ip"$j"tables -A "$i" -j LOG --log-prefix "firewall: $i died: "
    ip"$j"tables -A "$i" -j DROP
    ip"$j"tables -P "$i" DROP
EOF
    # bad packets are logged at the "debug" log level so as not to spam the console
    nft add rule ip"$j" filter "$i_chain" counter log level debug prefix '"firewall: '"$i_short"' died: "'
    nft add rule ip"$j" filter "$i_chain" counter drop
    # setting the drop policy is redundant and does not translate directly into nft
  done
done

if false # if true, drop to serial shell for debugging purposes
then
  bash -i </dev/ttyS0 &>/dev/ttyS0
fi

WHICH_NFT="$(which nft)"
"$WHICH_NFT" add table ip filter # required on 4.4.x. no idea why.
"$WHICH_NFT" -f /tmp/dg/vars/nft.cmds
CSUM_RULESET="$("$WHICH_NFT" list ruleset -nnn | sed -e 's/counter packets [0-9]\+ bytes [0-9]\+/counter/' | sha256sum - | cut -d " " -f 1)"
if [ "$CSUM_RULESET" != "a55e73c34aafab55264e1db7404fc3de822b1c8b1730e04fbf3ea4545c27e543" ]
then
  export CSUM_RULESET
  set +o xtrace
  echo "!! firewall was not loaded correctly"
  echo "!! dropping to shell"
  echo "!! you can still boot with 'exit 0' (at your own risk)"
  bash -i
fi

###
### FIXUPS
###

# common fixups

function fixups()
{
  # apply the sticky bit to /tmp/dg/vars as it's used to pass data
  # between as_{root,user} snippets
  chmod 1777 /tmp/dg/vars
}

fixups

# os-specific fixups

function emit_startup_script()
{
  cat <<'EOF'
#!/usr/bin/env bash
env -i bash -l /tmp/dg/rc_local.sh
EOF
}

function f_gentoo()
{
  emit_startup_script >/etc/local.d/rc_local.start
  chmod a+x            /etc/local.d/rc_local.start
}

function f_buildroot()
{
  emit_startup_script >/etc/init.d/S99rclocal
  chmod a+x            /etc/init.d/S99rclocal
  
  mv /etc/init.d/*sshd   /etc/init.d/_no_auto_start_sshd   || true
  mv /etc/init.d/*ntp    /etc/init.d/_no_auto_start_ntp    || true
  mv /etc/init.d/*telnet /etc/init.d/_no_auto_start_telnet || true
  
  local CLEANPATH
  CLEANPATH="$(echo {/usr{/local,},}/{s,}bin)"
  CLEANPATH="${CLEANPATH// /:}"
  echo 'export PATH='"$CLEANPATH" >/etc/profile.d/dg_path.sh
  
  if [ -f /tmp/dg/initramfs/flag_cl_emmc_lw ]
  then
    local i
    for i in {,s}gdisk
    do
      mkdir -p                                            /usr/local/sbin
      ln -vsfT ./../../../tmp/dg/contingency/emmc_lw/"$i" /usr/local/sbin/"$i"
    done
  fi
}

f_"$OS_RELEASE_ID"
unset f_{gentoo,buildroot}

# chain to the real init

exec /sbin/init "$@"
