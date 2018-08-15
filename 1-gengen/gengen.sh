#!/usr/bin/env bash

set -o xtrace
set -o errexit
set -o nounset
set -o pipefail
shopt -s failglob
shopt -s nullglob

OPTION_VERSION_LINUX_LIBRE_LTS_A=4.4.116
OPTION_VERSION_LINUX_LIBRE_LTS_B=4.14.20
OPTION_VERSION_LINUX_LIBRE_X64="$OPTION_VERSION_LINUX_LIBRE_LTS_A"
OPTION_VERSION_LINUX_LIBRE_BPI="$OPTION_VERSION_LINUX_LIBRE_LTS_A"
OPTION_VERSION_LINUX_LIBRE_ROK="$OPTION_VERSION_LINUX_LIBRE_LTS_B"
OPTION_VERSION_U_BOOT=2016.11
OPTION_VERSION_COREBOOT_COMMIT=687b023d970327e2d4994e5fb170edf9a1e7180f # b002
OPTION_VERSION_COREBOOT_COMMIT_SHA=8281c9dad08c7f67ba1d4e2f44711e59579a47c8685ddfeea30e870ecf28bc58
OPTION_VERSION_COREBOOT_VBOOT_COMMIT=3d25d2b4ba7886244176aa8c429fdac2acf7db3e # b002
OPTION_VERSION_COREBOOT_VBOOT_COMMIT_SHA=8020d4ffc6b20f75eea15a17a58342e910725be4b4d99231e4a9800523392c68
OPTION_VERSION_COREBOOT_SEABIOS_COMMIT=9332965e1c46ddf4e19d7050f1e957a195c703fa
OPTION_VERSION_COREBOOT_SEABIOS_COMMIT_SHA=e4acb5dd84b41e0c69ba6b1462f0efd8704d4e764309447496f59246d90943e6
OPTION_VERSION_ICH9GEN_COMMIT=8b32ef0321e40695e348296c5189ea2c7346f05d
OPTION_VERSION_ICH9GEN_COMMIT_SHA=7327a4751cf4c191c94bc06a3d43a49b67a81df3f3abc4c11c3de2941ef1cd86
OPTION_VERSION_LIBMPSSE_COMMIT=a2eafa24a3446a711b13523ec06c17b5a1c6cdc1
OPTION_VERSION_LIBMPSSE_COMMIT_SHA=dbf0e682981403d59aa7a38ed9603ac5809fd530065e28adc1254558743984cb
OPTION_VERSION_BUILDROOT=2017.11
OPTION_VERSION_BUILDROOT_SHA=ad6928741afdc5503ef849d1482825b5c31583e467e19212a303e1b25514a3b4
OPTION_VERSION_XZ_EMBEDDED=20130513
OPTION_VERSION_XZ_EMBEDDED_SHA=19577e9f68a2d4e08bb5564e3946e35c6323276cb6749c101c86e26505e3bf0e
OPTION_VERSION_ZFS=0.7.6
OPTION_VERSION_ZFS_SPL_SHA=648148762969d1ee94290c494c4f022aeacabe0e84cddf65906af608be666f95
OPTION_VERSION_ZFS_ZFS_SHA=1687f4041a990e35caccc4751aa736e8e55123b81d5f5a35b11916d9e580c23d

OPTION_U_BOOT_BOARD_NAME_LIST=(Bananapi)
OPTION_ARM_BOOTSD_DTB_NAME=sun7i-a20-bananapi.dtb

# a specific mirror is used here to prevent queries for
# snaphost-latest.tar.xz* from spanning multiple servers which is
# likely to produce splices as the servers do not update at the same
# time
MIRROR_DISTFILES_GENTOO_ORG=gentoo.ussg.indiana.edu

MIRROR_LINUX_LIBRE=http://linux-libre.fsfla.org/pub/linux-libre/releases
# sometimes linux-libre.fsfla.org gets really, really, really slow ...
MIRROR_LINUX_LIBRE=http://linux-libre.gnulinux.si/releases

CLEANPATH="$(echo {/usr{/local,},}/{s,}bin | tr ' ' ':')"

ROOTCLEAN="n"

if [ "${1-}" == "rootclean" ]
then
  ROOTCLEAN="y"
  shift
fi

ARG1="${1-}"
ARG2="${2-}"

if [ "${CORES-}" == "" ]
then
  CORES="$(nproc)"
fi

function kill_mounts_below()
{
  A="$1"
  AL="$(readlink -f "$A")"
  while [ 1 ]
  do
    MP="$(cat /proc/mounts | ( grep -F " $AL" || true ) | tail -n 1 | cut -d " " -f 2)"
    if [ "$MP" == "" ]
    then
      break
    fi
    AN="${#AL}"
    if [ "${MP:0:AN}" != "$AL" ]
    then
      exit 1
    fi
    sudo umount "$MP" || sleep 1
  done
}

# when invoked with -i, inspect a file
if [ "$ARG1" == "-i" ]
then
  sudo cat ./build/btrfs/gentoo/"$ARG2"
  exit
fi

function btrfsclean()
{
  local NAME
  for NAME in "$@"
  do
    if [ -d ./"$NAME" ]
    then
      if ! btrfs subvolume delete ./"$NAME"
      then
        rm -rf --one-file-system ./"$NAME"
        mv ./"$NAME" ./"$(dirname "$NAME")"/old-"$(basename "$NAME")"-"$(date +%s.%Ns)"
      fi
      [ ! -d ./"$NAME" ]
    fi
  done
}

