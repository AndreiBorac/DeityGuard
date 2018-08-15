#!/usr/bin/env bash

set -o xtrace
set -o errexit
set -o nounset
set -o pipefail
shopt -s failglob
shopt -s nullglob

CLEANPATH="/usr/sbin:/usr/bin:/sbin:/bin:/bin_busybox"

ROOTCLEAN="n"

if [ "$1" == "rootclean" ]
then
  ROOTCLEAN="y"
  shift
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

# when invoked with -c, clean up from a previous run (also used internally)
if [ "${1-}" == "-c" ]
then
  for i in ./build
  do
    if sudo mountpoint -q "$i"
    then
      MP="$(readlink -f "$i")"
      sudo fuser -k -9 -M -m "$MP" || true
    fi
  done
  
  kill_mounts_below ./build
  
  exit
fi

function export_loadable_variables()
{
  for i in "$@"
  do
    echo "exporting $i" >&2
    echo "$i='${!i}'"
    echo "exporting $i='${!i}'" >&2
  done
}

function slurp_config()
{
  (
    { [ -f ./shared_config/"$1".sh ] && cat ./shared_config/"$1".sh ;} || cat ./config/"$1".sh
  ) |\
  (
    while IFS= read LINE
    do
      echo "$LINE"
      
      if [ "${LINE:0:9}" == "#include " ]
      then
        slurp_config "${LINE:9}" </dev/null
      fi
    done
  )
}

if [ "$ROOTCLEAN" != "y" ]
then
  # first clean up from any previous run
  bash "$0" -c
  
  # create build directory
  [ -d ./build ] || sudo mkdir -m 0000 ./build
  sudo mountpoint -q ./build || sudo mount -t tmpfs none ./build
  mkdir -p ./build/tmp
  
  # copy script into build directory
  cat ./"$0" >./build/tmp/script
  
  # create a file with loadable variables
  HOMEDIR="$(readlink -f .)"
  BUILDDIR="$(readlink -f "$HOMEDIR"/build)"
  INCHROOT=n
  FINGEN_HOSTARCH="$(cat ./local/hostarch)"
  export_loadable_variables HOMEDIR INCHROOT FINGEN_HOSTARCH >./build/tmp/loadables
  
  # add config variables to loadables
  slurp_config "$2" >>./build/tmp/loadables
  
  # extra options have the last word
  echo "$FINGEN_EXTRA_OPTIONS" >>./build/tmp/loadables
  
  # set umask so we do not depend on a correct setting in the host environment
  umask 0002
  
  # exec as root in a clean environment
  LOADABLES="$(readlink -f ./build/tmp/loadables)"
  exec sudo env -i PATH="$CLEANPATH" bash "$BUILDDIR"/tmp/script rootclean "$LOADABLES" "$@"
fi

LOADABLES="$1"
shift
. "$LOADABLES"

function cp_()
{
  cp --reflink=auto -vax "$@"
}

function cp_from()
{
  (
    cd "$1"
    shift
    cp --reflink=auto -vax "$@"
  )
}

if [ "$INCHROOT" == "n" ]
then
  cd "$HOMEDIR"/build
  mkdir -p ./chroot
  mv ./tmp ./chroot/
  cd ./chroot
  
  mkdir -p ./files
  cp_ "$HOMEDIR"/files/. ./files
  mkdir -p ./overlay ./config_overlay
  cp_ "$HOMEDIR"/overlay/. ./overlay/
  [ ! -d "$HOMEDIR"/config/overlay ] || cp_ "$HOMEDIR"/config/overlay/. ./config_overlay/
  
  mkdir -p ./persist
  mkdir -p "$HOMEDIR"/local/persist
  mount --bind "$HOMEDIR"/local/persist ./persist
  
  mkdir -p ./output
  RL_OUTPUT="$(readlink -f "$HOMEDIR"/local/output)"
  mount --bind "$RL_OUTPUT" ./output
  
  mkdir -p ./rootfs-mirror
  mount -o bind,ro "$HOMEDIR"/local/gengen-build-btrfs-gentoo-builds-rootfs-mirror/ ./rootfs-mirror
  
  tar --lzop -xf "$HOMEDIR"/local/gengen-build-btrfs-gentoo-builds-unikit.tzo
  
  mkdir -p ./dev
  mknod    ./dev/null    c 1 3
  mknod    ./dev/zero    c 1 5
  mknod    ./dev/urandom c 1 8
  mknod    ./dev/random  c 1 9
  ln -vsf -T ./../tmp ./dev/shm
  
  mkdir -p ./proc
  mount --bind /proc ./proc
  
  INCHROOT=y
  export_loadable_variables INCHROOT >>./tmp/loadables
  
  function hostarchprobe_x64()
  {
    [ -d ./x64 ]
  }
  function hostarchprobe_ca7()
  {
    [ -d ./builds/brarm-output-ca7 ]
  }
  function hostarchprobe_ca17()
  {
    [ -d ./builds/brarm-output-ca17 ]
  }
  function hostarchsetup_x64()
  {
    ln -vsfT ./x64/bin/ ./bin
    ln -vsfT ./x64/lib64/ ./lib64
    ln -vsfT ./x64/usr/ ./usr
    ln -vsfT ./bash ./bin/sh
    BUSYBOX_LOCATION=bin/busybox
  }
  function hostarchsetup_arm()
  {
    local ARMVER
    ARMVER="$1"
    
    ln -vsfT ./builds/brarm-output-"$ARMVER"/target/usr/ ./usr
    ln -vsfT ./builds/brarm-output-"$ARMVER"/target/usr/lib/ ./lib
    ln -vsfT ./bash ./usr/bin/sh
    BUSYBOX_LOCATION=usr/bin/busybox
  }
  function hostarchsetup_ca7()
  {
    hostarchsetup_arm "ca7"
  }
  function hostarchsetup_ca17()
  {
    hostarchsetup_arm "ca17"
  }
  read -a HOSTARCHTRY <"$HOMEDIR"/local/hostarch
  HOSTARCHFOUND=n
  for HOSTARCH in "${HOSTARCHTRY[@]}"
  do
    if hostarchprobe_"$HOSTARCH"
    then
      HOSTARCHFOUND=y
      break
    fi
  done
  [ "$HOSTARCHFOUND" == "y" ]
  hostarchsetup_"$HOSTARCH"
  export_loadable_variables HOSTARCH BUSYBOX_LOCATION >>./tmp/loadables
  env -i PATH="$CLEANPATH" chroot . bash /tmp/script rootclean /tmp/loadables "$@" 2>&1 | tee ./../stdamp
  
  umount ./proc
  
  umount ./rootfs-mirror
  umount ./output
  umount ./persist
  
  cd ./..
  
  touch ./chroot/product
  
  CHROOT_PRODUCT="$(cat ./chroot/product)"
  for i in $CHROOT_PRODUCT
  do
    BN_I="$(basename "$i")"
    ln -vf -T ./chroot/"$i" ./"$BN_I"
  done
  
  echo "+OK (success)"
  exit
fi

[ "$INCHROOT" == "y" ]
#busybox mkdir -p ./sbin ./bin
# busybox --install -s isn't smart enough to make relative symlinks, so there:
#busybox --list-all | busybox sed -e 's/.*/busybox ln -s _\0 \0/' -e 's@_[^ /]*/@../_@' -e 's@_[^ /]*/@../_@' -e 's@_[^ ]* @'"$BUSYBOX_LOCATION"' @' | busybox sh
busybox mkdir ./bin_busybox
busybox --list | busybox sed -e 's@^@busybox ln -s ./../'"$BUSYBOX_LOCATION"' ./bin_busybox/@' | busybox sh

function srcsel_x64()
{
  SRCSEL_X64=/x64
  SRCSEL_LINUX_MODULES=/builds/linux-libre-final-x64-x64
  SRCSEL_ROOTFS=/builds/gentoo
  SRCSEL_ROOTFS_NAME=gentoo
}

function srcsel_arm_1()
{
  local ARMVER
  for ARMVER in "${COMPATIBLE_ARMVERS[@]}"
  do
    if [ -d        /builds/brarm-output-"$ARMVER" ]
    then
      SRCSEL_BRARM=/builds/brarm-output-"$ARMVER"
      return
    fi
  done
  
  set +o xtrace
  echo "!! couldn't find a compatible build of brarm"
  echo "!! bye"
  exit 1
}

function srcsel_arm_2()
{
  local ARMVER
  for ARMVER in "${COMPATIBLE_ARMVERS[@]}"
  do
    local LINFLV
    for LINFLV in "${COMPATIBLE_LINFLVS[@]}"
    do
      if [ -d /builds/linux-libre-final-"$ARMVER"-"$LINFLV" ]
      then
        SRCSEL_LINUX_MODULES=/builds/linux-libre-final-"$ARMVER"-"$LINFLV"
        return
      fi
    done
  done
  
  set +o xtrace
  echo "!! couldn't find a compatible build of linux"
  echo "!! bye"
  exit 1
}

function srcsel_arm_3()
{
  local ARMVER
  for ARMVER in "${COMPATIBLE_ARMVERS[@]}"
  do
    if [ -f         /builds/brarm-output-"$ARMVER"/images/system.inf ]
    then
      SRCSEL_ROOTFS=/builds/brarm-output-"$ARMVER"/images/system
      SRCSEL_ROOTFS_NAME=brarm-"$ARMVER"
      return
    fi
  done
  
  set +o xtrace
  echo "!! couldn't find a compatible system image"
  echo "!! bye"
  exit 1
}

function srcsel_arm()
{
  srcsel_arm_1
  srcsel_arm_2
  srcsel_arm_3
}

function srcsel()
{
  srcsel_"$ARCH"
  SRCSEL_LINUX_KVER="$(ls -1 "$SRCSEL_LINUX_MODULES"/lib/modules | head -n 1)"
  
  if [ -f "$SRCSEL_LINUX_MODULES"/lib/modules/"$SRCSEL_LINUX_KVER"/kernel/drivers/video/console/fbcon.ko ]
  then
    SRCSEL_LINUX_HAVE_FBCON=y
    SRCSEL_LINUX_MAYBE_FBCON="fbcon"
  else
    SRCSEL_LINUX_HAVE_FBCON=n
    SRCSEL_LINUX_MAYBE_FBCON=""
  fi
}

function srcsel_tool_x64()
{
  local TOOL
  TOOL="$1"
  
  SRCSEL_TOOL=/builds/"$TOOL"-x64
}

function srcsel_tool_arm()
{
  local TOOL
  TOOL="$1"
  
  local ARMVER
  for ARMVER in "${COMPATIBLE_ARMVERS[@]}"
  do
    if [ -d /builds/"$TOOL"-"$ARMVER" ]
    then
      SRCSEL_TOOL=/builds/"$TOOL"-"$ARMVER"
      return
    fi
  done
  
  set +o xtrace
  echo "!! couldn't find a compatible build of '$TOOL'"
  echo "!! while targeting arm architecture(s) '${COMPATIBLE_ARMVERS[*]}'"
  echo "!! bye"
  exit 1
}

function srcsel_tool()
{
  srcsel_tool_"$ARCH" "$1"
}

function srcsel_tool_host()
{
  local TOOL
  TOOL="$1"
  
  local i
  for i in $FINGEN_HOSTARCH
  do
    if [ -d /builds/"$TOOL"-"$i" ]
    then
      SRCSEL_TOOL=/builds/"$TOOL"-"$i"
      return
    fi
  done
  
  set +o xtrace
  echo "!! couldn't find a compatible build of '$TOOL'"
  echo "!! while targeting host architecture(s) '$FINGEN_HOSTARCH'"
  echo "!! bye"
  exit 1
}

