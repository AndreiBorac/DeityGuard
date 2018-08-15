#!/bin/false

. /builds/elvopt

# change the default stage3 profile to the desktop profile, but only
# if it is 17.0. this code will have to be updated every time the
# default stage3 profile is changed (who knows whether "desktop" will
# remain the appropriate choice to make here, right?)
(
  V=17.0
  
  [ -h           /etc/portage/make.profile ]
  
  RL="$(readlink /etc/portage/make.profile)"
  
  if [ "$RL" == "../../usr/portage/profiles/default/linux/amd64/$V" ]
  then
    eselect profile set default/linux/amd64/"$V"/desktop
  fi
  
  RL="$(readlink /etc/portage/make.profile)"
  
  [ "$RL" == "../../usr/portage/profiles/default/linux/amd64/$V/desktop" ]
)

mkdir -p /builds/world
[ -f /builds/world/original-make.conf ] || cp /etc/portage/make.conf /builds/world/original-make.conf
cat /builds/world/original-make.conf | egrep -v '^USE=' >/etc/portage/make.conf

mkdir -p             /etc/portage/sets  /etc/portage/package.{use,{,un}mask,accept_keywords,license}           /etc/portage/profile/use.mask
rm -f    /var/lib/portage/world{,_sets} /etc/portage/package.{use,{,un}mask,accept_keywords,license}/_settings /etc/portage/profile/use.mask/_settings
touch    /var/lib/portage/world{,_sets} /etc/portage/package.{use,{,un}mask,accept_keywords,license}/_settings /etc/portage/profile/use.mask/_settings

cat >>/etc/portage/make.conf <<'EOF'
ACCEPT_LICENSE="-* @FREE"
CPU_FLAGS_X86="mmx mmxext sse sse2"
INPUT_DEVICES="libinput"
VIDEO_CARDS="fbdev intel i915 nouveau radeon"
USE=""
USE="${USE} bindist"
USE="${USE} glamor"
USE="${USE} X"
USE="${USE} icu"
PORTAGE_ELOG_CLASSES="log warn error"
PORTAGE_ELOG_SYSTEM="save"
PORTAGE_NICENESS="19"
EOF

if egrep -q '^#world-purge$' /builds/elvopt
then
  ( rmdir /builds/world/enable-* ) || true
fi

function wunst()
{
  if egrep -q '^#world-'"$1"'$' /builds/elvopt
  then
    mkdir -p /builds/world/enable-"$1"
  fi
  
  if [ -d /builds/world/enable-"$1" ]
  then
    return 0
  else
    return 1
  fi
}

function wunst_plain()
{
  local N
  N="$1"
  shift
  
  if wunst "$N"
  then
    echo "$*" | tr ' ' '\n' >/etc/portage/sets/"$N"
    echo @"$N" >>/var/lib/portage/world_sets
  fi
}

function wunst_alias()
{
  local QP
  QP="$1"
  
  local BN
  BN="$(basename "$QP")"
  
  if wunst "$BN"
  then
    echo "$QP" >/etc/portage/sets/"$BN"
    echo @"$BN" >>/var/lib/portage/world_sets
  fi
}

if wunst basic
then
  # packages needed to complete the build
  # gengen ensures that world-basic is always set, so it is not necessary to set it manually
  wunst_plain \
    basic \
    sys-apps/openrc \
    app-portage/gentoolkit \
    app-arch/{lzip,lzop} sys-fs/squashfs-tools \
    sys-fs/inotify-tools \
    sys-apps/dtc dev-embedded/libftdi dev-libs/libusb \
    sys-boot/syslinux \
    dev-util/dialog sys-apps/gptfdisk sys-fs/lvm2 sys-block/nbd net-dns/djbdns dev-util/strace app-crypt/gnupg sys-apps/kexec-tools dev-libs/libisoburn \
    dev-embedded/u-boot-tools dev-embedded/sunxi-tools \
    app-admin/sudo \
    app-emulation/qemu
  # gentoolkit: needed for revdep-rebuild
  # lzip/lzop: needed for buildroot
  # squashfs-tools: needed to make squashfs
  # inotify-tools: needed for zfs header tracing hack when compiling linux
  # dtc: needed for u-boot (and veysp)
  # libftdi/libusb: needed for flashpagan (libmpsse)
  # syslinux: needed for making bootable ISOs (syslinux files included in unikit)
  # also needed in unikit: dialog, gptfdisk (sgdisk), lvm2 (dmsetup), nbd, dnsip, strace, gpg, kexec, libisoburn (xorriso), u-boot-tools (mkimage), sunxi-tools (fel)
  # sudo: needed to be able to emerge on the target system
  # qemu: needed for cross compilation of libaboon applications
  cat >>/etc/portage/package.accept_keywords/_settings <<'EOF'