# when invoked with -j, jump into gentoo chroot
if [ "$ARG1" == "-j" ]
then
  set -x
  FROM=gentoo
  if [ -d ./build/btrfs/scratch-"$FROM" ]
  then
    kill_mounts_below ./build/btrfs/scratch-"$FROM"
    sudo bash -c "$(declare -p FROM)"$'\n'"$(declare -f btrfsclean)"$'\n''btrfsclean ./build/btrfs/scratch-"$FROM"'
    [ -d ./build/btrfs/scratch-"$FROM" ] && exit 1
  fi
  sudo btrfs subvolume snapshot ./build/btrfs/gentoo ./build/btrfs/scratch-"$FROM"
  cd ./build/btrfs/scratch-"$FROM"
  sudo mount -t tmpfs none ./tmp
  sudo mount -t proc none ./proc
  sudo mount --rbind /sys ./sys
  sudo mount --make-rslave ./sys
  sudo mount --rbind /dev ./dev
  sudo mount --make-rslave ./dev
  sudo mkdir -p ./run/shm
  sudo mount -t tmpfs none ./run/shm
  
  if [ "${GENGEN_NETESC+set}" == "set" ]
  then
    sudo $GENGEN_NETESC env -i PATH="$CLEANPATH" chroot . bash -i
  else
    sudo                env -i PATH="$CLEANPATH" chroot . bash -i
  fi
  kill_mounts_below .
  exit
fi

# when invoked with -w, print dependencies
if [ "$ARG1" == "-w" ]
then
  set -x
  FROM=gentoo
  if [ -d ./build/btrfs/scratch-"$FROM" ]
  then
    kill_mounts_below ./build/btrfs/scratch-"$FROM"
    sudo bash -c "$(declare -p FROM)"$'\n'"$(declare -f btrfsclean)"$'\n''btrfsclean ./build/btrfs/scratch-"$FROM"'
    [ -d ./build/btrfs/scratch-"$FROM" ] && exit 1
  fi
  sudo btrfs subvolume snapshot ./build/btrfs/gentoo ./build/btrfs/scratch-"$FROM"
  cd ./build/btrfs/scratch-"$FROM"
  sudo mount -t tmpfs none ./tmp
  sudo mount -t proc none ./proc
  sudo mount --rbind /sys ./sys
  sudo mount --make-rslave ./sys
  sudo mount --rbind /dev ./dev
  sudo mount --make-rslave ./dev
  sudo mkdir -p ./run/shm
  sudo mount -t tmpfs none ./run/shm
  sudo env -i PATH="$CLEANPATH" chroot . bash -c 'emerge --verbose --pretend --depclean --with-bdeps=y' | sudo tee ./../gentoo/builds/world/dependencies
  kill_mounts_below .
  exit
fi

# when invoked with -l, dump the latest world build log
if [ "$ARG1" == "-l" ]
then
  FL="$(find ./build/btrfs/gentoo/var/log -maxdepth 1 -type f | ( egrep '^\./build/btrfs/gentoo/var/log/emg\.[0-9]+\.[0-9]+s$' || true ) | LC_ALL=C sort | tail -n 1)"
  [ -f "$FL" ]
  cat "$FL"
  exit
fi

FAKEDATE=19990101

if [ "$ARG1" == "-kill-stage3" ]
then
  sudo mkdir -p ./local/offload/old-stage3
  
  for ARCHFULL in amd64
  do
    for i in ""{,.DIGESTS.asc}
    do
      sudo mv  ./local/offload/sources/special_stage3-"$ARCHFULL"-"$FAKEDATE".tar.xz"$i" ./local/offload/old-stage3/ || true
      sudo rm -f ./build/btrfs/sources/special_stage3-"$ARCHFULL"-"$FAKEDATE".tar.xz"$i" || true
    done
  done
  
  exit
fi

function kill_portage()
{
  sudo mkdir -p ./local/offload/old-portage
  
  for i in ""{,.md5sum,.gpgsig}
  do
    sudo mv  ./local/offload/sources/special_portage-"$FAKEDATE".tar.xz"$i" ./local/offload/old-portage/ || true
    sudo rm -f ./build/btrfs/sources/special_portage-"$FAKEDATE".tar.xz"$i" || true
  done
}

if [ "$ARG1" == "-kill-portage" ]
then
  kill_portage
  exit
fi

if [ "$ARG1" == "-kill-portage-sched" ]
then
  sudo touch ./local/kill_portage_sched
  exit
fi

FORCEPORTAGE=n

if [ -f ./local/kill_portage_sched ]
then
  kill_portage
  sudo rm -f ./local/kill_portage_sched
  FORCEPORTAGE=y
  # continue ...
fi

UNIKITMAYBEYESFILE=n

if [ -f ./local/unikitmaybeyes ]
then
  UNIKITMAYBEYESFILE=y
fi

ALLARMVERS=(ca7 ca17)
readonly ALLARMVERS