function initramfs_init_x64()
{
  rm -f /tmp/initramfs_add_binaries_file_list
  cat "$SRCSEL_X64"/files_zero_point >>/tmp/initramfs_add_binaries_file_list
  
  # here we mirror how gentoo sets things up
  
  local i
  for i in ./initramfs/{lib,usr/{lib,local/lib}}
  do
    mkdir -vp "$i"64
    ln -vsf -T ./lib64 "$i"
  done
  
  # add_binaries won't necessarily create /sbin so create it here for
  # the benefit of busybox --install
  
  mkdir -p ./initramfs/sbin
}

function initramfs_init_arm()
{
  rm -f /tmp/initramfs_add_binaries_file_list
  cat "$SRCSEL_BRARM"/target/files_zero_point >>/tmp/initramfs_add_binaries_file_list
  
  # here we mirror how buildroot sets things up
  
  # bin
  mkdir -p ./initramfs/usr/bin
  ln -vsfT ./usr/bin/ ./initramfs/bin
  # sbin
  mkdir -p ./initramfs/usr/sbin
  ln -vsfT ./usr/sbin/ ./initramfs/sbin
  # lib
  mkdir -p ./initramfs/usr/lib
  ln -vsfT ./usr/lib/ ./initramfs/lib
  ln -vsfT ./lib/ ./initramfs/lib32
  ln -vsfT ./lib/ ./initramfs/usr/lib32
}

function initramfs_init()
{
  mkdir -p ./initramfs
  mount -t tmpfs none ./initramfs
  
  initramfs_init_"$ARCH"
  
  INITRAMFS_ADD_MODULES_LIST=""
}

function initramfs_fini()
{
  cp -ax ./initramfs ./"$1"
  umount ./initramfs
}

function initramfs_add_binaries_common()
{
  local SRCSEL
  SRCSEL="$1"
  shift
  
  local i
  for i in "$@"
  do
    local BN_I
    BN_I="$(basename "$i")"
    
    cat "$SRCSEL"/files_"$BN_I" >>/tmp/initramfs_add_binaries_file_list
  done
}

function initramfs_add_binaries_x64()
{
  initramfs_add_binaries_common "$SRCSEL_X64" "$@"
}

function initramfs_add_binaries_arm()
{
  initramfs_add_binaries_common "$SRCSEL_BRARM"/target "$@"
}

function initramfs_add_binaries_finally_common()
{
  local SRCSEL
  SRCSEL="$1"
  
  if [ -f /tmp/initramfs_add_binaries_file_list ]
  then
    cat </tmp/initramfs_add_binaries_file_list | sort | uniq >/tmp/initramfs_add_binaries_file_list_fixed
    
    cp_from "$SRCSEL" --verbose --parents $(cat /tmp/initramfs_add_binaries_file_list_fixed) "$(readlink -f ./initramfs)"
  fi
}

function initramfs_add_binaries_finally_x64()
{
  initramfs_add_binaries_finally_common "$SRCSEL_X64"
}

function initramfs_add_binaries_finally_arm()
{
  initramfs_add_binaries_finally_common "$SRCSEL_BRARM"/target
}

function initramfs_add_binaries()
{
  initramfs_add_binaries_"$ARCH" "$@"
}

function initramfs_add_binaries_finally()
{
  initramfs_add_binaries_finally_"$ARCH"
}

function initramfs_add_binaries_if_x64()
{
  if [ "$ARCH" == "x64" ]
  then
    initramfs_add_binaries_"$ARCH" "$@"
  fi
}

function initramfs_add_binaries_if_arm()
{
  if [ "$ARCH" == "arm" ]
  then
    initramfs_add_binaries_"$ARCH" "$@"
  fi
}

function initramfs_add_binaries_dd()
{
  # add dd; funky because coreutils is configured kind of like a multi-call binary in buildroot
  function f_x64() { initramfs_add_binaries dd ;}
  function f_arm() { initramfs_add_binaries dd coreutils ;}
  f_"$ARCH"
  unset f_x64 f_arm
}

function initramfs_add_binaries_dialog()
{
  # add dialog; funky because ancillary data is in different locations in gentoo vs buildroot
  initramfs_add_binaries dialog
  function f_x64() { echo etc/terminfo       >>/tmp/initramfs_add_binaries_file_list ;}
  function f_arm() { echo usr/share/terminfo >>/tmp/initramfs_add_binaries_file_list ;}
  f_"$ARCH"
  unset f_x64 f_arm
}

function first_to_last()
{
  local FIRST REMAINING
  while read -r FIRST REMAINING
  do
    if [ -n "$FIRST" ]
    then
      if [ -n "$REMAINING" ]
      then
        echo "${REMAINING} ${FIRST}"
      else
        echo "${FIRST}"
      fi
    fi
  done
}

function reverse_words()
{
  local LINE
  while read LINE
  do
    echo -n "$LINE"" " | tac -s " " | sed -e 's/ $/\n/'
  done
}

function reverse_array()
{
  local OUT
  OUT=()
  local i
  for ((i=$#;i>0;i--))
  do
    OUT+=("${!i}")
  done
  echo "${OUT[@]}"
}

function reverse_words()
{
  local TOKENS
  while read -a TOKENS
  do
    if [ "${TOKENS+isset}" == "isset" ]
    then
      reverse_array "${TOKENS[@]}"
    fi
  done
}

function initramfs_add_modules()
{
  local FROM DEST KDIR KVER KDIR
  FROM="$SRCSEL_LINUX_MODULES"/
  DEST="$(readlink -f ./initramfs)"
  KVER="$SRCSEL_LINUX_KVER"
  KDIR="$FROM"lib/modules/"$KVER"
  
  INITRAMFS_ADD_MODULES_KVER="$KVER"
  
  if [ ! -f ./initramfs/lib/modules/"$KVER"/modules.alias ]
  then
    cp_from "$FROM" --verbose --parents ./lib/modules/"$KVER"/modules.alias "$DEST"
  fi
  
  local WANT
  WANT="$*"
  WANT="${WANT// /|}"
  
  local FOUND
  FOUND="$(egrep '/('"$WANT"')\.ko\:' "$KDIR"/modules.dep)"
  
  if [ "$(echo "$FOUND" | wc -l)" != "$#" ]
  then
    set +o xtrace
    echo "!! found too few or too many modules"
    echo "!! going one by one for debugging purposes"
    for i in "$@"
    do
      if ! egrep -q '/'"$i"'\.ko\:' "$KDIR"/modules.dep
      then
        echo "!! missing module '$i'"
        echo "!! hint:"
        egrep "$(echo "$i" | tr '\-_' '..')"'\.ko\:' "$KDIR"/modules.dep || true
      fi
    done
    echo "!! found too few or too many modules"
    echo "!! bye"
    exit 1
  fi
  
  local MODS
  #MODS="$(egrep '/('"$WANT"')\.ko\:' "$KDIR"/modules.dep)"
  #MODS="$(echo "$MODS" | sed -e 's/://')"
  #MODS="$(echo "$MODS" | reverse_words)"
  #MODS="$(echo "$MODS" | tr ' ' '\n')"
  #echo FINALLY
  #echo "$MODS"
  MODS="$(egrep '/('"$WANT"')\.ko\:' "$KDIR"/modules.dep | sed -e 's/://' | reverse_words | tr ' ' '\n')"
  egrep '/('"$WANT"')\.ko\:' "$KDIR"/modules.dep >>"$DEST"/lib/modules/"$KVER"/modules.dep.tmp
  
  cp_from "$FROM"/lib/modules/"$KVER" --verbose --parents $MODS "$DEST"/lib/modules/"$KVER"
  
  INITRAMFS_ADD_MODULES_LIST="$INITRAMFS_ADD_MODULES_LIST $(echo $MODS)"
}

function initramfs_add_modules_finally()
{
  local FROM DEST KDIR KVER KDIR
  FROM="$SRCSEL_LINUX_MODULES"/
  DEST="$(readlink -f ./initramfs)"
  KVER="$SRCSEL_LINUX_KVER"
  KDIR="$FROM"lib/modules/"$KVER"
  
  sort <"$DEST"/lib/modules/"$KVER"/modules.dep.tmp | uniq >"$DEST"/lib/modules/"$KVER"/modules.dep
  rm -f "$DEST"/lib/modules/"$KVER"/modules.dep.tmp
}

function initramfs_no_modules_alias()
{
  local FROM DEST KDIR KVER KDIR
  FROM="$SRCSEL_LINUX_MODULES"/
  DEST="$(readlink -f ./initramfs)"
  KDIR="$FROM"lib/modules
  KVER="$(ls -1 "$KDIR" | head -n 1)"
  KDIR="$KDIR"/"$KVER"
  
  rm -f "$DEST"/lib/modules/"$SRCSEL_LINUX_KVER"/modules.alias
}

function initramfs_drop()
{
  local APPEND=n
  local EXECUTABLE=n
  
  case "$1" in
    -a)
      APPEND=y
      shift
      ;;
    
    -x)
      EXECUTABLE=y
      shift
      ;;
    
    -ax)
      APPEND=y
      EXECUTABLE=y
      shift
      ;;
  esac
  
  local FILENAME
  FILENAME="$1"
  
  local DN_A
  DN_A="$(dirname "$1")"
  mkdir -p ./initramfs/"$DN_A"
  
  if [ "$APPEND" == "y" ]
  then
    cat  >>./initramfs/"$FILENAME"
  else
    [ ! -f ./initramfs/"$FILENAME" ]
    cat   >./initramfs/"$FILENAME"
  fi
  
  if [ "$EXECUTABLE" == "y" ]
  then
    chmod a+x ./initramfs/"$FILENAME"
  fi
}

function initramfs_pack()
{
  function initramfs_pack_compress { xz --check=crc32 --compress -6 ; }
  function initramfs_pack_consumer() { cat >./initrd.img ; }
  
  while [ "$#" -gt 0 ]
  do
    case "$1" in
      -0)
        function initramfs_pack_compress() { cat ; }
        ;;
      
      -e)
        function initramfs_pack_compress() { xz --check=crc32 --compress -6e ; }
        ;;
      
      -a)
        function initramfs_pack_consumer() { cat >>./initrd.img ; }
        ;;
      
      *)
        exit 1
        ;;
    esac
    
    shift
  done
  
  #find ./initramfs -xdev ! -type d -printf "%p %y %s %M\n"
  
  #( cd ./initramfs ; find . -printf "%p %y %s %M\n" ) # no longer works since using busybox find
  
  ( cd ./initramfs ; find . | cpio --format=newc --reproducible --create ) | initramfs_pack_compress | initramfs_pack_consumer
}

function initramfs_pack_init_only()
{
  touch -t 199901010000 ./init
  echo ./init | cpio --format=newc --reproducible --create >./initrd.img
}

function initramfs_banter_shell()
{
  if [ "$2" != "" ]
  then
    echo "$2" | initramfs_drop -x "$1"
  else
    echo "#!/bin/false" | initramfs_drop "$1"
  fi
  
  initramfs_drop -a "$1" <<'EOF'
set -o xtrace
set -o errexit
set -o nounset
set -o pipefail
shopt -s failglob || true
shopt -s nullglob || true
EOF
}