=dev-embedded/sunxi-tools-1.3 ~amd64
EOF
  # even wget does not work without ECC so we disable bindist even in basic
  cat >>/etc/portage/package.use/_settings <<'EOF'
dev-libs/openssl -bindist
net-misc/openssh -bindist
EOF
  cat >>/etc/portage/make.conf <<'EOF'
QEMU_SOFTMMU_TARGETS="x86_64 arm"
QEMU_USER_TARGETS="arm"
EOF
fi

if wunst selfhost
then
  # packages needed to be able to run gengen/fingen (all features) on the target host (highly recommended)
  wunst_plain selfhost sys-fs/btrfs-progs sys-process/lsof net-misc/s3cmd dev-python/python-swiftclient
fi

if wunst libressl
then
  # libressl is more secure than openssl, so it is highly recommended to enable this
  cat >>/etc/portage/make.conf <<'EOF'
USE="${USE} libressl"
EOF
  echo dev-libs/libressl >>/etc/portage/sets/basic
  echo -libressl >>/etc/portage/profile/use.mask/_settings
  # curl needs a fix to use libressl
  echo -curl_ssl_libressl >>/etc/portage/profile/use.mask/_settings
  cat >>/etc/portage/make.conf <<'EOF'
CURL_SSL="libressl"
EOF
  # take ldap away to prevent sudo from depending on cyrus which lacks libressl support just yet
  # this could be set just on sudo, but what is ldap good for anyways?
  cat >>/etc/portage/make.conf <<'EOF'
USE="${USE} -ldap"
EOF
  # some python modules need testing versions to build with libressl
  cat >>/etc/portage/package.accept_keywords/_settings <<'EOF'
=dev-python/cryptography-2.0.3 ~amd64
=dev-python/asn1crypto-0.22.0 ~amd64
EOF
fi

if wunst anybase
then
  # packages needed to be able to use the dg-any-base overlay of fingen (all features)
  wunst_plain anybase net-firewall/nftables net-misc/ntp sys-fs/cryptsetup sys-fs/zfs x11-base/xorg-server xfce-base/xfce4-meta xfce-extra/xfce4-notifyd x11-terms/xfce4-terminal
  cat >>/etc/portage/make.conf <<'EOF'
XFCE_PLUGINS="brightness clock trash"
EOF
  cat >>/etc/portage/package.accept_keywords/_settings <<'EOF'
sys-fs/zfs ~amd64

# required by net-firewall/nftables-0.7::gentoo
# required by @anybase
# required by @selected
# required by @world (argument)
>=net-libs/libnftnl-1.0.7 ~amd64
# required by @anybase
# required by @selected
# required by @world (argument)
>=net-firewall/nftables-0.7 ~amd64
EOF
  cat >>/etc/portage/package.use/_settings <<'EOF'
sys-fs/zfs kernel-builtin -rootfs
app-text/poppler -qt4
dev-util/cmake -qt4
EOF
  cat >>/etc/portage/profile/use.mask/_settings <<'EOF'
-kernel-builtin
EOF
fi

if wunst netsurf
then
  # a minimalistic browser (without JS support, so YMMV)
  wunst_alias www-client/netsurf
  cat >>/etc/portage/package.accept_keywords/_settings <<'EOF'
>=www-client/netsurf-3.6 ~amd64
EOF
  # netsurf has a bunch of libraries which are also testing
  cat >>/etc/portage/package.accept_keywords/_settings <<'EOF'