if [ "$ARG1" == "brarm-dirclean" ]
then
  for i in "${ALLARMVERS[@]}"
  do
    sudo chroot ./build/btrfs/gentoo bash -c 'set -o xtrace && cd /builds/brarm-"'"$i"'"/buildroot-* && make "'"$ARG2"'"-dirclean O=/builds/brarm-output-"'"$i"'"' || true
  done
  
  exit
fi

if [ "$ARG1" == "brarm-dirclean-ca17" ]
then
  for i in ca17
  do
    sudo chroot ./build/btrfs/gentoo bash -c 'set -o xtrace && cd /builds/brarm-"'"$i"'"/buildroot-* && make "'"$ARG2"'"-dirclean O=/builds/brarm-output-"'"$i"'"' || true
  done
  
  exit
fi

function shell_adjust()
{
  [ -z "${SHELL_RESUME_TO+x}" ] # nesting not supported
  set +o xtrace
  #( ( set +o ; shopt -p ) | tr '\n' ' ' ; echo ) >&2
  SHELL_RESUME_TO="$(set +o ; shopt -p)"
  #( echo "SHELL_RESUME_TO=$SHELL_RESUME_TO" | tr '\n' ' ' ; echo ) >&2
  "$@"
  set -o xtrace
}

function shell_resume()
{
  set +o xtrace
  #( echo "SHELL_RESUME_TO=$SHELL_RESUME_TO" | tr '\n' ' ' ; echo ) >&2
  eval "$SHELL_RESUME_TO"
  set -o xtrace
  unset SHELL_RESUME_TO
  #( set +o ; shopt -p ) | tr '\n' ' ' >&2
  set -o errexit
}

sudo which mkfs.btrfs
#sudo which lzop
#sudo which lzip
sudo which fuser
sudo which lsof

