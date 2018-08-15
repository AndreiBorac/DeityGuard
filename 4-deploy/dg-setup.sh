#!/usr/bin/env bash

###
# COMMON
###

set -o xtrace
set -o errexit
set -o nounset
set -o pipefail
shopt -s nullglob
shopt -s failglob

GLOBAL_UBUNTU_SUITE=artful
GLOBAL_STORAGE_PASSPHRASE=x

if [ ! -f ./deityguard.tar.xz ]
then
  set +o xtrace
  echo "!! deityguard archive is required"
  echo "!! bye"
  exit 1
fi

if [ ! -f ./dg-config.sh ]
then
  set +o xtrace
  echo "!! config is required"
  echo "!! bye"
  exit 1
fi

. ./dg-config.sh

function drop_to_shell()
{
  (
    set +o xtrace
    
    echo "dropping to shell so you can $1 if needed"
    
    bash -i
  )
}

function sudo_()
{
  if [ "$EUID" != 0 ]
  then
    sudo "$@"
  else
    "$@"
  fi
}

function umount_()
{
  while sudo_ mountpoint -q "$1"
  do
    sudo_ umount "$1"
  done
}

function ithird_config_as_pusher()
{
  local ifname="$1"
  local channel="$2"
  
  sudo ifconfig "$ifname" 10.183.215."$channel"01 netmask 255.255.255.252
  sudo arp -s 10.183.215."$channel"02 02:00:00:00:00:0"$channel"
}

function ithird_config_as_client()
{
  local ifname="$1"
  local channel="$2"
  
  sudo ifconfig "$ifname" down
  sudo ifconfig "$ifname" hw ether 02:00:00:00:00:0"$channel"
  sudo ifconfig "$ifname" 10.183.215."$channel"02 netmask 255.255.255.252
}

function open_disk()
{
  local disk="$1"
  
  drop_to_shell "format $disk"
  # sudo cryptsetup luksFormat /dev/sda
  # YES
  # x
  # x
  # sudo cryptsetup luksOpen /dev/sda sda
  # x
  # sudo mkfs.ext4 /dev/mapper/sda
  # sudo cryptsetup luksClose sda
  
  mkdir -p ./persist
  
  if [ ! -b /dev/mapper/dg-setup ]
  then
    echo "$GLOBAL_STORAGE_PASSPHRASE" | sudo_ cryptsetup luksOpen "$disk" dg-setup
  fi
  
  while [ ! -b /dev/mapper/dg-setup ]
  do
    sleep 0.1
  done
  
  mkdir -p ./persist
  
  if ! sudo_ mountpoint -q ./persist
  then
    sudo_ e2fsck -pf /dev/mapper/dg-setup || sudo_ e2fsck -pf /dev/mapper/dg-setup
    sudo_ mount -o noatime /dev/mapper/dg-setup ./persist
  fi
  
  sudo_ chmod a+rwxt ./persist
}

###
# EXTERIOR
###

function f_exterior_ubuntu()
{
  local suite="$GLOBAL_UBUNTU_SUITE"
  
  if [ ! -d                    ./build/ubuntu ]
  then
    sudo_ debootstrap "$suite" ./build/ubuntu
  fi
  
  if ! sudo_ mountpoint -q     ./build/ubuntu/tmp
  then
    sudo_ mount -t tmpfs none  ./build/ubuntu/tmp
  fi
  
  if ! sudo_ mountpoint -q     ./build/ubuntu/proc
  then
    sudo_ mount --bind /proc   ./build/ubuntu/proc
  fi
  
  tee                          ./build/ubuntu/tmp/pkgs <<'EOF'
net-tools build-essential ruby haveged lzop xorriso xterm vlock
EOF
  
  tee                          ./build/ubuntu/tmp/script <<'EOF'
set -o xtrace
set -o errexit
set -o nounset
set -o pipefail
shopt -s failglob
shopt -s nullglob

cat >/etc/apt/sources.list <<'DBLEOF'
EOF
  
  tee -a                       ./build/ubuntu/tmp/script <<EOF
deb http://archive.ubuntu.com/ubuntu/  ${suite}          main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu/ ${suite}-security main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/  ${suite}-updates  main restricted universe multiverse
EOF
  
  tee -a                       ./build/ubuntu/tmp/script <<'EOF'
DBLEOF

export LC_ALL=C

apt-get       update
apt-get -y -d upgrade
apt-get -y -d install $(cat /tmp/pkgs)
EOF
  
  sudo_ chroot                 ./build/ubuntu bash /tmp/script
  
  umount_                      ./build/ubuntu/tmp
  umount_                      ./build/ubuntu/proc
  
  sudo_ tar -zf ./build/iso/ubuntu.tar.gz.tmp -C ./build/ubuntu -c .
  
  mv ./build/iso/ubuntu.tar.gz{.tmp,}
}