function initramfs_banter()
{
  initramfs_banter_shell "$1" "$2"
  
  initramfs_drop -a "$1" <<'EOF'
#busybox depmod

mountpoint_()
{
  # this doesn't correctly detect the case that /proc isn't mounted
  # but there is a /proc/mounts file on the / filesystem that contains
  # an entry for /proc ... not worth fixing

  egrep -q '^none '"$1"' ' /proc/mounts
}

mkdir -p /proc
if ! mountpoint_ /proc
then
  mount -t proc none /proc
fi

mkdir -p /etc
ln -vsf -T /proc/mounts /etc/mtab

mkdir -p /sys
if ! mountpoint_ /sys
then
  mount -t sysfs none /sys
fi

mkdir -p /dev
if ! mountpoint_ /dev
then
  mount -t devtmpfs none /dev
fi

mkdir -p /dev/shm
if ! mountpoint_ /dev/shm
then
  mount -t tmpfs -o rw,nosuid,nodev none /dev/shm
fi

mkdir -p /dev/pts
if ! mountpoint_ /dev/pts
then
  mount -t devpts -o mode=0620,gid=5,nosuid,noexec none /dev/pts
fi

mkdir -p /tmp
if ! mountpoint_ /tmp
then
  mount -t tmpfs none /tmp
fi

mkdir -p  /sbin
rm -f     /sbin/modprobe
touch     /sbin/modprobe
chmod a+x /sbin/modprobe
cat >/sbin/modprobe <<'DBLEOF'
#!/bin/busybox sh
echo "(kernel) modprobe '$*' (attempt)" >>/tmp/modprobe.early
busybox modprobe "$@"
RETV="$?"
echo "(kernel) modprobe '$*' => $RETV"  >>/tmp/modprobe.early
exit "$RETV"
DBLEOF
EOF
}

function u_boot_initramfs()
{
  mkimage -A arm -O linux -T ramdisk -C none -n "Linux initramfs" -d ./initrd.img ./uInitrd
}

function u_boot_script()
{
  while read LINE
  do
    echo "echo EXECUTE: ${LINE//[^0-9A-Za-z]/_}"
    echo "$LINE"
  done >./"$1".cmd
  
  mkimage -A arm -T script -C none -n 'script' -d ./"$1".cmd ./"$1".scr
}

STAGEF_MODULES_PLATFORM_INDEPENDENT=(_)
STAGEF_MODULES_PLATFORM_INDEPENDENT+=(af_packet)

STAGE0_MODULES_PLATFORM_INDEPENDENT=(_)
STAGE0_MODULES_PLATFORM_INDEPENDENT+=(usb-storage uas {sd,sr}_mod af_packet)
STAGE0_MODULES_PLATFORM_INDEPENDENT_USB_NET=(_)
STAGE0_MODULES_PLATFORM_INDEPENDENT_USB_NET+=(asix ax88179_178a cdc_eem cdc_ether cdc_mbim cdc_ncm cdc_subset ch9200 dm9601 gl620a huawei_cdc_ncm lan78xx mcs7830 net1080 plusb r8152 rndis_host rtl8150 smsc75xx smsc95xx sr9700 sr9800 usbnet zaurus)

STAGE1_MODULES_PLATFORM_INDEPENDENT=(_)
#STAGE1_MODULES_PLATFORM_INDEPENDENT+=(fbcon) # must handle fbcon specially now that for >=4.14 fbcon cannot be a module
STAGE1_MODULES_PLATFORM_INDEPENDENT+=(hid-generic usbhid) # keyboard

STAGE3_MODULES_PLATFORM_INDEPENDENT=(_)
STAGE3_MODULES_PLATFORM_INDEPENDENT+=("${STAGE0_MODULES_PLATFORM_INDEPENDENT[@]:1}")
STAGE3_MODULES_PLATFORM_INDEPENDENT+=("${STAGE1_MODULES_PLATFORM_INDEPENDENT[@]:1}")
STAGE3_MODULES_PLATFORM_INDEPENDENT+=(loop squashfs overlay)
STAGE3_MODULES_PLATFORM_INDEPENDENT_USB_NET=(_)
STAGE3_MODULES_PLATFORM_INDEPENDENT_USB_NET+=("${STAGE0_MODULES_PLATFORM_INDEPENDENT_USB_NET[@]:1}")

# here we have some system bringup stuff that is common to stage1 and
# stage3. this we call stageZ ...
function stageZ_common()
{
  initramfs_banter_shell stageZb ""
  initramfs_drop -a stageZb <<'EOF'
# banter shell ...

fail()
{
  rm -f /bootcont || true
  
  while [ 1 ]
  do
    while [ ! -f /bootcont ]
    do
      busybox sh -i
    done
    
    [ -f /bootcont ] && . /bootcont
    rm -f /bootcont || true
  done
}

busybox sh /stageZc || fail
[ -f /bootcont ] && . /bootcont
rm -f /bootcont || true

busybox sh /stageZd || fail
[ -f /bootcont ] && . /bootcont
rm -f /bootcont || true

busybox sh /stageZe || fail
[ -f /bootcont ] && . /bootcont
rm -f /bootcont || true

busybox sh /stageZf || fail
[ -f /bootcont ] && . /bootcont
rm -f /bootcont || true

busybox sh /stageZg || fail
[ -f /bootcont ] && . /bootcont
rm -f /bootcont || true

busybox sh /stageZh || fail
[ -f /bootcont ] && . /bootcont
rm -f /bootcont || true

busybox sh /stageZi || fail
[ -f /bootcont ] && . /bootcont
rm -f /bootcont || true

busybox sh /stageZj || fail
[ -f /bootcont ] && . /bootcont
rm -f /bootcont || true

fail
EOF
  
  local STAGEZ_DATE_UID
  if [ "${STAGEZ_INCLUDE_CURRENT_DATE-y}" == "y" ]
  then
    STAGEZ_DATE_UIS="$(date -u -Iseconds)"
  else
    STAGEZ_DATE_UIS="1999-01-01T00:00:00UTC"
  fi
  
  function stageZc_main()
  {
    if [ -f /modules.sqs ]
    then
      for i in loop squashfs
      do
        modprobe "$i" || [ -f /allow_modprobe_fail ] || [ -f /allow_modprobe_fail_"$i" ]
      done
      
      mkdir -p                               /lib/modules/"$(uname -r)"
      mount -t squashfs -o loop /modules.sqs /lib/modules/"$(uname -r)"
    fi
    
    # load "always" modules that do not require hardware detection
    for i in $STAGEZ_MODULES_ALWAYS
    do
      modprobe "$i" || [ -f /allow_modprobe_fail ] || [ -f /allow_modprobe_fail_"$i" ]
    done
    
    # this is the earliest sensible place to give a shell for
    # debugging - when initial console works
    
    #bash -i
    
    # setting the date is not trivial because busybox date -s does not
    # accept the same format as is output by busybox date -I. also, we
    # have to let the date in stageZ be overridden by stageF_date_uis
    # when booting via stageF
    
    DATE_UIS_0="$STAGEZ_DATE_UIS"
    if [ -f ./stageF_date_uis ]
    then
      DATE_UIS_0="$(cat ./stageF_date_uis)"
    fi
    
    # fix date format
    
    DATE_UIS_1="${DATE_UIS_0/UTC/}"
    DATE_UIS_2="${DATE_UIS_1/T/ }"
    date -u -s "$DATE_UIS_2"
    
    # perform hardware detection
    if [ "$ARCH" == "x64" ]
    then
      lspci -nn >./pcimap
      cat ./pcimap
      
      pcihas()
      {
        cat ./pcimap | grep -E -q "$1"'$'
      }
      
      pcimod()
      {
        if pcihas "$1"
        then
          shift
          touch /tmp/pcihad
          modprobe "$@" || [ -f /allow_modprobe_fail ] || [ -f /allow_modprobe_fail_"$1" ]
        fi
      }
      
      pcivga()
      {
        # here we use the /tmp/pcihad as a flag to tell us if we found
        # a card already. we don't want to load more than one card
        # because then we would need fbset and a lot of extra code to
        # figure out where to display things.
        
        rm -f /tmp/pcihad
        
        # discrete nvidia card
        [ -f /tmp/pcihad ] || pcimod "10de:0a65" nouveau
        
        # qemu "integrated"
        [ -f /tmp/pcihad ] || pcimod "1234:1111" bochs-drm
        
        # t400 integrated
        [ -f /tmp/pcihad ] || pcimod "8086:2a42" i915
        
        # d16 integrated
        [ -f /tmp/pcihad ] || pcimod "1a03:2000" ast
        
        # also, fbcon for framebuffer consoles
        modprobe fbcon || true # allow fail because for >=4.14 fbcon cannot be a module
      }
      
      # also, pcieth ... for stage3
      pcieth()
      {
        # qemu
        pcimod "8086:100e" e1000
        
        # t400
        pcimod "8086:10f5" e1000e
        
        # d16
        pcimod "8086:10d3" e1000e
        
        if [ "$ETH_HWADDR" != "" ] && [ ! -f /tmp/did-hw-ether ]
        then
          touch /tmp/did-hw-ether
          # if we set the hardware address, we must also dump any IP got through DHCP
          ifconfig eth0 hw ether "$ETH_HWADDR"
          ifconfig eth0 0.0.0.0 || true
          ifconfig eth0 down || true
        fi
      }
      
      # also, hard disc/disk controllers ... for stage3
      pcihdx()
      {
        pcimod "8086:7010" ata_piix
        pcimod "1af4:1001" virtio_pci
        pcimod "1af4:1001" virtio_blk
      }
      
      pcivga
      pcieth
      pcihdx
    fi
    
    # set output to vga
    chvt 1
    cat >/bootcont <<'DBLEOF'
exec 0</dev/tty1
exec 1>/dev/tty1
exec 2>/dev/tty1
DBLEOF
  }
  
  export_loadable_variables \
      ARCH \
      STAGEZ_MODULES_ALWAYS \
      STAGEZ_DATE_UIS \
      ETH_HWADDR \
    | initramfs_drop -a stageZcv
  declare -f stageZc_main | initramfs_drop -a stageZcv
  
  initramfs_banter stageZc ""
  initramfs_drop -a stageZc <<'EOF'
# banter ...

. ./stageZcv

stageZc_main
EOF
  
  function stageZd_t400()
  {
    modprobe acpi-cpufreq || [ -f /allow_modprobe_fail ] || [ -f /allow_modprobe_fail_acpi-cpufreq ]
    
    local i
    for i in 0 1
    do
      echo 1 | ( tee /sys/devices/system/cpu/cpu"$i"/cpuidle/state3/disable || true )
    done
  }
  
  function stageZd_main()
  {
    if [ "$MODEL" == "t400" ]
    then
      stageZd_"$MODEL"
    fi
  }
  
  export_loadable_variables \
      MODEL \
    | initramfs_drop -a stageZdv
  declare -f stageZd_main | initramfs_drop -a stageZdv
  if [ "$MODEL" == "t400" ]
  then
    declare -f stageZd_"$MODEL" | initramfs_drop -a stageZdv
  fi
  
  initramfs_banter_shell stageZd ""
  initramfs_drop -a stageZd <<'EOF'
# banter shell ...

. ./stageZdv

stageZd_main
EOF
}