# when invoked with -c, clean up from a previous run (also used internally)
if [ "$ARG1" == "-c" ]
then
  for i in ./build ./build/btrfs
  do
    if sudo mountpoint -q "$i"
    then
      X="$(readlink -f "$i")"
      sudo fuser -k -9 -M -m "$X" || true
    fi
  done
  
  shell_adjust shopt -u failglob
  for i in ./build/btrfs/*
  do
    if [ -d "$i" ]
    then
      X="$(readlink -f "$i")"
      sudo lsof -nP 2>/dev/null | ( egrep "$X" || true ) | sed -e 's/[ \t]\+/ /g' | cut -d " " -f 2 | sort | uniq | ( xargs sudo kill -9 || true )
    fi
  done
  shell_resume
  
  kill_mounts_below ./build
  
  exit
fi

function export_loadable_variables()
{
  declare -p "$@"
}

function export_loadable_variables_ifset()
{
  local i
  for i in "$@"
  do
    if [ "${!i+set}" == "set" ]
    then
      export_loadable_variables "$i"
    fi
  done
}

if [ "$ROOTCLEAN" != "y" ]
then
  # first clean up from any previous run
  "$0" -c
  
  # create build directory
  [ -d ./build ] || sudo mkdir -m 0000 ./build
  sudo mountpoint -q ./build || sudo mount -t tmpfs none ./build
  sudo mountpoint -q ./build
  
  # copy script into build directory
  cat ./"$0" >./build/gengen
  
  # create a file with loadable variables
  HOMEDIR="$(readlink -f .)"
  OFFLOADDIR="$(readlink -f "$HOMEDIR"/local/offload)"
  BUILDDIR="$(readlink -f ./build)"
  export_loadable_variables HOMEDIR OFFLOADDIR BUILDDIR CORES FORCEPORTAGE UNIKITMAYBEYESFILE  >./build/sysgen-loadable-variables
  export_loadable_variables_ifset GENGEN_NETESC                                               >>./build/sysgen-loadable-variables
  SYSGENLDV="$(readlink -f ./build/sysgen-loadable-variables)"
  
  # set umask appropriately (for building on void linux)
  umask 0002
  
  # exec as root in a clean environment
  exec sudo env -i PATH="$CLEANPATH" bash "$BUILDDIR"/gengen rootclean "$SYSGENLDV" "$@"
fi

SYSGENLDV="$1"
shift
. "$SYSGENLDV"

cd "$BUILDDIR"

function fatal()
{
  echo "$@"
  exit 1
}

if [ !                            -f "$OFFLOADDIR"/backing.img ]
then
  truncate -s $(( (128*(1024**3)) )) "$OFFLOADDIR"/backing.img
  mkfs.btrfs -f                      "$OFFLOADDIR"/backing.img
  #mkfs.ext4 -F                      "$OFFLOADDIR"/backing.img
fi

if ! [ -c /dev/loop-control ]
then
  modprobe loop
fi

mkdir -p ./btrfs
mountpoint -q ./btrfs && exit 1
mount -t btrfs -o noatime,nodiratime,nobarrier "$OFFLOADDIR"/backing.img ./btrfs
#mount -t ext4 -o noatime,nodiratime "$OFFLOADDIR"/backing.img ./btrfs
mountpoint -q ./btrfs
btrfs filesystem resize max ./btrfs

BTRFSDIR="$(readlink -f ./btrfs)"

function gpg__()
{
  if which gpg &>/dev/null
  then
    gpg  "$@"
  else
    gpg2 "$@"
  fi
}

function gpg_()
{
  gpg__ --homedir "$BUILDDIR"/.gnupg --no-default-keyring --keyring my_keyring "$@"
}

function gpg_keysel()
{
  rm -f "$BUILDDIR"/.gnupg/my_keyring
  gpg_ --import <"$HOMEDIR"/files/pubkey/"$1"
}

rm -f "$BUILDDIR"/touch.lst

function wget_()
{
  $GENGEN_NETESC wget "$@"
}

function getsrc()
{
  echo "$1" >>"$BUILDDIR"/touch.lst
  
  if [ ! -f                   "$OFFLOADDIR"/sources/"$1" ]
  then
    wget_ -O"$OFFLOADDIR"/tmp "$2"
    mv      "$OFFLOADDIR"/tmp "$OFFLOADDIR"/sources/"$1"
  fi
  
  mkdir -p                            "$BTRFSDIR"/sources
  
  if [ "$OFFLOADDIR"/sources/"$1" -nt "$BTRFSDIR"/sources/"$1" ]
  then
    cp "$OFFLOADDIR"/sources/"$1"     "$BTRFSDIR"/sources/"$1"
  fi
}

function getsrc_bn()
{
  local BN
  BN="$(basename "$1")"
  getsrc "$BN" "$1"
}

function getsrc_bn_pf()
{
  local PF
  PF="$1"
  local BN
  BN="$(basename "$2")"
  getsrc "$PF""$BN" "$2"
}

mkdir -p "$OFFLOADDIR"/sources

for ARCH in amd64:amd64
do
  ARCHFMLY="$(echo "$ARCH" | cut -d : -f 1)"
  ARCHFULL="$(echo "$ARCH" | cut -d : -f 2)"
  
  if [ ! -f "$OFFLOADDIR"/sources/special_gentoo-release-"$ARCHFULL" ]
  then
    wget_ -O- http://"$MIRROR_DISTFILES_GENTOO_ORG"/releases/"$ARCHFMLY"/autobuilds/latest-stage3-"$ARCHFULL".txt | egrep '^[0-9]' | egrep -o '^[^/]+' | head -n 1 >"$OFFLOADDIR"/sources/special_gentoo-release-"$ARCHFULL".tmp
    mv "$OFFLOADDIR"/sources/special_gentoo-release-"$ARCHFULL"{.tmp,}
  fi
  
  echo special_gentoo-release-"$ARCHFULL" >>"$BUILDDIR"/touch.lst
  
  ARCHRELD="$(cat "$OFFLOADDIR"/sources/special_gentoo-release-"$ARCHFULL")"
  
  for i in ""{,.DIGESTS.asc}
  do
    getsrc special_stage3-"$ARCHFULL"-"$FAKEDATE".tar.xz"$i" http://"$MIRROR_DISTFILES_GENTOO_ORG"/releases/"$ARCHFMLY"/autobuilds/"$ARCHRELD"/stage3-"$ARCHFULL"-"$ARCHRELD".tar.xz"$i"
  done
done

for i in ""{.md5sum,.gpgsig,} # fetch the archive last to reduce the chances of a splice
do
  getsrc special_portage-"$FAKEDATE".tar.xz"$i" http://"$MIRROR_DISTFILES_GENTOO_ORG"/snapshots/portage-latest.tar.xz"$i"
done

for OPTION_VERSION_LINUX_LIBRE in "$OPTION_VERSION_LINUX_LIBRE_X64" "$OPTION_VERSION_LINUX_LIBRE_BPI" "$OPTION_VERSION_LINUX_LIBRE_ROK"
do
  for i in ""{,.sign}
  do
    getsrc_bn_pf special_ "$MIRROR_LINUX_LIBRE"/"$OPTION_VERSION_LINUX_LIBRE"-gnu/linux-libre-"$OPTION_VERSION_LINUX_LIBRE"-gnu.tar.xz"$i"
  done
done

unset OPTION_VERSION_LINUX_LIBRE

for i in ""{,.sig}
do
  getsrc_bn_pf special_ ftp://ftp.denx.de/pub/u-boot/u-boot-"$OPTION_VERSION_U_BOOT".tar.bz2"$i"
done

getsrc_bn_pf special_for_zfs_ https://github.com/zfsonlinux/zfs/releases/download/zfs-"$OPTION_VERSION_ZFS"/spl-"$OPTION_VERSION_ZFS".tar.gz
getsrc_bn_pf special_for_zfs_ https://github.com/zfsonlinux/zfs/releases/download/zfs-"$OPTION_VERSION_ZFS"/zfs-"$OPTION_VERSION_ZFS".tar.gz

getsrc special_coreboot-"$OPTION_VERSION_COREBOOT_COMMIT".tar.gz                 https://github.com/coreboot/coreboot/archive/"$OPTION_VERSION_COREBOOT_COMMIT".tar.gz
getsrc special_coreboot-vboot-"$OPTION_VERSION_COREBOOT_VBOOT_COMMIT".tar.gz     https://github.com/coreboot/vboot/archive/"$OPTION_VERSION_COREBOOT_VBOOT_COMMIT".tar.gz
getsrc special_coreboot-seabios-"$OPTION_VERSION_COREBOOT_SEABIOS_COMMIT".tar.gz https://github.com/coreboot/seabios/archive/"$OPTION_VERSION_COREBOOT_SEABIOS_COMMIT".tar.gz
getsrc special_ich9gen-"$OPTION_VERSION_ICH9GEN_COMMIT".tar.gz                   https://github.com/AndreiBoracMirrors/ich9gen/archive/"$OPTION_VERSION_ICH9GEN_COMMIT".tar.gz
getsrc special_libmpsse-"$OPTION_VERSION_LIBMPSSE_COMMIT".tar.gz                 https://github.com/devttys0/libmpsse/archive/"$OPTION_VERSION_LIBMPSSE_COMMIT".tar.gz

# the list of urls here can be generated by running, in coreboot's archive: ./util/crossgcc/buildgcc -u 2>/dev/null | sed -e 's/[ \t][ \t]*/ /g'
for i in http://ftpmirror.gnu.org/gmp/gmp-6.1.2.tar.xz http://ftpmirror.gnu.org/mpfr/mpfr-3.1.5.tar.xz http://ftpmirror.gnu.org/mpc/mpc-1.0.3.tar.gz http://www.mr511.de/software/libelf-0.8.13.tar.gz http://ftpmirror.gnu.org/gcc/gcc-6.3.0/gcc-6.3.0.tar.bz2 http://ftpmirror.gnu.org/binutils/binutils-2.28.tar.bz2 http://ftpmirror.gnu.org/gdb/gdb-8.0.tar.xz https://acpica.org/sites/acpica/files/acpica-unix2-20161222.tar.gz http://www.python.org/ftp/python/3.5.1/Python-3.5.1.tar.xz http://downloads.sourceforge.net/sourceforge/expat/expat-2.2.1.tar.bz2 http://llvm.org/releases/4.0.0/llvm-4.0.0.src.tar.xz http://llvm.org/releases/4.0.0/cfe-4.0.0.src.tar.xz http://llvm.org/releases/4.0.0/compiler-rt-4.0.0.src.tar.xz http://llvm.org/releases/4.0.0/clang-tools-extra-4.0.0.src.tar.xz http://ftpmirror.gnu.org/make/make-4.2.1.tar.bz2 https://cmake.org/files/v3.9/cmake-3.9.0-rc3.tar.gz
do
  getsrc_bn_pf special_for_coreboot_ "$i"