function f_exterior_prefetch()
(
  mkdir -p ./local_offload
  
  mkdir -p ./build/prefetch
  
  cd ./build/prefetch
  
  tar -Jxf ./../../deityguard.tar.xz
  
  (
    cd ./deityguard
    pwd
    tar -C ./../../../overlay -c . --dereference | tar -vx
  )
  
  cd ./deityguard/1-gengen
  
  mkdir -p ./local
  
  ln -vsfT ./../../../../../local_offload ./local/offload
  
  [ -d ./local/offload ]
  
  . ./aliases.sh
  
  export GENGEN_NETESC=""
  
  if [ "${2-}" == "clean" ]
  then
    #dg_locally_gengen_dl
    
    if [ -d ./build/btrfs/gentoo ]
    then
      sudo_ btrfs subvolume delete ./build/btrfs/gentoo
    fi
    
    if [ "${3-}" == "stage3" ]
    then
      sudo_ rm -f \
        ./build/btrfs/sources/special_stage3-amd64-19990101.tar.xz{,.DIGESTS.asc} \
        ./../../../../local_offload/sources/special_stage3-amd64-19990101.tar.xz{,.DIGESTS.asc} \
        ./../../../../local_offload/sources/special_gentoo-release-amd64
    fi
    
    exit
  fi
  
  if [ ! -d ./build/btrfs/gentoo ]
  then
    dg_locally_gengen_gentoo_stage3
  fi
  
  if [ "${2-}" == "-kill-portage" ]
  then
    touch ./local/kill_portage_sched
  fi
  
  local EXTRAOPTS=""
  if [ "${2-}" == "prune" ]
  then
    EXTRAOPTS="prune"
  fi
  
  dg_locally_gengen_gentoo_world_dryrun world-{purge,libressl,selfhost,anybase,netsurf,firefox,chromium,workstation,misc} $EXTRAOPTS
)

function f_exterior_dump_interior_config()
{
  echo "DG_SETUP_ROLE=interior"
  cat ./dg-config.sh | egrep '^DG_SETUP_INTERIOR'
}

function f_exterior_transfer()
{
  sudo_ killall -w NetworkManager || true
  ithird_config_as_pusher "$DG_SETUP_EXTERIOR_ITHIRD_INTERFACE_TO_INTERIOR" 1
  
  mkdir -p                  ./build/transfer
  umount_                   ./build/transfer
  sudo_ mount -t tmpfs none ./build/transfer
  
  (
    cd ./build/transfer
    tar -Jxf ./../../deityguard.tar.xz
  )
  
  local RL
  RL="$(readlink -f ./local_offload/sources)"
  mkdir -p                  ./build/transfer/transmit
  cp -rs "$RL"              ./build/transfer/transmit/dg_setup_sources
  
  ln -vsfT ./../../../deityguard.tar.xz ./build/transfer/transmit/deityguard.tar.xz
  
  tar -zf ./build/transfer/transmit/overlay.tar.gz -C ./overlay -c . --dereference
  
  cat <./dg-setup.sh >./build/transfer/transmit/dg-setup.sh
  chmod a+x           ./build/transfer/transmit/dg-setup.sh
  
  f_exterior_dump_interior_config >./build/transfer/transmit/dg-config.sh
  
  mkdir -p      ./local_transfer
  
  if [ "${2-}" == "clean" ]
  then
    echo 0     >./local_transfer/rel
  fi
  
  if [ ! -f     ./local_transfer/rel ]
  then
    echo 0     >./local_transfer/rel
  fi
  
  local MT
  MT="$(cat     ./local_transfer/rel)"
  
  if [ "${2-}" != "preview" ]
  then
    tar -C ./build/transfer/transmit -c . --verbose --dereference --newer '@'"$MT" --owner=0 --group=0 |\
      ./build/transfer/deityguard/3-ithird/pusher/pusher.rb 1
    
    date "+%s" >./local_transfer/rel
  fi
}