function initramfs_add_stageZ_entry_via_busybox()
{
  local ENT
  ENT="$1"
  
  local INI
  INI="$2"
  
  # add script
  initramfs_banter_shell "$ENT" "#!/bin/busybox sh"
  initramfs_drop -a "$ENT" <<'EOF'
# banter shell ...

/bin/busybox --install -s

export PATH=/usr/sbin:/usr/bin:/sbin:/bin

exec busybox sh /stageZb "$@"
EOF
  
  if [ "$INI" == "y" ]
  then
    ln -vsfT "$ENT" ./initramfs/init
  fi
}

# we don't use this but we export it with declare
function dd_()
{
  local WHICH_DD
  WHICH_DD="$(which dd)"
  "$WHICH_DD" "$@" oflag=seek_bytes iflag=fullblock,skip_bytes,count_bytes bs=16M conv=notrunc,fdatasync status=progress
}

# we don't use this but we export it with declare
function dd_no_sync()
{
  local WHICH_DD
  WHICH_DD="$(which dd)"
  "$WHICH_DD" "$@" oflag=seek_bytes iflag=fullblock,skip_bytes,count_bytes bs=16M conv=notrunc status=progress
}

# we don't use this but we export it with declare
function emmc_probe_status()
{
  EMMC_PROBE_GOOD=n
  
  while [ ! -b /dev/mmcblk0 ]
  do
    sleep 0.25
  done
  
  (
    blockdev --getsize64 /dev/mmcblk0
    blockdev --getro     /dev/mmcblk0
    dd_no_sync if=/dev/mmcblk0 of=/dev/null count=$(( (16*(1024**2)) ))
    touch ./emmc_probe_good
  ) </dev/null &
  
  (
    set +o xtrace
    
    for i in $(seq 1 30)
    do
      if [ -f ./emmc_probe_good ]
      then
        break
      fi
      
      sleep 0.1
    done
  )
  
  if [ -f ./emmc_probe_good ]
  then
    wait # for probe shell backgrounded above
    EMMC_PROBE_GOOD=y
  fi
}

# we don't use this but we export it with declare
function eth_bring_up_if_down()
{
  local IFACE
  IFACE="$1"
  
  ifconfig "$IFACE" || return 0 # try to work even without ethernet
  
  if false # true = always drop the interface for testing, false = leave it alone
  then
    ifconfig "$IFACE" 0.0.0.0
    ifconfig "$IFACE" down
  fi
  
  (
    if ! ( ifconfig "$IFACE" || true ) | egrep -q 'inet '
    then
      cat >/tmp/udhcpc.script <<'EOF'
#!/bin/busybox sh
set | egrep '^[a-z]+=' >/tmp/udhcpc.varset
EOF
      chmod a+x /tmp/udhcpc.script
      
      ifconfig           "$IFACE" up
      if udhcpc -n -q -i "$IFACE" -s /tmp/udhcpc.script || udhcpc -n -q -i "$IFACE" -s /tmp/udhcpc.script
      then
        . /tmp/udhcpc.varset
        ifconfig         "$IFACE" "$ip" netmask "$subnet"
        router="$(echo "$router" | cut -d " " -f 1)"
        route del default || true
        route add default gw "$router"
        ifconfig         "$IFACE"
      fi
    fi
    
    ( ( ifconfig "$IFACE" || true ) | egrep -q 'inet ' ) || true
  )
  
  echo nameserver 8.8.8.8 >/etc/resolv.conf
}

# we don't use this but we export it with declare
function dnsip_x64()
{
  dnsip "$1"
}

# we don't use this but we export it with declare
function dnsip_arm()
{
  nslookup "$1" | tail -n +5 | ( egrep '^Address [0-9]+: [0-9]+\.[0-9]+\.[0-9]+\.[0-9]$' || true ) | ( egrep -o '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]$' || true ) | head -n 1
}

# we don't use this but we export it with declare
function dnsip_()
{
  local OUT=""
  for i in $(seq 1 20)
  do
    [ "$OUT" != "" ] || OUT="$(dnsip_"$ARCH" "$1")"
  done
  [ "$OUT" != "" ] || OUT=0.0.0.0
  echo "$OUT"
}

# we don't use this but we export it with declare
function classical_resolve()
{
  if [ "${CLASSICAL_INSERT_DNS_HOST:0:4}" == "DNS:" ]
  then
    CLASSICAL_INSERT_DNS_HOST="${CLASSICAL_INSERT_DNS_HOST:4}"
    CLASSICAL_INSERT_DNS_HOST_RESOLVED="$(dnsip_ "$CLASSICAL_INSERT_DNS_HOST" | cut -d " " -f 1)"
  else
    CLASSICAL_INSERT_DNS_HOST_RESOLVED="$CLASSICAL_INSERT_DNS_HOST"
  fi
}

# we don't use this but we export it with declare
function classical_genurl()
{
  local PORTSPEC
  PORTSPEC=""
  if [ "$CLASSICAL_INSERT_HTTP_PORT" != "80" ]
  then
    PORTSPEC=":${CLASSICAL_INSERT_HTTP_PORT}"
  fi
  
  echo http://"${CLASSICAL_INSERT_DNS_HOST_RESOLVED}${PORTSPEC}${CLASSICAL_INSERT_HTTP_PATH}""$1"
}

# we don't use this but we export it with declare
function classical_geturl()
{
  local NAME
  NAME="$1"
  touch ./classical/"$NAME"
  local URL
  URL="$(classical_genurl "$NAME")"
  wget --header="Host: $CLASSICAL_INSERT_HTTP_HOST" -O ./classical/"$NAME" "$URL"
}

function fakeroot_tar()
{
  tar --owner=0 --group=0 --mtime=0 "$@"
}