done

getsrc_bn_pf special_ https://buildroot.org/downloads/buildroot-"$OPTION_VERSION_BUILDROOT".tar.bz2
. "$HOMEDIR"/files/buildroot-dependencies

getsrc_bn_pf special_for_unpranker_ https://tukaani.org/xz/xz-embedded-"$OPTION_VERSION_XZ_EMBEDDED".tar.gz

FLAG_STAGE3=n
FLAG_PORTAGE=n
FLAG_WORLD=n

FLAG_LINUX=n
FLAG_LINUX_MIN=n
FLAG_SQUASHFS=n

FLAG_CA7=n
FLAG_CA17=n

FLAG_BRARM=n

FLAG_ARM_LINUX_BPI=n
FLAG_ARM_LINUX_ROK=n

FLAG_COREBOOT=n
FLAG_ARM_U_BOOT=n

FLAG_NBD_HYPERBOLIC=n
FLAG_UNPRANKER=n

FLAG_INSTIGATOR=n
FLAG_SAFEPIPE=n
FLAG_MURMUR=n
FLAG_LINUXTOOLS=n
FLAG_FANMAN=n
FLAG_GPTIZE=n

FLAG_FLASHPAGAN=n

FLAG_UNIKIT=n
FLAG_UNIKITMAYBE=n

FLAG_DRYRUN=n
FLAG_BACKTRACK=n
FLAG_NOCLEAN=n
FLAG_ONCEOVER=n
FLAG_PRISTINE=n
FLAG_SOURCES=n
FLAG_LIGHTSOUT=n

FLAG_PRUNE=n

for i in "$@"
do
  [ "$i" == "stage3"          ] && FLAG_STAGE3=y && FLAG_PORTAGE=y && FLAG_WORLD=y
  [ "$i" == "portage"         ]                  && FLAG_PORTAGE=y && FLAG_WORLD=y
  [ "$FORCEPORTAGE" == "y"    ]                  && FLAG_PORTAGE=y && FLAG_WORLD=y
  [ "$i" == "world"           ]                                    && FLAG_WORLD=y
  
  [ "$i" == "linux"           ] && FLAG_LINUX=y
  [ "$i" == "linux-min"       ] && FLAG_LINUX_MIN=y
  [ "$i" == "squashfs"        ] && FLAG_SQUASHFS=y
  
  [ "$i" == "ca7"             ] && FLAG_CA7=y
  [ "$i" == "ca17"            ] && FLAG_CA17=y
  
  [ "$i" == "brarm"           ] && FLAG_BRARM=y
  
  [ "$i" == "arm-linux-bpi"   ] && FLAG_ARM_LINUX_BPI=y
  [ "$i" == "arm-linux-rok"   ] && FLAG_ARM_LINUX_ROK=y
  
  [ "$i" == "coreboot"        ] && FLAG_COREBOOT=y
  [ "$i" == "arm-u-boot"      ] && FLAG_ARM_U_BOOT=y
  
  [ "$i" == "nbd-hyperbolic"  ] && FLAG_NBD_HYPERBOLIC=y
  [ "$i" == "unpranker"       ] && FLAG_UNPRANKER=y
  
  [ "$i" == "instigator"      ] && FLAG_INSTIGATOR=y
  [ "$i" == "safepipe"        ] && FLAG_SAFEPIPE=y
  [ "$i" == "murmur"          ] && FLAG_MURMUR=y
  [ "$i" == "linuxtools"      ] && FLAG_LINUXTOOLS=y
  [ "$i" == "fanman"          ] && FLAG_FANMAN=y
  [ "$i" == "gptize"          ] && FLAG_GPTIZE=y
  
  [ "$i" == "flashpagan"      ] && FLAG_FLASHPAGAN=y
  
  [ "$i" == "unikit"          ] && FLAG_UNIKIT=y
  [ "$i" == "unikitmaybe"     ] && FLAG_UNIKITMAYBE=y
  
  [ "$i" == "dryrun"          ] && FLAG_DRYRUN=y
  [ "$i" == "backtrack"       ] && FLAG_BACKTRACK=y
  [ "$i" == "noclean"         ] && FLAG_NOCLEAN=y
  [ "$i" == "onceover"        ] && FLAG_ONCEOVER=y
  [ "$i" == "pristine"        ] && FLAG_PRISTINE=y
  [ "$i" == "sources"         ] && FLAG_SOURCES=y
  [ "$i" == "lightsout"       ] && FLAG_LIGHTSOUT=y
  
  [ "$i" == "prune"           ] && FLAG_PRUNE=y