function f_exterior()
{
  [ -d ./build ] || sudo_ mkdir -m 0000 ./build
  sudo_ mountpoint -q ./build || sudo_ mount -t tmpfs none ./build
  
  mkdir -p ./build/iso/build
  
  if [ ! -f ./build/iso/ubuntu.tar.gz ]
  then
    f_exterior_ubuntu
  fi
  
  cat <./deityguard.tar.xz >./build/iso/deityguard.tar.xz
  
  cat <./dg-setup.sh >./build/iso/dg-setup.sh
  chmod a+x           ./build/iso/dg-setup.sh
  
  f_exterior_dump_interior_config >./build/iso/dg-config.sh
  
  if [ "${1-}" == "isowren" ]
  then
    (
      cd ./build/iso
      sudo_ xorriso -dev "$DG_SETUP_EXTERIOR_ISO_DEV" -blank as_needed -add . -- -commit_eject all
    )
  fi
  
  if [ "${1-}" == "prefetch" ]
  then
    f_exterior_prefetch "$@"
  fi
  
  if [ "${1-}" == "transfer" ]
  then
    f_exterior_transfer "$@"
  fi
}

###
# INTERIOR
###

function f_interior()
{
  if [ "${1-}" == "phase2" ]
  then
    f_interior_phase2
    return
  fi
  
  [ -d ./build ] || sudo_ mkdir -m 0000 ./build
  sudo_ mountpoint -q ./build || sudo_ mount -t tmpfs none ./build
  
  cd ./build
  
  if [ ./../ubuntu.tar.gz -nt ./rel_ubuntu ]
  then
    (
      mkdir -p ./ubuntu
      cd ./ubuntu
      sudo_ tar -zxf ./../../ubuntu.tar.gz
    )
    
    touch ./rel_ubuntu
  fi
  
  local i
  for i in etc/apt/sources.list var/lib/apt var/cache/apt
  do
    sudo_ mountpoint -q /"$i" || sudo_ mount --bind ./ubuntu/"$i" /"$i"
  done
  
  function getpkg()
  {
    if ! which "$1"
    then
      sudo apt-get -y install "$2"
    fi
  }
  
  getpkg ifconfig net-tools
  
  getpkg gcc build-essential
  
  local i
  for i in ruby haveged lzop xorriso xterm vlock
  do
    getpkg "$i" "$i"
  done
  
  open_disk "$DG_SETUP_INTERIOR_DISK"
  
  cd ./persist
  
  tar -Jxf ./../../deityguard.tar.xz
  
  mkdir -p ./ithird
  
  # kill any old instances
  sudo_ killall -w ithird_udpcap || true
  sudo_ killall -w ruby || true
  sudo_ killall -w xterm || true
  
  # prepare third idea client interface
  sudo_ killall -w NetworkManager || true
  ithird_config_as_client "$DG_SETUP_INTERIOR_ITHIRD_INTERFACE_TO_EXTERIOR" 1
  
  # run third idea client
  xterm -title dg_ithird -e 'cd ./ithird ; sudo bash ./../deityguard/3-ithird/client/client.rb 1 ; bash -i' </dev/null &>/dev/null & disown
  
  drop_to_shell "wait for transfer completion"
  
  cd ./ithird
  
  ./dg-setup.sh phase2
}