function stage3_overlays()
{
  mkdir ./initramfs/overlay
  busybox mount -t tmpfs none ./initramfs/overlay
  
  local i
  for i in "${CHAIN_OVERLAYS[@]}"
  do
    if [ "$i" == "_" ] || [ "$i" == "$CHAIN_SEPARATOR" ]; then continue; fi
    
    if   [ -d /config/overlay/"$i" ]
    then
      cp_ /config/overlay/"$i"/. ./initramfs/overlay/
    elif [ -d /overlay/"$i" ]
    then
      cp_ /overlay/"$i"/. ./initramfs/overlay/
    else
      echo "fatal: cannot source overlay '${i}'"
      exit 1
    fi
  done
  
  mkdir -p ./initramfs/overlay/tmp/dg
  
  (
    declare -p CHAIN_SEPARATOR CHAIN_OVERLAYS
    
    declare -f f_defs
    
    echo '
function f_root()
{
  local CMD
'
    chain_act_root_runall
    echo '
}
function f_user()
{
  local CMD
'
    chain_act_user_runall
    echo '}
'
  ) >./initramfs/overlay/tmp/dg/conf
  
  ( cd ./initramfs/overlay ; find . -type f -o -type l | fakeroot_tar -c -T - ) >./initramfs/overlay.tar
  
  busybox umount ./initramfs/overlay
  rmdir ./initramfs/overlay
}

function initramfs_add_tools()
{
  mkdir -p ./initramfs/builds_tools
  
  local TOOL
  for TOOL in "$@"
  do
    local SRCSEL_TOOL
    srcsel_tool "$TOOL"
    cp_ "$SRCSEL_TOOL"/"$TOOL" ./initramfs/builds_tools/"$TOOL"
  done
}

# we don't use this but we export it with declare
function kexec_prepare()
{
  # carry forward ssh host key and all loaded data to stage3
  local SSH_HOST_KEY
  SSH_HOST_KEY=""
  [ -d ./ssh-host-key ] && SSH_HOST_KEY=./ssh-host-key
  find $SSH_HOST_KEY ./sg_pl_ini ./classical | cpio -H newc -o >>./stage3_initrd.img
  
  if [ "$CLASSICAL_LANDER_EMMC_PROBE_WORKAROUND" == "y" ]
  then
    # CLASSICAL_LANDER_EMMC_PROBE_WORKAROUND=y requires that stage3 be
    # able to kexec itself, so append ./stage3.bin to the initramfs
    # for great recursive justice.
    echo ./stage3.bin | cpio --format=newc --reproducible --create >>./stage3_initrd.img
  fi
}

# we don't use this but we export it with declare
function kexec_x64()
{
  kexec_prepare
  kexec \
    --type=bzImage \
    --load ./stage3_kernel.zim \
    --initrd=./stage3_initrd.img \
    --command-line="$(cat ./stage3_knlopt.txt)" \
    --force
}

# we don't use this but we export it with declare
function kexec_arm()
{
  kexec_prepare
  kexec \
    --type=zImage \
    --load ./stage3_kernel.zim \
    --initrd=./stage3_initrd.img \
    --dtb=./stage3_fdtree.dtb \
    --command-line="$(cat ./stage3_knlopt.txt)" \
    --force
}

# we don't use this but we export it with declare
function kexec_veysp()
{
  kexec_prepare
  penguinize_stage3_veysp
  cat ./stage3_penguin_A ./stage3_penguin_B ./stage3_penguin_C ./stage3_penguin_D |\
    dd of=/dev/mem oflag=seek_bytes seek=$(( 0x20000000 ))
  modprobe flush_data_cache
  echo b >/proc/sysrq-trigger
  reboot -f
}

# stage3 is supposed to:
# - prompt for the partition to use, or to enter basic partitioning tool
# ---> we can even require our own partition type guid to prevent disasters!
# - once a partition has been selected, cache the stages in its reserved area
# ---> unless that exact data is already there
# - mount remote nbd backed by the partition
# - boot in!

function stage3_common()
{
  # stage3 binaries
  initramfs_add_binaries busybox bash sgdisk partx udevadm dmsetup nbd-client
  initramfs_add_binaries_dd
  initramfs_add_binaries_dialog
  initramfs_add_binaries_if_x64 openvt
  initramfs_add_binaries_if_x64   /lib64/udev/scsi_id dnsip
  initramfs_add_binaries_if_arm /usr/lib/udev/scsi_id
  initramfs_add_tools linuxtools nbd-hyperbolic fanman safepipe
  if [ "$MODEL" == "veysp" ]
  then
    initramfs_add_tools gptize
  fi
  
  if [ "$ARCH" == "x64" ]
  then
    # for dialog
    cp_ --parents "$SRCSEL_X64"/etc/terminfo/ ./initramfs/
  fi
  
  # add additional binaries for debugging, if enabled
  if [ "$DEBUG_MODEL" == "y" ]
  then
    initramfs_add_binaries strace
    initramfs_add_binaries_if_arm gdbserver #mmc addpart delpart resizepart
  fi
  
  # add stageZ
  cp_ "$SRCSEL_LINUX_MODULES"/lib/modules/"$SRCSEL_LINUX_KVER"/boot/modules.sqs ./initramfs/modules.sqs.noz
  STAGEZ_MODULES_ALWAYS="${STAGE3_MODULES_PLATFORM_SPECIFIC[*]:1} ${STAGE3_MODULES_PLATFORM_INDEPENDENT[*]:1} $SRCSEL_LINUX_MAYBE_FBCON"
  if [ "$STAGE3_USB_NET" == "y" ]
  then
    STAGEZ_MODULES_ALWAYS="$STAGEZ_MODULES_ALWAYS ${STAGE3_MODULES_PLATFORM_INDEPENDENT_USB_NET[@]:1}"
  fi
  local i
  for i in "${STAGE3_MODULES_MODPROBE_FAIL_LAX[@]:1}"
  do
    if [ -n "$i" ]
    then
      touch ./initramfs/allow_modprobe_fail_"$i"
    fi
  done
  initramfs_add_modules loop squashfs
  stageZ_common
  initramfs_add_stageZ_entry_via_busybox stage3a n
  
  # load NH_{IMAGE_SIZE,USER_{BLOCK_SIZE_LOG,A,B,C,D}} values
  . "$SRCSEL_ROOTFS".inf
  
  # copy .hyp directly into stage3
  cat "$SRCSEL_ROOTFS".hyp >./initramfs/rootfs.hyp.noz
  
  # adjust http path with rootfs.hyp sha256sum
  local ROOTFS_HYP_SUM
        ROOTFS_HYP_SUM="$(sha256sum "$SRCSEL_ROOTFS".hyp | cut -d " " -f 1)"
  CLASSICAL_LANDER_HTTP_PATH_DATA="$CLASSICAL_LANDER_HTTP_PATH_DATA""$ROOTFS_HYP_SUM".bin
  
  # save SRCSEL_HYPERBOLIC selection for fingen to be able to upload the required rootfs image
  export_loadable_variables SRCSEL_ROOTFS{,_NAME} >./srcsel_rootfs_variables
  
  export_loadable_variables \
      ARCH DEBUG_MODEL CLASSICAL_LANDER_BYPASS \
      COMMON_CACHE_PARTITION_{OFFSET,CLEAR_ZONE} \
      CLASSICAL_LANDER_{ETHERNET_INTERFACE,DNS_HOST,HTTP_{PARALLELISM,PORT,HOST,PATH_DATA},RESERVED_AREA_{SIZE,ALIGN}} \
      NH_{IMAGE_SIZE,CACHE_{BLOCK_SIZE_LOG,USER_{A,B,C,D}}} \
      CLASSICAL_LANDER_EMMC_{PROBE,LOCKED}_WORKAROUND \
    | initramfs_drop classical-lander-variables
  
  CLASSICAL_LANDER_EXPORT_LD_LIBRARY_PATH=n
  
  if [ "$ARCH" == "x64" ]
  then
    CLASSICAL_LANDER_EXPORT_LD_LIBRARY_PATH=y
    
    (
      LD_LIBRARY_PATH="$(cat /x64/ld_library_path)"
      export_loadable_variables LD_LIBRARY_PATH
    ) | initramfs_drop -a classical-lander-variables
  fi
  
  export_loadable_variables CLASSICAL_LANDER_EXPORT_LD_LIBRARY_PATH | initramfs_drop -a classical-lander-variables
  
  function stageZe_d16()
  {
    (
      modprobe k10temp   || [ -f /allow_modprobe_fail ]
      modprobe i2c-piix4 || [ -f /allow_modprobe_fail ]
      modprobe w83795    || [ -f /allow_modprobe_fail ]
      modprobe w83627ehf || [ -f /allow_modprobe_fail ]
      
      CELSIUS_COUNT=0
      CELSIUS_FILES=""
      
      for i in /sys/class/hwmon/hwmon*
      do
        if [ -f "$i"/name ] && [ "$(cat "$i"/name)" == "k10temp" ]
        then
          CELSIUS_COUNT=$(( (CELSIUS_COUNT+1) ))
          CELSIUS_FILES="${CELSIUS_FILES} ${i}/temp1_input"
        fi
      done
      
      cp /builds_tools/fanman /tmp/fanman
      
      (
        ulimit -s 16 # 4 does not work, 8 works, but double it to be safe
        /tmp/fanman "$CELSIUS_COUNT" $CELSIUS_FILES 1 /sys/devices/pci0000\:00/0000\:00\:14.0/i2c-??/??-002f/pwm1 "$FANMAN_CELSIUS_LO" "$FANMAN_CELSIUS_HI" "$FANMAN_PWM_IDLE" "$FANMAN_PWM_FULL" </dev/null &>/dev/null &
      )
      
      rm -f /tmp/fanman # remove the executable file so it cannot be modified
      cp /builds_tools/fanman /tmp/fanman # make another copy so it can be run by the user
    )
  }
  
  function stageZe_main()
  {
    if [ "$MODEL" == "d16" ]
    then
      stageZe_"$MODEL"
    fi
    
    [ -d ./ssh-host-key ] && cp -a ./ssh-host-key /tmp/
    
    exec bash ./classical-lander.sh "$@"
  }
  
  export_loadable_variables MODEL | initramfs_drop stageZev
  declare -f stageZe_main | initramfs_drop -a stageZev
  if [ "$MODEL" == "d16" ]
  then
    export_loadable_variables FANMAN_{CELSIUS_{LO,HI},PWM_{IDLE,FULL}} | initramfs_drop -a stageZev
    declare -f stageZe_"$MODEL" | initramfs_drop -a stageZev
  fi
  
  initramfs_banter_shell stageZe ""
  initramfs_drop -a stageZe <<'EOF'
# banter shell ...

. ./stageZev

stageZe_main
EOF
  
  declare -f dd_ dd_no_sync emmc_probe_status eth_bring_up_if_down dnsip_{,x64,arm} | initramfs_drop -a classical-lander-variables
  
  if [ "$CLASSICAL_LANDER_EMMC_PROBE_WORKAROUND" == "y" ]
  then
    export_loadable_variables MODEL | initramfs_drop -a classical-lander-variables
    
    declare -f kexec_{prepare,x64,arm} | initramfs_drop -a classical-lander-variables
    
    initramfs_add_binaries cpio
    
    if [ "$MODEL" == "veysp" ]
    then
      initramfs_add_binaries dtc
      initramfs_add_tools murmur
      declare -f kexec_veysp penguinize_stage3_veysp penguinize_stage3 penguinize_generic fdtree_fiddle_veysp binu32 binchr | initramfs_drop -a classical-lander-variables
      export_loadable_variables MODEL_VEYSP_4GB | initramfs_drop -a classical-lander-variables
    fi
  fi
  
  cp_ /files/classical-lander.sh ./initramfs/
}

function fdtree_fiddle_veysp()
{
  function fdtree_prepend_memreserve()
  {
    local A
    A="$1"
    local B
    B="$2"
    
    A="$(printf 0x%x "$A")"
    B="$(printf 0x%x "$B")"
    
    sed -i -e '2i/memreserve/'"$A"' '"$B"';' ./"$PENGUINIZE_PREFIX"_fdtree.dts
  }
  
  fdtree_prepend_memreserve "$BA_IRD" "$SZ_IRD"
  fdtree_prepend_memreserve "$BA_DTB" "$SZ_DTB"
  
  cat >>./"$PENGUINIZE_PREFIX"_fdtree.dts <<EOF
/
{
  chosen
  {
    bootargs = "$FDTREE_FIDDLE_VEYSP_BOOTARGS";
    linux,initrd-start = <$(printf 0x%x "$BA_IRD")>;
    linux,initrd-end   = <$(printf 0x%x "$(( (BA_IRD+SZ_IRD_ORIG) ))")>;
  };
};
EOF
  
  if [ "$FDTREE_FIDDLE_VEYSP_ARM_PENGUIN_LOADER" == "y" ]
  then
    cat >>./"$PENGUINIZE_PREFIX"_fdtree.dts <<EOF
/
{
  reserved-memory
  {
    arm-penguin-loader-head@20000000
    {
      reg = <0x20000000 0x00001000>;
    };
    arm-penguin-loader-body@20000000
    {
      reg = <0x20001000 0x07fff000>;
    };
  };
};
EOF
  fi
  
  if [ "$MODEL_VEYSP_4GB" == "y" ]
  then
    cat >>./"$PENGUINIZE_PREFIX"_fdtree.dts <<'EOF'
/
{
  memory@0
  {
    device_type = "memory";
    /* reg = <0x00000000 0xfe000000>; # before 4.14.x */
    reg = <0x0 0x0 0x0 0xfe000000>;
  };
};
EOF
  fi
}

function stage3()
{
  initramfs_init
  
  stage3_common
  
  # let's not forget the overlays
  stage3_overlays
  
  initramfs_add_binaries_finally
  initramfs_add_modules_finally
  initramfs_no_modules_alias
  unpranker_pack ./init-stage3a ./initramfs /stage3a "${STAGE3A_ARID-y}"
  cp ./init-stage3a ./init
  initramfs_fini stage3_content_initramfs
  
  initramfs_pack_init_only
  
  initramfs_init
  
  # include linux in an architecture-dependent way
  function f_x64() {
    cp_ "$SRCSEL_LINUX_MODULES"/lib/modules/"$SRCSEL_LINUX_KVER"/boot/bzImage               ./initramfs/stage3_kernel.zim.noz
  }
  function f_arm() {
    cp_ "$SRCSEL_LINUX_MODULES"/lib/modules/"$SRCSEL_LINUX_KVER"/boot/zImage                ./initramfs/stage3_kernel.zim.noz
    cp_ "$SRCSEL_LINUX_MODULES"/lib/modules/"$SRCSEL_LINUX_KVER"/boot/"$LINUX_DTB_NAME".dtb ./initramfs/stage3_fdtree.dtb
  }
  f_"$ARCH"
  unset f_x64 f_arm
  
  # include kernel options
  echo "$LINUX_CMDLINE" >./initramfs/stage3_knlopt.txt
  
  # include initrd
  mv ./initrd.img ./initramfs/stage3_initrd.img.noz
  
  unpranker_pack ./stage3.bin ./initramfs "" "${STAGE3_ARID-y}"
  initramfs_fini stage3_content
}

function penguinize_generic()
{
  local BA_MEM
  local BA_ZIM BA_DTB BA_IRD
  local SZ_ZIM SZ_IRD SZ_DTB SZ_IRD_ORIG
  local SZ_LB_ZIM SZ_LB_DTB SZ_LB_IRD
  local BA_LB_ZIM BA_LB_DTB BA_LB_IRD
  local BA_PSEUDO_KEXEC SZ_PSEUDO_KEXEC
  local EX_BA_LB_ZIM EX_BA_LB_DTB EX_BA_LB_IRD
  local MM_ZIM MM_DTB MM_IRD MM_HDR
  local SZ_TOTAL
  
  BA_MEM="$PENGUINIZE_BA_MEM"
  
  BA_ZIM=$(( (BA_MEM + ( 32*(1024**2))) ))
  BA_DTB=$(( (BA_MEM + (128*(1024**2))) ))
  BA_IRD=$(( (BA_MEM + (130*(1024**2))) ))
  
  # add blanking block and pad zim and ird up to block size
  
  SZ_ZIM="$(stat -c %s  ./"$PENGUINIZE_PREFIX"_kernel.zim)"
  SZ_ZIM=$(( (((SZ_ZIM+512+511)/512)*512) ))
  truncate -s "$SZ_ZIM" ./"$PENGUINIZE_PREFIX"_kernel.zim
  
  SZ_IRD="$(stat -c %s  ./"$PENGUINIZE_PREFIX"_initrd.img)"
  SZ_IRD_ORIG="$SZ_IRD"
  SZ_IRD=$(( (((SZ_IRD+512+511)/512)*512) ))
  truncate -s "$SZ_IRD" ./"$PENGUINIZE_PREFIX"_initrd.img
  
  # add additional block for dtb as we may grow it slightly
  
  SZ_DTB="$(stat -c %s  ./"$PENGUINIZE_PREFIX"_fdtree.dtb)"
  SZ_DTB=$(( (((SZ_DTB+512+512+511)/512)*512) ))
  
  dtc -I dtb -O dts <./"$PENGUINIZE_PREFIX"_fdtree.dtb >./"$PENGUINIZE_PREFIX"_fdtree.dts
  
  penguinize_generic_fdtree_fiddle
  
  dtc -I dts -O dtb <./"$PENGUINIZE_PREFIX"_fdtree.dts >./"$PENGUINIZE_PREFIX"_fdtree.dtb
  [ "$(stat -c %s ./"$PENGUINIZE_PREFIX"_fdtree.dtb)" -le "$SZ_DTB" ] # make sure we didn't exceed the size budget
  truncate -s "$SZ_DTB" ./"$PENGUINIZE_PREFIX"_fdtree.dtb
  
  SZ_LB_ZIM=$(( ((SZ_ZIM+511)/512) ))
  SZ_LB_DTB=$(( ((SZ_DTB+511)/512) ))
  SZ_LB_IRD=$(( ((SZ_IRD+511)/512) ))
  
  BA_LB_ZIM=1
  BA_LB_DTB=$(( BA_LB_ZIM+SZ_LB_ZIM ))
  BA_LB_IRD=$(( BA_LB_DTB+SZ_LB_DTB ))
  
  EX_BA_LB_ZIM=$(( (BA_LB_ZIM*512) ))
  EX_BA_LB_DTB=$(( (BA_LB_DTB*512) ))
  EX_BA_LB_IRD=$(( (BA_LB_IRD*512) ))
  
  EX_SZ_LB_ZIM=$(( (SZ_LB_ZIM*512) ))
  EX_SZ_LB_DTB=$(( (SZ_LB_DTB*512) ))
  EX_SZ_LB_IRD=$(( (SZ_LB_IRD*512) ))
  
  MM_ZIM="$("$PENGUINIZE_MURMUR" "$EX_SZ_LB_ZIM" ./"$PENGUINIZE_PREFIX"_kernel.zim 2>&1)"
  MM_DTB="$("$PENGUINIZE_MURMUR" "$EX_SZ_LB_DTB" ./"$PENGUINIZE_PREFIX"_fdtree.dtb 2>&1)"
  MM_IRD="$("$PENGUINIZE_MURMUR" "$EX_SZ_LB_IRD" ./"$PENGUINIZE_PREFIX"_initrd.img 2>&1)"
  
  # bash only
  if [ -n "${BASH_VERSION-}" ]
  then
    local REGEX
    REGEX="^(0|([1-9][0-9]*))$"
    [[ "$MM_ZIM" =~ $REGEX ]]
    [[ "$MM_DTB" =~ $REGEX ]]
    [[ "$MM_IRD" =~ $REGEX ]]
  fi
  
  (
    binu32 "$BA_ZIM"
    binu32 "$EX_BA_LB_ZIM"
    binu32 "$EX_SZ_LB_ZIM"
    binu32 "$MM_ZIM"
    
    binu32 "$BA_DTB"
    binu32 "$EX_BA_LB_DTB"
    binu32 "$EX_SZ_LB_DTB"
    binu32 "$MM_DTB"
    
    binu32 "$BA_IRD"
    binu32 "$EX_BA_LB_IRD"
    binu32 "$EX_SZ_LB_IRD"
    binu32 "$MM_IRD"
  ) >./"$PENGUINIZE_PREFIX"_penguin_header
  
  MM_HDR="$("$PENGUINIZE_MURMUR" "$(wc -c <./"$PENGUINIZE_PREFIX"_penguin_header)" ./"$PENGUINIZE_PREFIX"_penguin_header 2>&1)"
  
  (
    echo -n "De8m9UqGsNieAGWB"
    
    binu32 "$MM_HDR"
    
    cat ./"$PENGUINIZE_PREFIX"_penguin_header
  ) >./"$PENGUINIZE_PREFIX"_penguin_A
  
  truncate -s 512 ./"$PENGUINIZE_PREFIX"_penguin_A
  
  mv ./"$PENGUINIZE_PREFIX"_kernel.zim ./"$PENGUINIZE_PREFIX"_penguin_B
  mv ./"$PENGUINIZE_PREFIX"_fdtree.dtb ./"$PENGUINIZE_PREFIX"_penguin_C
  mv ./"$PENGUINIZE_PREFIX"_initrd.img ./"$PENGUINIZE_PREFIX"_penguin_D
  
  SZ_TOTAL="$(cat ./"$PENGUINIZE_PREFIX"_penguin_A ./"$PENGUINIZE_PREFIX"_penguin_B ./"$PENGUINIZE_PREFIX"_penguin_C ./"$PENGUINIZE_PREFIX"_penguin_D | wc -c)"
  [ "$SZ_TOTAL" -le "$PENGUINIZE_SZ_LIMIT" ]
}

function penguinize_stage3()
{
  local SZ_PSEUDO_KEXEC
  SZ_PSEUDO_KEXEC=$(( 0x08000000 ))
  local PENGUINIZE_PREFIX PENGUINIZE_MURMUR PENGUINIZE_BA_MEM PENGUINIZE_SZ_LIMIT
  PENGUINIZE_PREFIX=stage3
  PENGUINIZE_MURMUR=/builds_tools/murmur
  PENGUINIZE_BA_MEM=0
  PENGUINIZE_SZ_LIMIT="$SZ_PSEUDO_KEXEC"
  penguinize_generic_fdtree_fiddle() {
    penguinize_stage3_fdtree_fiddle
  }
  penguinize_generic
}

function penguinize_stage3_veysp()
{
  penguinize_stage3_fdtree_fiddle() {
    FDTREE_FIDDLE_VEYSP_BOOTARGS="$(cat ./stage3_knlopt.txt)" FDTREE_FIDDLE_VEYSP_ARM_PENGUIN_LOADER=y fdtree_fiddle_veysp
  }
  
  penguinize_stage3
}

# stage2 is supposed to:
# - use either stage1 or stage2 kexec to kexec into stage3
# 
# stage3 is directly embedded in stage2, there is no additional fetch
# for stage3.
# 
# additional modules are absolutely not allowed in stage2! this is
# because stage2 might be generated from a completely different kernel
# build than stage0/stage1 were distilled from. additional modules are
# allowed in stage3, but that can only work reliably if a real kexec
# is done. SKIP_KEXEC is really only intended for development, not
# production use.
function stage2()
{
  initramfs_init
  
  initramfs_add_binaries cpio
  
  # add kexec if needed
  # - if included, this will simply overwrite stage1's kexec; no need to branch on that again
  if [ "$STAGE2_USE_STAGE1_KEXEC" != "y" ]
  then
    initramfs_add_binaries kexec
  fi
  
  # embed stage3
  cp ./stage3.bin ./initramfs/stage3.bin.noz
  
  # we don't use this but we export it with declare
  function stage2a_main()
  {
    # unpack stage3
    ./stage3.bin
    
    # support unpacking only, signaled by environment variable
    if [ "${FINFIN_STAGE2_UNPACK_ONLY-}" == "y" ]
    then
      exit 0
    fi
    
    if [ "$STAGE2_SKIP_KEXEC" == "y" ]
    then
      mkdir ./newt
      mount -t tmpfs none ./newt
      ( cd ./newt ; cpio -F ./../stage3_initrd.img -i )
      # carry forward ssh host key and all loaded data as in kexec_prepare
      SSH_HOST_KEY=""
      [ -d ./ssh-host-key ] && SSH_HOST_KEY=./ssh-host-key
      cp -a $SSH_HOST_KEY ./sg_pl_ini ./classical ./newt/
      cat >./bootcont <<'EOF'
# give assurance to switch_root that this is an initramfs
rm -f /init
touch /init
# pass control to the new init
exec switch_root /newt /init "$@"
false
EOF
    else
      if [ "$MODEL" == "veysp" ]
      then
        kexec_veysp
      else
        kexec_"$ARCH"
      fi
      
      false
    fi
  }
  
  export_loadable_variables \
      ARCH MODEL \
      STAGE2_SKIP_KEXEC \
    | initramfs_drop -a stage2av
  
  declare -f stage2a_main kexec_{prepare,x64,arm} | initramfs_drop -a stage2av
  
  # needed due to the funny business in kexec_prepare
  export_loadable_variables \
    CLASSICAL_LANDER_EMMC_PROBE_WORKAROUND \
    | initramfs_drop -a stage2av
  
  if [ "$MODEL" == "veysp" ]
  then
    initramfs_add_binaries dtc
    initramfs_add_tools murmur
    declare -f kexec_veysp penguinize_stage3_veysp penguinize_stage3 penguinize_generic fdtree_fiddle_veysp binu32 binchr | initramfs_drop -a stage2av
    export_loadable_variables MODEL_VEYSP_4GB | initramfs_drop -a stage2av
  fi
  
  initramfs_banter_shell stage2a "#!/bin/busybox sh"
  initramfs_drop -a stage2a <<'EOF'
. ./stage2av

stage2a_main

false
EOF
  
  initramfs_add_binaries_finally
  
  unpranker_pack ./stage2.bin ./initramfs /stage2a y
  initramfs_fini stage2_content
}

# stage1 is supposed to:
# - bring up the display, so things are no longer running blind
# - load stage2
# - verify stage2 by public key
# - prompt user
# - exec stage2
function stage1()
{
  initramfs_init
  
  # add stage1 binaries
  # adding dnsip and gpg bumps us up from 5.2M to 7.4M
  # we should probably get rid of these in the future
  initramfs_add_binaries busybox gpgv2 kexec
  initramfs_add_binaries_dd
  
  # add x64-only stage1 binaries
  # no dnsip in buildroot, but there busybox's nslookup works
  if [ "$ARCH" == "x64" ]
  then
    initramfs_add_binaries dnsip
  fi
  
  # add additional binaries for debugging, if enabled
  if [ "$DEBUG_MODEL" == "y" ]
  then
    initramfs_add_binaries strace
  fi
  
  # add tools
  initramfs_add_tools safepipe
  
  # on x64, add pci ids for lspci hardware detection
  if [ "$ARCH" == "x64" ]
  then
    cp_ --parents /x64/usr/share/misc/pci.ids.gz ./initramfs/
  fi
  
  # add stageZ
  
  initramfs_add_modules "${STAGE1_MODULES_PLATFORM_SPECIFIC[@]:1}" "${STAGE1_MODULES_PLATFORM_INDEPENDENT[@]:1}" $SRCSEL_LINUX_MAYBE_FBCON "${STAGE1_MODULES_WITHOUT_AUTO_LOAD[@]:1}"
  STAGEZ_MODULES_ALWAYS="${STAGE1_MODULES_PLATFORM_SPECIFIC[*]:1}   ${STAGE1_MODULES_PLATFORM_INDEPENDENT[*]:1}  $SRCSEL_LINUX_MAYBE_FBCON"
  stageZ_common
  initramfs_add_stageZ_entry_via_busybox stage1a n
  
  # chain from stageZ to classical-insert
  initramfs_banter_shell stageZe ""
  initramfs_drop -a stageZe <<'EOF'
# banter shell ...

exec busybox sh ./classical-insert.sh
EOF
  
  # add classical-insert
  
  local CLASSICAL_INSERT_PROBE
  CLASSICAL_INSERT_PROBE="$(echo /dev/hd{a..z} /dev/sr{0..9} /dev/sd{a..z} /dev/vd{a..z} /dev/mmcblk{0..9})"
  
  export_loadable_variables \
      MACHINE_NAME ARCH DEBUG_MODEL CLASSICAL_INSERT_BYPASS \
      COMMON_CACHE_PARTITION_{OFFSET,CLEAR_ZONE} \
      CLASSICAL_INSERT_{PROBE,ETHERNET_INTERFACE,DNS_HOST,HTTP_{PORT,HOST,PATH},PKEY_{AUTH,MAXL}} \
      CLASSICAL_INSERT_EMMC_PROBE_WORKAROUND \
    | initramfs_drop -a classical-insert-variables
  declare -f dd_ dd_no_sync emmc_probe_status eth_bring_up_if_down classical_{resolve,genurl,geturl} dnsip_{,x64,arm} | initramfs_drop -a classical-insert-variables
  
  cp_ /files/classical-insert.sh ./initramfs/
  
  # finalize
  
  initramfs_add_binaries_finally
  initramfs_add_modules_finally
  initramfs_no_modules_alias
  
  unpranker_pack ./stage1.bin ./initramfs /stage1a y
  initramfs_fini stage1_content
}

function stage0_ssh_host_key()
{
  local DEST
  DEST="$1"
  
  local PFIX
  PFIX=./persist/ssh-host-key/"$MACHINE_NAME"/ssh_host_ed25519_key
  
  if [ ! -f "$PFIX" ] || [ ! -f "$PFIX".pub ]
  then
    mkdir -p "$(dirname "$PFIX")"
    # ssh-keygen likes to know who is invoking it
    mkdir -p /etc
    echo 'root:x:0:0:root:/root:/bin/bash' >/etc/passwd
    ssh-keygen -t ed25519 -f "$PFIX" -N "" -C ""
  fi
  
  mkdir -p "$DEST"
  cp "$PFIX"{,.pub} "$DEST"
}

# stage0 is supposed to:
# - run the instigator to load and exec stage1
function stage0()
{
  initramfs_init
  
  initramfs_add_tools instigator
  
  initramfs_add_modules "${STAGE0_MODULES_PLATFORM_SPECIFIC[@]:1}" "${STAGE0_MODULES_PLATFORM_INDEPENDENT[@]:1}"
  
  if [ "$STAGE0_USB_NET" == "y" ]
  then
    initramfs_add_modules "${STAGE0_MODULES_PLATFORM_INDEPENDENT_USB_NET[@]:1}"
  fi
  
  declare -A DEJALOAD
  local X
  X=100
  for i in $INITRAMFS_ADD_MODULES_LIST
  do
    if [ "${DEJALOAD["$i"]-n}" != "y" ]
    then
      DEJALOAD["$i"]=y
      ln -vsf -T ./lib/modules/"$SRCSEL_LINUX_KVER"/"$i" ./initramfs/m"$X"
      X=$(( (X+1) ))
    fi
  done
  if (( X>999 ))
  then
    echo "too many modules"
    exit 1
  fi
  
  touch ./initramfs/sg_for_real             # old
  if [ "$INSTIGATOR_EMMC_PROBE_WORKAROUND" == "y" ]
  then
    touch ./initramfs/sg_do_emmc_probe_workaround
  fi
  touch ./initramfs/sg_do_{mount,dhcp,exec} # new
  echo -n 5000                                                      >./initramfs/sg_hb_ms
  echo -n                "$INSTIGATOR_ETHERNET_INTERFACE"           >./initramfs/sg_if_name
  echo -n /sys/class/net/"$INSTIGATOR_ETHERNET_INTERFACE"/operstate >./initramfs/sg_if_fn_o
  
  local SIZE_STAGE1
  SIZE_STAGE1="$(stat -c %s ./stage1.bin)"
  # calculate stage1 checksum (we will certainly need it)
  local CSUM_STAGE1
  CSUM_STAGE1="$(sha256sum ./stage1.bin | cut -d " " -f 1)"
  # adjust initramfs
  echo -n -e "$INSTIGATOR_DNS_HOST" >./initramfs/sg_dns_host
  echo -n -e "$INSTIGATOR_HTTP_PORT" >./initramfs/sg_http_port
  echo -n -e "GET ${INSTIGATOR_HTTP_PATH}${CSUM_STAGE1}${INSTIGATOR_HTTP_SUFF} "'HTTP/1.1\r\nHost: '"$INSTIGATOR_HTTP_HOST"'\r\nAccept-Encoding: identity\r\nConnection: close\r\n\r\n' >./initramfs/sg_pl_req
  echo -n "$SIZE_STAGE1" >./initramfs/sg_pl_siz
  echo -n "$CSUM_STAGE1" >./initramfs/sg_pl_sum
  
  echo -n "$INSTIGATOR_DRIVE_SETTLE_SECONDS" >./initramfs/sg_ds_s
  local X
  X=100
  local INSTIGATOR_PROBE
  INSTIGATOR_PROBE="$(echo /dev/hd{a..z} /dev/sr{0..9} /dev/sd{a..z} /dev/vd{a..z} /dev/mmcblk{0..9})"
  for i in $INSTIGATOR_PROBE
  do
    ln -vsf -T ."$i" ./initramfs/b"$X"; X="$(( (X+1) ))"
  done
  echo -n "$(( (COMMON_CACHE_PARTITION_OFFSET + COMMON_CACHE_PARTITION_CLEAR_ZONE) ))" >./initramfs/sg_pl_off
  dd if=./stage1.bin.rid of=./initramfs/sg_pl_rid
  
  if [ "$MANAGE_SSH_HOST_KEY" == "y" ]
  then
    stage0_ssh_host_key ./initramfs/ssh-host-key/
  fi
  
  initramfs_add_modules_finally
  initramfs_no_modules_alias
  
  if [ "${USE_LINUX_MIN-}" != "" ]
  then
    rm -rf ./initramfs/lib/modules
    rm -f  ./initramfs/m*
    touch  ./initramfs/allow_modprobe_fail
  fi
  
  unpranker_pack ./init-stage0 ./initramfs /builds_tools/instigator y
  cp ./init-stage0 ./init
  initramfs_fini stage0_content_initramfs
  
  initramfs_pack_init_only
  echo "initrd.img" >>/product
}

# stageF is used for FEL/MaskROM booting only. it's supposed to load
# and execute stage3 over the network.
function stageF()
{
  initramfs_init
  
  # stageF binaries
  initramfs_add_binaries busybox
  
  initramfs_add_modules "${STAGEF_MODULES_PLATFORM_SPECIFIC[@]:1}" "${STAGEF_MODULES_PLATFORM_INDEPENDENT[@]:1}"
  STAGEZ_MODULES_ALWAYS="${STAGEF_MODULES_PLATFORM_SPECIFIC[*]:1}   ${STAGEF_MODULES_PLATFORM_INDEPENDENT[*]:1}"
  stageZ_common
  initramfs_add_stageZ_entry_via_busybox stageFa n
  
  STAGEF_CSUM_STAGE3_BIN="$(sha256sum ./init-stage3a | cut -d " " -f 1)"
  STAGEF_CSUM_ROOTFS_HYP="$(sha256sum ./stage3_content_initramfs/rootfs.hyp.noz | cut -d " " -f 1)"
  
  . "$SRCSEL_ROOTFS".inf
  STAGEF_CSUM_ROOTFS_BIN="$CSUM_ROOTFS"
  
  if [ "$STAGEF_AUTONOMOUS" == "y" ]
  then
    cp ./init-stage3a                     ./initramfs/stage3.bin
    cp /rootfs-mirror"$SRCSEL_ROOTFS".sqs ./initramfs/rootfs.sqs
  fi
  
  STAGEF_DATE_UIS="$(date -u -Iseconds)"
  
  function stageZe_main()
  {
    CLASSICAL_INSERT_DNS_HOST="$CLASSICAL_STAGEF_DNS_HOST"
    CLASSICAL_INSERT_HTTP_PORT="$CLASSICAL_STAGEF_HTTP_PORT"
    CLASSICAL_INSERT_HTTP_HOST="$CLASSICAL_STAGEF_HTTP_HOST"
    CLASSICAL_INSERT_HTTP_PATH="$CLASSICAL_STAGEF_HTTP_PATH"
    
    eth_bring_up_if_down "$CLASSICAL_STAGEF_ETHERNET_INTERFACE"
    
    classical_resolve
    
    mkdir -p ./classical
    mount -t tmpfs none ./classical
    # leave the tmpfs limited to half of ram; stage3+rootfs could get large
    
    CLASSICAL_INSERT_HTTP_PATH=/
    
    if [ ! -e ./stage3.bin ]
    then
      classical_geturl stage3.bin-"$STAGEF_CSUM_STAGE3_BIN".bin
      ACTUAL_CSUM_STAGE3_BIN="$(sha256sum ./classical/stage3.bin-"$STAGEF_CSUM_STAGE3_BIN".bin | cut -d " " -f 1)"
      [ "$ACTUAL_CSUM_STAGE3_BIN" == "$STAGEF_CSUM_STAGE3_BIN" ]
      chmod a+x ./classical/stage3.bin-"$STAGEF_CSUM_STAGE3_BIN".bin
      ln -vsfT  ./classical/stage3.bin-"$STAGEF_CSUM_STAGE3_BIN".bin ./stage3.bin
    fi
    
    if [ ! -e ./rootfs.sqs ]
    then
      classical_geturl rootfs.bin-"$STAGEF_CSUM_ROOTFS_HYP".bin
      ACTUAL_CSUM_ROOTFS_BIN="$(sha256sum ./classical/rootfs.bin-"$STAGEF_CSUM_ROOTFS_HYP".bin | cut -d " " -f 1)"
      [ "$ACTUAL_CSUM_ROOTFS_BIN" == "$STAGEF_CSUM_ROOTFS_BIN" ]
      ln -vsfT  ./classical/rootfs.bin-"$STAGEF_CSUM_ROOTFS_HYP".bin ./rootfs.sqs
    fi
    
    echo "$STAGEF_DATE_UIS" >./stageF_date_uis
  }
  
  stage0_ssh_host_key ./initramfs/ssh-host-key/
  
  export_loadable_variables \
      ARCH \
      CLASSICAL_STAGEF_{ETHERNET_INTERFACE,DNS_HOST,HTTP_{PORT,HOST,PATH}} \
      STAGEF_CSUM_{STAGE3_BIN,ROOTFS_{HYP,BIN}} \
      STAGEF_DATE_UIS \
    | initramfs_drop -a stageZev
  declare -f stageZe_main eth_bring_up_if_down classical_{resolve,genurl,geturl} dnsip_{,x64,arm} | initramfs_drop -a stageZev
  
  initramfs_banter_shell stageZe ""
  initramfs_drop -a stageZe <<'EOF'
# banter shell ...

. ./stageZev

stageZe_main

cat >./bootcont <<'DBLEOF'
rm -f /bootcont
exec ./stage3.bin "$@"
DBLEOF
EOF
  
  initramfs_add_binaries_finally
  initramfs_add_modules_finally
  initramfs_no_modules_alias
  unpranker_pack ./init-stageFa ./initramfs /stageFa y
  cp ./init-stageFa ./init
  initramfs_fini stageF_content_initramfs
  
  initramfs_pack_init_only
}

function firstline()
{
  local X
  IFS= read X
  echo "$X"
  cat >&2
}

function binchr()
{
  local X="$1"
  printf '\'"$(printf "%03o" "$X")"
}

function binu32()
{
  local X="$1"
  binchr $(( (X >> (8*0)) & 0xFF))
  binchr $(( (X >> (8*1)) & 0xFF))
  binchr $(( (X >> (8*2)) & 0xFF))
  binchr $(( (X >> (8*3)) & 0xFF))
}

function binu64()
{
  local X="$1"
  binchr $(( (X >> (8*0)) & 0xFF))
  binchr $(( (X >> (8*1)) & 0xFF))
  binchr $(( (X >> (8*2)) & 0xFF))
  binchr $(( (X >> (8*3)) & 0xFF))
  binchr $(( (X >> (8*4)) & 0xFF))
  binchr $(( (X >> (8*5)) & 0xFF))
  binchr $(( (X >> (8*6)) & 0xFF))
  binchr $(( (X >> (8*7)) & 0xFF))
}

function unpranker_pack_patch_segment_x64()
{
  local FILE
  FILE="$1"
  local SIZE
  SZIM="$(stat -c %s "$FILE")"
  
  for i in $((0x98)) $((0xa0))
  do
    binu64 "$SZIM" | dd of="$FILE" bs=1 seek="$i" conv=notrunc
  done
}

function unpranker_pack_patch_segment_arm()
{
  local FILE
  FILE="$1"
  local SIZE
  SZIM="$(stat -c %s "$FILE")"
  
  for i in $((0x64)) $((0x68))
  do
    binu32 "$SZIM" | dd of="$FILE" bs=1 seek="$i" conv=notrunc
  done
}

function unpranker_pack_patch_segment()
{
  unpranker_pack_patch_segment_"$ARCH" "$@"
}

function unpranker_pack_with_filter_and_rename()
{
  find . -type f -o -type l | unpranker_pack_filter |\
  (
    while read LINE
    do
      NAME="$(unpranker_pack_rename "$LINE")"
      
      echo -n -e "u${NAME}\0"
      
      if   [ -h "$LINE" ]
      then
        echo -n -e "h${NAME}\0"
        echo -n -e "$(readlink ${LINE})\0"
      else
        if [ -x "$LINE" ]
        then
          echo -n -e "x"
        else
          echo -n -e "f"
        fi
        
        SIZE="$(stat -c %s "$LINE")"
        echo -n -e "${NAME}\0" # in bash, \0 will not work unless it is the last thing specified to echo. yeah.
        echo -n -e "${SIZE}\0"
        
        dd if="$LINE"
      fi
    done
  )
}

# files that are already compressed (or otherwise not compressable)
# should have the extension .noz, which will be stripped when adding
# the files to the archive
function unpranker_pack()
{
  local FILE="$1" # output file
  local ROOT="$2" # root directory
  local EXEC="$3" # if not "", exec target
  local ARID="$4" # if y, append a random unique identifier
  
  # not used for anything; this is just for information
  # the big stuff (i.e., archives) float to the top and one can check that they have .noz where appropriate
  (
    cd "$ROOT"
    
    #find . -printf "%s %p %y\n" | busybox sort -r -n # no longer works since using busybox find
  ) >"$FILE".tmp.0
  
  (
    cd "$ROOT"
    
    find . -type d |\
    (
      while read LINE
      do
        if [ "$LINE" != "." ]
        then
          echo -n -e "d${LINE}\0"
        fi
      done
    )
    
    function unpranker_pack_filter() { egrep -v '\.noz$' || true ;}
    function unpranker_pack_rename() { echo "$1" ;}
    unpranker_pack_with_filter_and_rename
    
    echo -n -e "R"
  ) >"$FILE".tmp.1
  
  xz --check=crc32 -0 <./"$FILE".tmp.1 >./"$FILE".tmp.2
  
  (
    echo -n "H578OhBMuIxJR80C;"
    echo -n "5786;" # xz compressed magic
    echo -n "$(stat -c %s ./"$FILE".tmp.1);"
    echo -n "$(stat -c %s ./"$FILE".tmp.2);"
  ) >./"$FILE".tmp.3

  (
    echo -n "2595;" # uncompressed magic
    
    cd "$ROOT"
    
    function unpranker_pack_filter() { ( egrep '\.noz$' || true ) ;}
    function unpranker_pack_rename() { if [ "${1: -4}" == ".noz" ]; then echo "${1:0: -4}"; else echo "$1"; fi ;}
    unpranker_pack_with_filter_and_rename
    
    if [ -n "$EXEC" ]
    then
      echo -n -e "X${EXEC}\0"
    else
      echo -n -e "E"
    fi
  ) >./"$FILE".tmp.4
  
  local SRCSEL_TOOL
  srcsel_tool unpranker
  cat "$SRCSEL_TOOL"/unpranker "$FILE".tmp.3 "$FILE".tmp.2 "$FILE".tmp.4 >./"$FILE"
  
  #unpranker_pack_patch_segment ./"$FILE"
  
  chmod a+x ./"$FILE"
  
  if [ "$ARID" == "y" ]
  then
    # append a random unique identifier - deterministically generated from the content itself
    sha256sum ./"$FILE" | cut -d " " -f 1 | dd bs=$(( ((256/8)*2) )) count=1 iflag=fullblock >./"$FILE".rid
    cat ./"$FILE".rid >>./"$FILE"
  fi
}

function prepare_cbfstool()
{
  if [ "$HOSTARCH" == "x64" ]
  then
    function cbfstool_()
    {
      /x64/builds/coreboot/cbfstool "$@"
    }
  else
    function cbfstool_()
    {
      cbfstool "$@"
    }
  fi
}

function main_chip_x64()
{
  srcsel
  stage3
  stage2
  stage1
  stage0
  touch ./booster.rom
  if [ "${3-}" == "bootcd" ]
  then
    bootcd_common
  fi
  
  cp_ /builds/coreboot/"$BOOT_ROM".rom ./boot.rom
  
  cp_ "$SRCSEL_LINUX_MODULES"/lib/modules/"$SRCSEL_LINUX_KVER"/boot/bzImage .
  echo bzImage >>/product
  
  if [ "${USE_LINUX_MIN-}" != "" ]
  then
    cp_ /builds/linux-libre-final-min-"$USE_LINUX_MIN"/bzImage .
  fi
  
  prepare_cbfstool
  
  if [ "$BOOT_ROM_KEEP_SEABIOS" == "y" ]
  then
    echo -n -e "/rom@img/linux\nHALT\n" >./bootorder
    cbfstool_ ./boot.rom add          -f ./bootorder -n bootorder -t raw
    cbfstool_ ./boot.rom add-payload  -f ./bzImage   -n img/linux        -I ./initrd.img -C "$LINUX_CMDLINE"
  else
    for i in fallback/payload vgaroms/seavgabios.bin
    do
      cbfstool_ ./boot.rom remove -n "$i"
    done
    
    cbfstool_ ./boot.rom add-payload  -f ./bzImage   -n fallback/payload -I ./initrd.img -C "$LINUX_CMDLINE"
  fi
  
  cbfstool_ ./boot.rom print | tee ./boot.rom.toc
  
  echo boot.rom     >>/product
  echo boot.rom.toc >>/product
}

function main_chip_arm()
{
  srcsel
  stage3
  stage2
  stage1
  stage0
  
  cp_ /builds/coreboot/"$BOOT_ROM".rom ./boot.rom
  
  [ "$BOOT_ROM_PENGUIN" == "y" ]
  
  cp_ "$SRCSEL_LINUX_MODULES"/lib/modules/"$SRCSEL_LINUX_KVER"/boot/zImage                ./penguinize_kernel.zim
  cp_ "$SRCSEL_LINUX_MODULES"/lib/modules/"$SRCSEL_LINUX_KVER"/boot/"$LINUX_DTB_NAME".dtb ./penguinize_fdtree.dtb
  cp_ ./initrd.img                                                                        ./penguinize_initrd.img
  
  function f()
  {
    local PENGUINIZE_PREFIX PENGUINIZE_MURMUR PENGUINIZE_BA_MEM PENGUINIZE_SZ_LIMIT
    PENGUINIZE_PREFIX=penguinize
    srcsel_tool_host murmur
    PENGUINIZE_MURMUR="$SRCSEL_TOOL"/murmur
    unset SRCSEL_TOOL
    PENGUINIZE_BA_MEM=0
    PENGUINIZE_SZ_LIMIT=$(( 0x10000000 ))
    penguinize_generic_fdtree_fiddle() {
      FDTREE_FIDDLE_VEYSP_BOOTARGS="$LINUX_CMDLINE" FDTREE_FIDDLE_VEYSP_ARM_PENGUIN_LOADER=y fdtree_fiddle_veysp
    }
    penguinize_generic
  }; f
  
  cat ./penguinize_penguin_{A,B,C,D} >./penguin.bin
  
  prepare_cbfstool
  
  cbfstool_ ./boot.rom add -f ./penguin.bin -n penguin.bin -t raw
  
  cbfstool_ ./boot.rom print | tee ./boot.rom.toc
  
  echo boot.rom     >>/product
  echo boot.rom.toc >>/product
  
  if false # if true, prepare another penguin.bin for emulation in a similar way
  then
    cp_ "$SRCSEL_LINUX_MODULES"/lib/modules/"$SRCSEL_LINUX_KVER"/boot/zImage               ./penguinize_kernel.zim
    cp_ "$SRCSEL_LINUX_MODULES"/lib/modules/"$SRCSEL_LINUX_KVER"/boot/vexpress-v2p-ca9.dtb ./penguinize_fdtree.dtb
    cp_ ./initrd.img                                                                       ./penguinize_initrd.img
    
    function f()
    {
      local PENGUINIZE_PREFIX PENGUINIZE_MURMUR PENGUINIZE_BA_MEM PENGUINIZE_SZ_LIMIT
      PENGUINIZE_PREFIX=penguinize
      srcsel_tool_host murmur
      PENGUINIZE_MURMUR="$SRCSEL_TOOL"/murmur
      unset SRCSEL_TOOL
      PENGUINIZE_BA_MEM=$(( 0x60000000 ))
      PENGUINIZE_SZ_LIMIT=$(( 0x10000000 ))
      penguinize_generic_fdtree_fiddle() {
        FDTREE_FIDDLE_VEYSP_BOOTARGS="console=ttyAMA0" FDTREE_FIDDLE_VEYSP_ARM_PENGUIN_LOADER=n fdtree_fiddle_veysp
      }
      penguinize_generic
    }; f
    
    cat ./penguinize_penguin_{A,B,C,D} >./penguin_emulation.bin
  fi
}

function main_fel_arm()
{
  srcsel
  # some fixes for deterministic build:
  # - prevent stage3 date inclusion
  STAGEZ_INCLUDE_CURRENT_DATE=n
  # - prevent rid appends
  STAGE3A_ARID=n
  STAGE3_ARID=n
  stage3
  stageF
  
  cp_ /builds/arm-u-boot-final-ca7/"$U_BOOT_BOARD_NAME"/u-boot-sunxi-with-spl.bin ./fel-u-boot
  
  ln -vsfT ./stage3_content/stage3_kernel.zim.noz ./fel-kernel
  ln -vsfT ./stage3_content/stage3_fdtree.dtb     ./fel-fdtree
  
  mkimage -A arm -O linux -T ramdisk -C none -n "Linux initramfs" -d ./initrd.img ./fel-initrd
  
  #setenv bootargs "console=ttyS0,115200"
  u_boot_script fel-script <<'EOF'
setenv bootargs "console=tty1"
bootz ${kernel_addr_r} ${ramdisk_addr_r} ${fdt_addr_r}
EOF
  
  ln -vsfT ./fel-script{.scr,}
}

main_"$1"_"$ARCH"