done

echo "FLAG_DRYRUN='$FLAG_DRYRUN'"

ARMVERS=(_)
if [ "$FLAG_CA7"  == "y" ]; then ARMVERS+=(ca7);  fi
if [ "$FLAG_CA17" == "y" ]; then ARMVERS+=(ca17); fi
readonly ARMVERS

cd "$BTRFSDIR"

function btrfsclean()
{
  local NAME
  for NAME in "$@"
  do
    if [ -d ./"$NAME" ]
    then
      if ! btrfs subvolume delete ./"$NAME"
      then
        rm -rf --one-file-system ./"$NAME"
        mv ./"$NAME" ./old-"$NAME"-"$(date +%s.%Ns)"
      fi
      [ ! -d ./"$NAME" ]
    fi
  done
}

function stage3unpack()
{
  local NAME="$1"
  local ARCH="$2"
  
  gpg_keysel gentoo_releng_1
  gpg_ --verify       "$BTRFSDIR"/sources/special_stage3-"$ARCH"-"$FAKEDATE".tar.xz.DIGESTS.asc
  local EXPECT
  EXPECT="$(cat       "$BTRFSDIR"/sources/special_stage3-"$ARCH"-"$FAKEDATE".tar.xz.DIGESTS.asc | egrep -o '[0-9a-f]{128}' | head -n 1)"
  local ACTUAL
  ACTUAL="$(sha512sum "$BTRFSDIR"/sources/special_stage3-"$ARCH"-"$FAKEDATE".tar.xz | cut -d ' ' -f 1)"
  [ "$ACTUAL" == "$EXPECT" ] || exit 1
  
  btrfsclean "$NAME"
  if ! btrfs subvolume create "$NAME"
  then
    mkdir "$NAME"
  fi
  tar -C ./"$NAME" -xpf "$BTRFSDIR"/sources/special_stage3-"$ARCH"-"$FAKEDATE".tar.xz
}

if [ "$FLAG_STAGE3" == "y" ]
then
  (
    stage3unpack gentoo amd64
    mkdir -p ./gentoo/builds
  )
fi

function gentoo_chroot_enter()
{
  rm -rf --one-file-system ./sources || true
  cp --reflink=auto -ax "$BTRFSDIR"/sources ./
  mount -t tmpfs none ./tmp
  mount -t proc none ./proc
  mount --rbind /sys ./sys
  mount --make-rslave ./sys
  mount --rbind /dev ./dev
  mount --make-rslave ./dev
  mkdir -p ./run/shm
  mount -t tmpfs none ./run/shm
}

function gentoo_chroot_leave()
{
  kill_mounts_below .
}

function gentoo_chroot_script()
{
  local NAME="$1"
  shift
  gentoo_chroot_enter
  (
    echo -n 'set -o xtrace; source /etc/profile; set -o errexit; set -o nounset; set -o pipefail; cd /tmp; shopt -s failglob; shopt -s nullglob; '
    cat "$HOMEDIR"/"$NAME"
  ) >./tmp/gentoo_chroot_script
  for i in "$@"
  do
    if [ -d "$HOMEDIR"/files/"$i" ]
    then
      mkdir ./tmp/"$i"
    else
      cp "$HOMEDIR"/files/"$i" ./tmp/"$i"
    fi
  done
  chroot . bash /tmp/gentoo_chroot_script 2>&1 | tee ./var/log/gcs."$NAME"."`date +%s.%Ns`"
  gentoo_chroot_leave
}

if [ "$FLAG_PORTAGE" == "y" ] || [ "$FLAG_WORLD" == "y" ]
then
  # the following packages must be special-cased as they are no longer available from the primary distfiles.gentoo.org location
  getsrc_bn https://downloads.sourceforge.net/project/vnc-tight/TightVNC-unix/1.3.10/tightvnc-1.3.10_unixsrc.tar.bz2
  getsrc_bn https://www.tightvnc.com/download/1.3.10/tightvnc-1.3.10_javasrc.tar.gz