# required by www-client/netsurf-3.6::gentoo[javascript]
# required by @netsurf
# required by @selected
# required by @world (argument)
>=dev-libs/nsgenbind-0.4 ~amd64
# required by www-client/netsurf-3.6::gentoo
# required by @netsurf
# required by @selected
# required by @world (argument)
>=dev-libs/libutf8proc-1.3.1_p2-r1 ~amd64
# required by www-client/netsurf-3.6::gentoo
# required by @netsurf
# required by @selected
# required by @world (argument)
>=net-libs/libdom-0.3.1 ~amd64
# required by www-client/netsurf-3.6::gentoo
# required by @netsurf
# required by @selected
# required by @world (argument)
>=dev-libs/libcss-0.6.1 ~amd64
# required by www-client/netsurf-3.6::gentoo[svgtiny,svg]
# required by @netsurf
# required by @selected
# required by @world (argument)
>=media-libs/libsvgtiny-0.1.5 ~amd64
# required by www-client/netsurf-3.6::gentoo[bmp]
# required by @netsurf
# required by @selected
# required by @world (argument)
>=media-libs/libnsbmp-0.1.4 ~amd64
# required by www-client/netsurf-3.6::gentoo[gif]
# required by @netsurf
# required by @selected
# required by @world (argument)
>=media-libs/libnsgif-0.1.4 ~amd64
# required by net-libs/libhubbub-0.3.3::gentoo
# required by net-libs/libdom-0.3.1::gentoo
# required by www-client/netsurf-3.6::gentoo
# required by @netsurf
# required by @selected
# required by @world (argument)
>=dev-libs/libparserutils-0.2.3 ~amd64
# required by net-libs/libdom-0.3.1::gentoo
# required by www-client/netsurf-3.6::gentoo
# required by @netsurf
# required by @selected
# required by @world (argument)
>=net-libs/libhubbub-0.3.3 ~amd64
# required by www-client/netsurf-3.6::gentoo[rosprite]
# required by @netsurf
# required by @selected
# required by @world (argument)
>=media-libs/librosprite-0.1.2-r1 ~amd64
# required by www-client/netsurf-3.6::gentoo
# required by @netsurf
# required by @selected
# required by @world (argument)
>=dev-libs/libnsutils-0.0.3 ~amd64
# required by www-client/netsurf-3.6::gentoo[psl]
# required by @netsurf
# required by @selected
# required by @world (argument)
>=media-libs/libnspsl-0.1.0 ~amd64
# required by dev-libs/libcss-0.6.1::gentoo
# required by www-client/netsurf-3.6::gentoo
# required by @netsurf
# required by @selected
# required by @world (argument)
>=dev-libs/libwapcaplet-0.4.0 ~amd64
# required by www-client/netsurf-3.6::gentoo[svgtiny,svg]
# required by @netsurf
# required by @selected
# required by @world (argument)
>=media-libs/libsvgtiny-0.1.6 ~amd64
EOF
fi

if wunst firefox
then
  wunst_alias www-client/firefox
  cat >>/etc/portage/package.use/_settings <<'EOF'
www-client/firefox -bindist
>=dev-lang/python-2.7.12:2.7 sqlite
EOF
fi

if wunst chromium
then
  wunst_alias www-client/chromium
  cat >>/etc/portage/package.accept_keywords/_settings <<'EOF'
=net-libs/nodejs-8.1.1 ~amd64
EOF
  # nodejs-8.1.1 has a special patch for libressl so mask any higher version
  cat >>/etc/portage/package.mask/_settings <<'EOF'
>net-libs/nodejs-8.1.1
EOF
  cat >>/etc/portage/package.accept_keywords/_settings <<'EOF'
# required by net-libs/nodejs-8.1.1::gentoo
# required by www-client/chromium-60.0.3112.78::gentoo
# required by @chromium
# required by @selected
# required by @world (argument)
>=dev-libs/libuv-1.11.0 ~amd64
EOF
  cat >>/etc/portage/package.use/_settings <<'EOF'
www-client/chromium
>=media-libs/libvpx-1.5.0 svc postproc
>=sys-libs/zlib-1.2.11 minizip
>=media-libs/libjpeg-turbo-1.5.0 static-libs
EOF
fi

if wunst workstation
then
  # packages needed to be a workstation host
  wunst_plain workstation sys-apps/usermode-utilities net-misc/tightvnc
  cat >>/etc/portage/package.use/_settings <<'EOF'
net-misc/tigervnc server
net-misc/tightvnc server
EOF
fi

if wunst misc
then
  # miscellaneous packages that I like to use
  # you should probably replace this list with your own
  wunst_plain \
    misc \
    sys-apps/{pciutils,lm_sensors} \
    app-editors/{nano,emacs} \
    app-misc/screen \
    app-portage/{eix,elogv} \
    x11-misc/x11vnc \
    app-text/evince \
    x11-terms/xterm
fi

EMERGE_EXTRAOPTS=""
if [ "$FLAG_BACKTRACK" == "y" ]
then
  EMERGE_EXTRAOPTS="--backtrack=30"
fi
cat /etc/portage/make.conf
cat /var/lib/portage/world || true
cat /var/lib/portage/world_sets
for i in /etc/portage/sets/*
do
  cat "$i"
done
for i in /etc/portage/package.use/*
do
  cat "$i"
done
for i in /var/lib/portage/world{,_sets} /etc/portage/package.{{,un}mask,accept_keywords,license}/* /etc/portage/profile/use.mask/*
do
  cat "$i"
done
( emerge -pf --update --emptytree --deep --with-bdeps=y --newuse $EMERGE_EXTRAOPTS @world 1>/builds/world/emerge.lst ) 2>&1 | tee /tmp/log

if egrep -q '^!!!' /tmp/log
then
  cat /tmp/log
  exit 1
fi