function f_interior_phase2()
{
  cd ./..
  
  mkdir -p ./phase2
  
  cd ./phase2
  
  tar -Jxf ./../ithird/deityguard.tar.xz
  
  cd ./deityguard
  
  tar -vzxf ./../../ithird/overlay.tar.gz
  
  cd ./1-gengen
  
  mkdir -p ./local/offload
  
  ln -vsfT ./../../../../../ithird/dg_setup_sources/ ./local/offload/sources
  
  (
    export GENGEN_NETESC=""
    drop_to_shell "interface with gengen"
  )
  
  cd ./../2-fingen
  
  mkdir -p ./local
  ln -vsfT ./../../1-gengen/build/btrfs/gentoo/builds/rootfs-mirror/ ./local/gengen-build-btrfs-gentoo-builds-rootfs-mirror
  ln -vsfT ./../../1-gengen/build/btrfs/gentoo/builds/unikit.tzo ./local/gengen-build-btrfs-gentoo-builds-unikit.tzo
  mkdir -p ./local/output
  echo x64 >./local/hostarch
  
  drop_to_shell "interface with fingen"
}

###
# HTTPSERV
###

function f_httpserv()
{
  [ -d ./build ] || sudo_ mkdir -m 0000 ./build
  sudo_ mountpoint -q ./build || sudo_ mount -t tmpfs none ./build
  
  cd ./build
  
  tar -Jxf ./../deityguard.tar.xz
  
  if [ ! -f /tmp/did-apt-update ]
  then
    local suite="$GLOBAL_UBUNTU_SUITE"
    
    sudo_ tee /etc/apt/sources.list <<EOF
deb http://archive.ubuntu.com/ubuntu/  ${suite}          main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu/ ${suite}-security main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/  ${suite}-updates  main restricted universe multiverse
EOF
    
    sudo_ apt-get update
    
    touch   /tmp/did-apt-update
  fi
  
  function getpkg()
  {
    if ! which "$1"
    then
      sudo apt-get -y install "$2"
    fi
  }
  
  getpkg ifconfig net-tools
  
  getpkg gcc build-essential
  
  local i
  for i in ruby xterm vlock
  do
    getpkg "$i" "$i"
  done
  
  open_disk "$DG_SETUP_HTTPSERV_DISK"
  
  cd ./persist
  
  # kill any old instances
  sudo_ killall -w ithird_udpcap || true
  sudo_ killall -w ruby || true
  sudo_ killall -w busybox_httpd || true
  sudo_ killall -w xterm || true
  
  # prepare third idea client interface
  sudo_ killall -w NetworkManager || true
  ithird_config_as_client "$DG_SETUP_HTTPSERV_ITHIRD_INTERFACE_TO_INTERIOR" 2
  
  # run third idea client
  xterm -title dg_ithird -e 'sudo bash ./../deityguard/3-ithird/client/client.rb 2 ; bash -i' </dev/null &>/dev/null & disown
  
  # prepare LAN interface
  sudo_ ifconfig "$DG_SETUP_HTTPSERV_LAN_INTERFACE":dgsetup "$DG_SETUP_HTTPSERV_LAN_FIXED_ADDRESS" netmask "$DG_SETUP_HTTPSERV_LAN_FIXED_NETMASK"
  
  # run busybox http server
  rm -f /tmp/busybox_httpd
  cp "$(which busybox)" /tmp/busybox_httpd
  xterm -title dg_httpd -e 'sudo /tmp/busybox_httpd httpd -fvv -c /dev/null -h . ; bash -i' </dev/null &>/dev/null & disown
}

f_"$DG_SETUP_ROLE" "$@"

set -o xtrace
echo "+OK (dg-setup.sh)"