fi

if [ "$FLAG_PORTAGE" == "y" ]
then
  (
    cd ./gentoo
    
    export_loadable_variables FAKEDATE >./builds/elvopt
    
    gpg_keysel gentoo_portage_1
    gpg_ --verify "$BTRFSDIR"/sources/special_portage-"$FAKEDATE".tar.xz{.gpgsig,}
    
    gentoo_chroot_script portage.sh patch-portage-pb-b001-emerge-webrsync-1 patch-gentoo-extras
  )
fi

if [ "$FLAG_WORLD" == "y" ]
then
  (
    cd ./gentoo
    
    export_loadable_variables CORES FLAG_{BACKTRACK,NOCLEAN,ONCEOVER} >./builds/elvopt
    echo "world-basic $*" | tr ' ' '\n' | ( egrep '^world-' || true ) | sed -e 's/^/#/' >>./builds/elvopt
    
    gentoo_chroot_script world1.sh
    
    # the following packages must be special-cased as they are no longer available from the primary distfiles.gentoo.org location
    getsrc_bn https://nodejs.org/dist/v8.1.1/node-v8.1.1.tar.xz
    
    cat ./builds/world/emerge.lst | ( egrep '^(http|https|ftp)://' || true ) | sed -e 's@ftp://[^ ]*[ ]*@@g' | sed -e 's/[ ].*//' |\
    (
      while IFS= read -r X_LINE
      do
        getsrc_bn "$X_LINE"
      done
    )
    
    if [ "$FLAG_DRYRUN" == "n" ]
    then
      gentoo_chroot_script world2.sh
    fi
  )
fi

if [ "$FLAG_LINUX" == "y" ]
then
  (
    cd ./gentoo
    
    TARGET=x64
    OPTION_VERSION_LINUX_LIBRE="$OPTION_VERSION_LINUX_LIBRE_X64"
    
    export_loadable_variables CORES OPTION_VERSION_LINUX_LIBRE FLAG_PRISTINE TARGET OPTION_VERSION_ZFS{,_{SPL,ZFS}_SHA} >./builds/elvopt
    
    gpg_keysel linuxlibre_1
    gpg_ --verify "$BTRFSDIR"/sources/special_linux-libre-"$OPTION_VERSION_LINUX_LIBRE"-gnu.tar.xz{.sign,}
    
    gentoo_chroot_script linux.sh common-linux.sh linux-config-"$TARGET".sh
  )
fi

if [ "$FLAG_LINUX_MIN" == "y" ]
then
  (
    cd ./gentoo
    
    OPTION_VERSION_LINUX_LIBRE="$OPTION_VERSION_LINUX_LIBRE_X64"
    
    export_loadable_variables CORES OPTION_VERSION_LINUX_LIBRE >./builds/elvopt
    
    gpg_keysel linuxlibre_1
    gpg_ --verify "$BTRFSDIR"/sources/special_linux-libre-"$OPTION_VERSION_LINUX_LIBRE"-gnu.tar.xz{.sign,}
    
    gentoo_chroot_script linux-min.sh linux-config-x64-min-d16.sh
  )
fi

if [ "$FLAG_SQUASHFS" == "y" ]
then
  (
    cd ./gentoo
    
    export_loadable_variables FLAG_SOURCES >./builds/elvopt
    
    gentoo_chroot_script squashfs.sh
  )
fi

if [ "$FLAG_BRARM" == "y" ]
then
  (
    for ARMVER in "${ARMVERS[@]:1}"
    do
      (
        cd ./gentoo
        
        export_loadable_variables OPTION_VERSION_BUILDROOT{,_SHA} FLAG_{PRISTINE,SOURCES} ARMVER >./builds/elvopt
        echo "brarm-basic $*" | tr ' ' '\n' | ( egrep '^brarm-' || true ) | sed -e 's/^/#/' >>./builds/elvopt
        
        gentoo_chroot_script brarm.sh brarm-packages.sh buildroot-dependencies patch-buildroot-pb-"$OPTION_VERSION_BUILDROOT"-{strict-check-hash-1,strict-check-hashes-1,squashfs-url-fix-1,mmc-utils-url-fix-1,openbox-url-fix-1,argp-url-fix-1,sunxi-tools-revamp-1,xserver-xorg-xcsecurity-1,extra-packages-1} patch-busybox-pb-b002-openvt-fix-1 patch-libmpsse-pb-b001-makefile-fix-1 patch-tint2-pb-b001-no-pollute-env-1 flashpagan.c
      )
    done
  )
fi

function arm_linux_common()
{
  (
    cd ./gentoo
    
    export_loadable_variables CORES OPTION_VERSION_LINUX_LIBRE FLAG_PRISTINE ARMVER TARGET >./builds/elvopt
    
    gpg_keysel linuxlibre_1
    gpg_ --verify "$BTRFSDIR"/sources/special_linux-libre-"$OPTION_VERSION_LINUX_LIBRE"-gnu.tar.xz{.sign,}
    
    gentoo_chroot_script arm-linux.sh common-linux.sh linux-config-"$TARGET".sh common-cross-compile.sh patch-linux-kernel-pb-v4.12.12-extra-kernel-modules-1
  )
}

if [ "$FLAG_ARM_LINUX_BPI" == "y" ]
then
  (
    [ "$FLAG_CA7" == "y" ]
    ARMVER=ca7
    TARGET=bpi
    OPTION_VERSION_LINUX_LIBRE="$OPTION_VERSION_LINUX_LIBRE_BPI"
    
    arm_linux_common
  )
fi

if [ "$FLAG_ARM_LINUX_ROK" == "y" ]
then
  (
    [ "$FLAG_CA17" == "y" ]
    ARMVER=ca17
    TARGET=rok
    OPTION_VERSION_LINUX_LIBRE="$OPTION_VERSION_LINUX_LIBRE_ROK"
    
    arm_linux_common
  )
fi

if [ "$FLAG_COREBOOT" == "y" ]
then
  (
    cd ./gentoo
    
    export_loadable_variables CORES OPTION_VERSION_{COREBOOT{,_{VBOOT,SEABIOS}},ICH9GEN}_COMMIT{,_SHA} >./builds/elvopt
    
    gentoo_chroot_script coreboot.sh patch-coreboot-pb-b002-{no-ada-timeout-1,no-option-table-1,d16-no-mct-save-1,t400-no-ati-gfx-1,arm-penguin-loader-1} patch-seabios-pb-b001-no-option-roms-1
  )
fi

if [ "$FLAG_ARM_U_BOOT" == "y" ]
then
  (
    for ARMVER in "${ARMVERS[@]:1}"
    do
      (
        cd ./gentoo
        
        export_loadable_variables CORES OPTION_VERSION_U_BOOT OPTION_U_BOOT_BOARD_NAME_LIST FLAG_PRISTINE ARMVER >./builds/elvopt
        
        gpg_keysel u_boot_1
        gpg_ --verify "$BTRFSDIR"/sources/special_u-boot-"$OPTION_VERSION_U_BOOT".tar.bz2{.sig,}
        
        gentoo_chroot_script arm-u-boot.sh common-cross-compile.sh
      )
    done
  )
fi

FILESET_LIBABOON="$(echo libaboon/{,{{everything,definitions,syscall,divide,abort,sysdeps,string,printer,start,context,linux,alloc,stack,queue,switch,token_bucket,work_queue,io,aio,bufio,heartbeat,watchdog,misc,sha256,type_magic,bignum}.c,builder.sh}})"

function lb_generic()
{
  local TOOL
  TOOL="$1"
  shift
  
  (
    cd ./gentoo
    
    export_loadable_variables TOOL ARMVERS FLAG_LIGHTSOUT >./builds/elvopt
    
    gentoo_chroot_script lb-generic.sh common-cross-compile.sh "$TOOL".c $FILESET_LIBABOON
  )
}

if [ "$FLAG_NBD_HYPERBOLIC" == "y" ]; then lb_generic nbd-hyperbolic; fi

if [ "$FLAG_INSTIGATOR"     == "y" ]; then lb_generic instigator;     fi
if [ "$FLAG_SAFEPIPE"       == "y" ]; then lb_generic safepipe;       fi
if [ "$FLAG_MURMUR"         == "y" ]; then lb_generic murmur;         fi
if [ "$FLAG_LINUXTOOLS"     == "y" ]; then lb_generic linuxtools;     fi
if [ "$FLAG_FANMAN"         == "y" ]; then lb_generic fanman;         fi
if [ "$FLAG_GPTIZE"         == "y" ]; then lb_generic gptize;         fi

if [ "$FLAG_UNPRANKER" == "y" ]
then
  (
    cd ./gentoo
    
    export_loadable_variables ARMVERS FLAG_LIGHTSOUT OPTION_VERSION_XZ_EMBEDDED{,_SHA} >./builds/elvopt
    
    gentoo_chroot_script lb-unpranker.sh common-cross-compile.sh unpranker.c $FILESET_LIBABOON
  )
fi

if [ "$FLAG_FLASHPAGAN" == "y" ]
then
  (
    cd ./gentoo
    
    export_loadable_variables OPTION_VERSION_LIBMPSSE_COMMIT{,_SHA} >./builds/elvopt
    
    gentoo_chroot_script flashpagan.sh flashpagan.c patch-libmpsse-pb-b001-makefile-fix-1
  )
fi

if [ "$FLAG_UNIKITMAYBE" == "y" ] && [ "$UNIKITMAYBEYESFILE" == "y" ]
then
  FLAG_UNIKIT=y
fi

if [ "$FLAG_UNIKIT" == "y" ]
then
  (
    cd ./gentoo
    
    export_loadable_variables ALLARMVERS >./builds/elvopt
    
    gentoo_chroot_script unikit.sh bincop.sh
  )
fi

if [ "$FLAG_WORLD" == "y" ] && [ "$FLAG_PRUNE" == "y" ]
then
  function prune_unused_files()
  {
    (
      cd "$1"
      find . -maxdepth 1 -type f -printf "%f\n" >"$BUILDDIR"/catalog.lst
      sort "$BUILDDIR"/touch.lst "$BUILDDIR"/touch.lst "$BUILDDIR"/catalog.lst | uniq -u | xargs rm -vf
    )
  }
  
  prune_unused_files "$OFFLOADDIR"/sources
  prune_unused_files "$BTRFSDIR"/sources
fi

echo "+OK (success)"
