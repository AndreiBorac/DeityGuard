#!/bin/false

set -o xtrace
set -o errexit
set -o nounset
set -o pipefail
shopt -s failglob || true
shopt -s nullglob || true

function shell_adjust()
{
  [ -z "${SHELL_RESUME_TO+x}" ] # nesting not supported
  set +o xtrace
  SHELL_RESUME_TO="$(set +o ; shopt -p)"
  "$@"
  set -o xtrace
}

function shell_resume()
{
  set +o xtrace
  eval "$SHELL_RESUME_TO"
  set -o xtrace
  unset SHELL_RESUME_TO
  set -o errexit
}

function dirty_glob()
{
  shell_adjust shopt -u failglob nullglob
  local X
  X=$(eval "echo $1")
  echo "${X[@]}"
  shell_resume
}

. ./classical-lander-variables

if [ "$CLASSICAL_LANDER_EXPORT_LD_LIBRARY_PATH" == "y" ]
then
  export LD_LIBRARY_PATH
fi

if [ "$CLASSICAL_LANDER_EMMC_LOCKED_WORKAROUND" == "y" ]
then
  touch /tmp/flag_cl_emmc_lw
  cp /builds_tools/gptize /tmp/
fi

REGEXP_GUID='[0-9A-Z]{8}-[0-9A-Z]{4}-[0-9A-Z]{4}-[0-9A-Z]{4}-[0-9A-Z]{12}'

NAME_CACHE_PARTITION="classical-lander-v1"
TYPECODE_CACHE_PARTITION=AE8F2F3E-2A46-413D-B55A-D6CECCEE28DA

function mkdir_p_cd()
{
  mkdir -p "$1"
  cd "$1"
}

function openvt_()
{
  if [ "${SCREEN-}" == "y" ]
  then
    TERM=screen "$@"
  else
    cat /proc/sys/kernel/printk | tee /tmp/saved_printk
    echo 0 | tee /proc/sys/kernel/printk
    local OPENVT_RETV
    OPENVT_RETV=0
    TERM=linux openvt -s -w -- "$@" || OPENVT_RETV="$?"
    echo "OPENVT_RETV='$OPENVT_RETV'"
    cat /tmp/saved_printk | tee /proc/sys/kernel/printk
  fi
}

DIALOG_TITLE="Classical Lander"
DIALOG_BACKTITLE="$DIALOG_TITLE"

function dialog_()
{
  dialog --nocancel --aspect 15 --backtitle 'Test Dialog' --title 'Test Dialog' "$@"
}

function dialog_()
{
  cat >/tmp/dialog_wrapper <<'EOF'
rm -f /tmp/dialog{,_status} || true
dialog "$@" 2>/tmp/dialog
#cat /tmp/dialog
echo "$?" >/tmp/dialog_status
exit 0
EOF
  openvt_ bash /tmp/dialog_wrapper --nocancel --aspect 15 --backtitle "$DIALOG_BACKTITLE" --title "$DIALOG_TITLE" "$@"
  DIALOG_STATUS="$(cat /tmp/dialog_status)"
  [ "$DIALOG_STATUS" == "0" ]
  DIALOG_OUTPUT="$(cat /tmp/dialog)"
}

function dialog_msgbox()
{
  dialog_ --msgbox "$1" 0 0
}

function dialog_menu()
{
  local LABEL
  LABEL="$1"
  shift
  local N
  N="$#"
  dialog_ --menu "$LABEL" 0 0 "$(( (N/2) ))" "$@"
}

function dialog_menu_yes_no()
{
  dialog_menu "$1" "n" "No" "y" "Yes"
}

function dialog_menu_yes_no_yes()
{
  dialog_menu "$1" "y" "Yes" "n" "No"
}

function dialog_inputbox()
{
  dialog_ --inputbox "$1" 0 0
}

function dialog_inputbox_with_default()
{
  dialog_ --inputbox "$2" 0 0 "$1"
}

function dirty_glob_all_drives()
{
  dirty_glob "/dev/{hd,sr,sd,vd,mmcblk}?"
}

function set_all_drives()
{
  ALL_DRIVES=()
  HAVE_DRIVES=n
  local ALL_DRIVES_GLOBTURE
  ALL_DRIVES_GLOBTURE="$(dirty_glob_all_drives)"
  shell_adjust set -o noglob
  local i
  for i in $ALL_DRIVES_GLOBTURE
  do
    if [ -b "$i" ]
    then
      ALL_DRIVES+=("$i")
      HAVE_DRIVES=y
    fi
  done
  local X
  if X="$(cat /tmp/mmc_window_loop_device)"
  then
    ALL_DRIVES+=("$X")
    HAVE_DRIVES=y
  fi
  shell_resume
}

function dump_pad_to()
{
  local ALIGN
  ALIGN="$1"
  local PAD_FILE
  PAD_FILE="$(mktemp)"
  cat >"$PAD_FILE"
  local SIZE
  SIZE="$(stat -c %s "$PAD_FILE")"
  SIZE="$(( (((SIZE+(ALIGN-1))/ALIGN)*ALIGN) ))"
  truncate -s "$SIZE" "$PAD_FILE"
  cat "$PAD_FILE"
  rm "$PAD_FILE"
}

function get_drive_size()
{
  local DUT
  DUT="$1"
  
  if [ -f "$DUT" ]
  then
    stat -c %s "$(readlink -f "$DUT")"
  else
    blockdev --getsize64 "$DUT"
  fi
}

function gpt_model_rm()
{
  rm -f /tmp/model
}

function gpt_model_transplant_src_dst()
{
  local SRC
  SRC="$1"
  local DST
  DST="$2"
  
  local SZ_SRC
  SZ_SRC="$(get_drive_size "$SRC")"
  local SZ_DST
  SZ_DST="$(get_drive_size "$DST")"
  [ "$SZ_SRC" == "$SZ_DST" ]
  
  local SIZE_MODEL_HEAD
  SIZE_MODEL_HEAD="$(( (34*512) ))"
  dd_ if="$SRC" of="$DST" count="$SIZE_MODEL_HEAD"
  
  local SIZE_MODEL_TAIL
  SIZE_MODEL_TAIL="$(( (33*512) ))"
  dd_ if="$SRC" of="$DST" skip="$(( (SZ_SRC-SIZE_MODEL_TAIL) ))" seek="$(( (SZ_DST-SIZE_MODEL_TAIL) ))" count="$SIZE_MODEL_TAIL"
}

function gpt_model_rd()
{
  local DUT
  DUT="$1"
  [ -b "$DUT" ]
  gpt_model_rm
  
  local SIZE
  SIZE="$(blockdev --getsize64 "$DUT")"
  truncate -s "$SIZE" /tmp/model
  
  gpt_model_transplant_src_dst "$DUT" /tmp/model
  
  if [ "$DUT" == "/dev/mmcblk0" ] && [ "$CLASSICAL_LANDER_EMMC_LOCKED_WORKAROUND" == "y" ]
  then
    local SIZE_MODEL_HEAD
    SIZE_MODEL_HEAD="$(( (34*512) ))"
    local SIZE_MODEL_TAIL
    SIZE_MODEL_TAIL="$(( (33*512) ))"
    rm -f /tmp/model_paa
    dd_ if=/tmp/model of=/tmp/model_paa skip="$(( (SIZE-SIZE_MODEL_TAIL) ))" count="$(( (SIZE_MODEL_TAIL-512) ))"
    [ "$(stat -c %s /tmp/model_paa)" == $(( (32*512) )) ]
    rm -f /tmp/model_gpt
    dd_ if=/tmp/model of=/tmp/model_gpt skip="$(( (SIZE-512) ))" count=512
    [ "$(stat -c %s /tmp/model_gpt)" == 512 ]
    cat /tmp/model_{gpt,paa} >/tmp/model_bou
    # gptize need not always succeed, of course. the secondary GPT may
    # be corrupt or the disk may simply not be GPT at all.
    if /builds_tools/gptize "$SIZE" </tmp/model_bou >/tmp/model_bup
    then
      local SZ_BUP
      SZ_BUP="$(stat -c %s /tmp/model_bup)"
      [ "$SZ_BUP" == "$SIZE_MODEL_HEAD" ]
      dd_ if=/tmp/model_bup of=/tmp/model
    fi
  fi
}

function gpt_model_wb()
{
  local DUT
  DUT="$1"
  [ -b "$DUT" ]
  
  gpt_model_transplant_src_dst /tmp/model "$DUT"
}

function gpt_test()
{
  local DUT
  DUT="$1"
  
  GPT_TEST=n
  GPT_TEST_GUID="not GPT"
  
  gpt_model_rd "$DUT"
  
  # sgdisk is total crap. there's no easy way to tell if a partition
  # even has gpt on it with this thing!
  
  if     sgdisk --print /tmp/model >/tmp/model.inf
  then
    local     X
    if        X="$(egrep '^Disk identifier \(GUID\): ' /tmp/model.inf | egrep -o "$REGEXP_GUID"'$' | head -n 1)" && [ -n "$X" ]
    then
      if sgdisk --print /tmp/model >/tmp/model.inf
      then
        local Y
        if    Y="$(egrep '^Disk identifier \(GUID\): ' /tmp/model.inf | egrep -o "$REGEXP_GUID"'$' | head -n 1)" && [ -n "$Y" ]
        then
          if [ "$X" == "$Y" ]
          then
            GPT_TEST_GUID="$X"
            GPT_TEST=y
          fi
        fi
      fi
    fi
  fi
  
  gpt_model_rm
}

function drivesel()
{
  local WRITABLE
  WRITABLE="n"
  
  while [ "$#" -gt 0 ]
  do
    case "$1" in
      -w) WRITABLE=y ;;
      *) exit 1 ;;
    esac
    
    shift
  done
  
  local DRIVES
  DRIVES=()
  
  DRIVES+=("(cancel)")
  DRIVES+=("(cancel)")
  
  set_all_drives
  if [ "$HAVE_DRIVES" == "y" ]
  then
    local i
    for i in "${ALL_DRIVES[@]}"
    do
      if [ ! -b "$i" ]
      then
        continue
      fi
      
      local BN_I
      BN_I="$(basename "$i")"
      
      echo "before blockdev"
      
      local BLOCKDEV_GETRO
      if ! BLOCKDEV_GETRO="$(blockdev --getro "$i")"
      then
        echo "after blockdev (continue)"
        continue
      fi
      
      echo "after blockdev (success)"
      
      if [ "$WRITABLE" == "y" ] && [ "$BLOCKDEV_GETRO" == "1" ]
      then
        continue
      fi
      
      local ID_SERIAL
      ID_SERIAL="unknown"
      
      if [ "$ID_SERIAL" == "unknown" ]
      then
        local X
        if X="$(udevadm test-builtin usb_id /block/"$BN_I" | egrep '^ID_SERIAL\=')"
        then
          ID_SERIAL="USB"-"${X:10}"
        fi
      fi
      
      if [ "$ID_SERIAL" == "unknown" ]
      then
        local SCSI_ID
        function f_x64() { SCSI_ID=/lib64/udev/scsi_id ;}
        function f_arm() { SCSI_ID=/usr/lib/udev/scsi_id ;}
        f_"$ARCH"
        unset f_x64
        unset f_arm
        local X
        if X="$("$SCSI_ID" --whitelisted --export "$i" | egrep '^ID_SERIAL\=')"
        then
          ID_SERIAL="SCSI"-"${X:10}"
        fi
      fi
      
      if [ "$ID_SERIAL" == "unknown" ]
      then
        function id_serial_last_resort()
        {
          local BN
          BN="$(basename "$1")"
          local X1
          if X1="$(cat     /sys/class/block/"$BN"/device/type   | /builds_tools/safepipe 09AZaz "_")"
          then
            local X2
            if X2="$(cat   /sys/class/block/"$BN"/device/name   | /builds_tools/safepipe 09AZaz "_")"
            then
              local X3
              if X3="$(cat /sys/class/block/"$BN"/device/serial | /builds_tools/safepipe 09AZaz "_")"
              then
                echo "UNK"-"$X1"-"$X2"-"$X3"
                return
              fi
            fi
          fi
          false
        }
        local X
        if X="$(id_serial_last_resort "$i")"
        then
          ID_SERIAL="$X"
        fi
      fi
      
      gpt_test "$i"
      
      DRIVES+=("$i")
      DRIVES+=("$ID_SERIAL (GPT: $GPT_TEST_GUID)")
    done
  fi
  
  dialog_menu "Choose a drive:" "${DRIVES[@]}"
  DRIVE="$(cat /tmp/dialog)"
}

function drivesel_w_or_icpv()
{
  if [ "$ICPV" != "" ]
  then
    DRIVE="$ICPV"
  else
    drivesel -w
  fi
}

function do_newg()
{
  drivesel_w_or_icpv
  
  if [ "$DRIVE" == "(cancel)" ]
  then
    return
  fi
  
  dialog_menu_yes_no "Really clear all partitioning information on '${DRIVE}' and create a new blank GPT?"
  if [ "$DIALOG_OUTPUT" != "y" ]
  then
    dialog_msgbox "You didn't say yes. Giving up for now."
    return
  fi
  
  gpt_model_rd "$DRIVE"
  if ! ( sgdisk --zap-all /tmp/model && sgdisk --disk-guid=R /tmp/model )
  then
    dialog_msgbox "Drats, sgdisk failed. Your disk has not been modified. Giving up for now."
    return
  fi
  gpt_model_wb "$DRIVE"
  dialog_msgbox "It is done."
  
  dialog_menu_yes_no "Do you also want to create a cache partition on this drive?"
  if [ "$DIALOG_OUTPUT" == "y" ]
  then
    ICPV="$DRIVE"
    do_part
  fi
}

function do_mbrg()
{
  drivesel_w_or_icpv
  
  if [ "$DRIVE" == "(cancel)" ]
  then
    return
  fi
  
  dialog_menu_yes_no "Really subject '${DRIVE}' to sgdisk's default MBR-to-GPT conversion?"
  if [ "$DIALOG_OUTPUT" != "y" ]
  then
    dialog_msgbox "You didn't say yes. Giving up for now."
    return
  fi
  
  gpt_model_rd "$DRIVE"
  if ! ( sgdisk --mbrtogpt /tmp/model && sgdisk --disk-guid=R /tmp/model )
  then
    dialog_msgbox "Drats, sgdisk failed. Your disk has not been modified. Giving up for now."
    return
  fi
  gpt_model_wb "$DRIVE"
  dialog_msgbox "It is done."
  
  dialog_menu_yes_no "Do you also want to create a cache partition on this drive?"
  if [ "$DIALOG_OUTPUT" == "y" ]
  then
    ICPV="$DRIVE"
    do_part
  fi
}

function find_cache_partition()
{
  CACHE_PARTITION_FOUND=n
  
  gpt_model_rd "$DRIVE"
  
  local CACHE_PARTITION_INDEX_MAX
  CACHE_PARTITION_INDEX_MAX="$(sgdisk --print /tmp/model | ( egrep '^ ' || true ) | wc -l)"
  
  for CACHE_PARTITION_INDEX in $(seq 1 "$CACHE_PARTITION_INDEX_MAX")
  do
    local X
    if X="$(sgdisk --info "$CACHE_PARTITION_INDEX" /tmp/model | egrep '^Partition GUID code: ' | egrep -o "$TYPECODE_CACHE_PARTITION")"
    then
      CACHE_PARTITION_FOUND=y
      break
    fi
  done
  
  if [ "$CACHE_PARTITION_FOUND" != "y" ]
  then
    gpt_model_rm
    return
  fi
  
  CACHE_PARTITION_GUID="$(sgdisk --info "$CACHE_PARTITION_INDEX" /tmp/model | egrep '^Partition unique GUID: ' | cut -d " " -f 4)"
  CACHE_PARTITION_BASE="$(sgdisk --info "$CACHE_PARTITION_INDEX" /tmp/model | egrep '^First sector: ' | cut -d " " -f 3)"
  CACHE_PARTITION_SIZE="$(sgdisk --info "$CACHE_PARTITION_INDEX" /tmp/model | egrep '^Last sector: '  | cut -d " " -f 3)"
  
  echo "$CACHE_PARTITION_GUID" | egrep -o "$REGEXP_GUID"
  
  CACHE_PARTITION_SIZE="$(( ((CACHE_PARTITION_SIZE-CACHE_PARTITION_BASE+1)*512) ))"
  CACHE_PARTITION_BASE="$(( (CACHE_PARTITION_BASE*512) ))"
  
  gpt_model_rm
  
  partx --update --nr "$CACHE_PARTITION_INDEX" "$DRIVE"
  
  if [[ "${DRIVE: -1}" =~ ^[0-9]$ ]]
  then
    CACHE_PARTITION_BDEV="$DRIVE"p"$CACHE_PARTITION_INDEX"
  else
    CACHE_PARTITION_BDEV="$DRIVE""$CACHE_PARTITION_INDEX"
  fi
  
  [ -b "$CACHE_PARTITION_BDEV" ]
  
  local BN_CACHE_PARTITION_BDEV
  BN_CACHE_PARTITION_BDEV="$(basename "$CACHE_PARTITION_BDEV")"
  
  local SYSFS_CACHE_PARTITION_BASE
  SYSFS_CACHE_PARTITION_BASE="$(cat /sys/class/block/"$BN_CACHE_PARTITION_BDEV"/start)"
  [ "$SYSFS_CACHE_PARTITION_BASE" == "$(( (CACHE_PARTITION_BASE/512) ))" ]
  
  local SYSFS_CACHE_PARTITION_SIZE
  SYSFS_CACHE_PARTITION_SIZE="$(cat /sys/class/block/"$BN_CACHE_PARTITION_BDEV"/size)"
  [ "$SYSFS_CACHE_PARTITION_SIZE" == "$(( (CACHE_PARTITION_SIZE/512) ))" ]
}

function display_size()
{
  echo "$1" | sed -e 's/$/,/' | sed -e ':a; s/\([^,]\)\([^,]\{3\}\),/\1,\2,/; ta' | sed -e 's/,$//'
}

function do_part()
{
  drivesel_w_or_icpv
  
  if [ "$DRIVE" == "(cancel)" ]
  then
    return
  fi
  
  dialog_menu_yes_no "Really add a cache partition to '${DRIVE}'?"
  if [ "$DIALOG_OUTPUT" != "y" ]
  then
    dialog_msgbox "You didn't say yes. Giving up for now."
    return
  fi
  
  gpt_test "$DRIVE"
  if [ "$GPT_TEST" != "y" ]
  then
    dialog_msgbox "That drive doesn't have a valid GPT on it. Giving up for now."
    return
  fi
  
  gpt_model_rd "$DRIVE"
  
  local FIRST
  FIRST="$(sgdisk --first-aligned-in-largest /tmp/model)"
  
  if ! [[ "$FIRST" =~ ^[0-9]+$ ]]
  then
    dialog_msgbox "Expected a non-negative integer. Giving up for now."
    gpt_model_rm
    return
  fi
  
  local MLAST
  MLAST="$(sgdisk --end-of-largest /tmp/model)"
  
  if ! [[ "$MLAST" =~ ^[0-9]+$ ]]
  then
    dialog_msgbox "Expected a non-negative integer. Giving up for now."
    gpt_model_rm
    return
  fi
  
  if [ "$MLAST" == "0" ] || [ "$FIRST" -ge "$MLAST" ]
  then
    dialog_msgbox "That drive has no space left! Giving up for now."
    gpt_model_rm
    return
  fi
  
  local DISPLAY_SIZE
  DISPLAY_SIZE="$(display_size "$(( ((MLAST-FIRST+1)*512) ))")"
  
  dialog_inputbox "Please enter the size of the cache partition (in GiB). This should be at least the size of the filesystem image plus $(display_size "$CLASSICAL_LANDER_RESERVED_AREA_SIZE") bytes. Actual available space is $(display_size "$(( ((MLAST-FIRST+1)*512) ))") bytes."
  
  local VALUE
  VALUE="$DIALOG_OUTPUT"
  
  if ! [[ "$VALUE" =~ ^[0-9]+$ ]]
  then
    dialog_msgbox "Expected a non-negative integer. Giving up for now."
    gpt_model_rm
    return
  fi
  
  VALUE="$(( ((VALUE+1)-1) ))"
  
  if [ "$VALUE" -lt 1 ]
  then
    dialog_msgbox "Expected a positive integer. Giving up for now."
    gpt_model_rm
    return
  fi
  
  if [ "$VALUE" -gt 120000 ]
  then
    dialog_msgbox "Expected a reasonable value. Giving up for now."
    gpt_model_rm
    return
  fi
  
  if ! sgdisk --new=0:0:+"$VALUE"G --typecode=0:"$TYPECODE_CACHE_PARTITION" --change-name=0:"$NAME_CACHE_PARTITION" /tmp/model
  then
    dialog_msgbox "Drats, sgdisk failed! Giving up for now."
    gpt_model_rm
    return
  fi
  
  gpt_model_wb "$DRIVE"
  
  dialog_msgbox "It is one."
  
  dialog_menu_yes_no "Do you also want to boot the OS with this drive?"
  if [ "$DIALOG_OUTPUT" == "y" ]
  then
    ICPV="$DRIVE"
    do_cbot
  fi
}

function dotquad2numeric()
{
  echo "$1" | ( IFS=. read A B C D ; echo "$(( ((((((A<<8)|B)<<8)|C)<<8)|D) ))" )
}

function root_from_ror()
{
  mkdir /cow
  mount -t tmpfs none /cow
  mount -t tmpfs -o remount,size=1t,nr_inodes=1g none /cow
  mkdir -p /cow/{upperdir,workdir}
  mkdir -p /root
  mount -t overlay -o lowerdir=/ror,upperdir=/cow/upperdir,workdir=/cow/workdir none /root
  mkdir -p /root/.live/{ror,cow}
  mount --move /ror /root/.live/ror
  mount --move /cow /root/.live/cow
}

function boot_with_ror_device()
{
  local DEV_ROR
  DEV_ROR="$1"
  
  mkdir /ror
  mount -t squashfs "$DEV_ROR" /ror
  root_from_ror
  
  mkdir -p                                ./root/lib/modules/"$(uname -r)"
  mount --move /lib/modules/"$(uname -r)" ./root/lib/modules/"$(uname -r)"
  
  local    PID_SS
  if       PID_SS="$(cat /tmp/pid_serial_shell)"
  then
    kill "$PID_SS"
  fi
  
  cat >/bootcont <<'EOF'
# this is kind of kludgy, it will complain about not being able to
# move /tmp/dg but that is fine
mkdir -p  /tmp/dg/initramfs
mv /tmp/* /tmp/dg/initramfs/ || true

# move the classical mount over, if there is one. in preinit it will
# be cleaned up when we have a proper fully-featured rm command
if mountpoint -q /classical
then
  mkdir                   /tmp/dg/initramfs/classical
  mount --move /classical /tmp/dg/initramfs/classical
fi

mount --move /dev /root/dev
mount --move /tmp /root/tmp

# unpack overlay with umask 0002
(
  umask 0002
  tar -C /root/ -xf /overlay.tar
)

# the above command may have upset the sticky bit on /root/tmp, so fix that
chmod 1777 /root/tmp
# with tar, it also puts a sticky bit on /, since the tarball is created from a tmpfs, so fix that too
chmod 0755 /root

# lazy unmount /sys because fanman may be keeping an open reference
umount -l /sys
umount -n /proc

# give assurance to switch_root that this is an initramfs
rm -f /init
touch /init

# tell preinit that we are using nbd-hyperbolic
touch ./root/tmp/dg/vars/using-nbd-hyperbolic

# pass control to the preinit script
exec switch_root /root /bin/bash /tmp/dg/preinit.sh "$@"

fail
EOF
  
  exit
}

function boot_with_backing_and_offset()
{
  local NH_CACHE_BACKING_FILE
  NH_CACHE_BACKING_FILE="$1"
  
  local NH_CACHE_BACKING_OFFSET
  NH_CACHE_BACKING_OFFSET="$2"
  
  # record the cache partition if there is an actual cache partition being used
  rm -f /tmp/classical-lander-cache-partition-guid
  if [ "$3" == "actual" ]
  then
    echo "$CACHE_PARTITION_GUID" >/tmp/classical-lander-cache-partition-guid
  fi
  
  local CACHE_BACKING_SIZE
  CACHE_BACKING_SIZE="$(get_drive_size "$NH_CACHE_BACKING_FILE")"
  
  if ((CACHE_BACKING_SIZE<(NH_CACHE_BACKING_OFFSET+NH_IMAGE_SIZE)))
  then
    dmsetup remove classical-lander-cache-dummy || true
    dmsetup remove classical-lander-cache-partition || true
    dmsetup mknodes
    dialog_msgbox "Your cache partition is too small to accommodate the filesystem image. Giving up for now."
    return
  fi
  
  # we may or may not have brought up the network already in other stages
  eth_bring_up_if_down "$CLASSICAL_LANDER_ETHERNET_INTERFACE"
  
  if [ "${CLASSICAL_LANDER_DNS_HOST:0:4}" == "DNS:" ]
  then
    CLASSICAL_LANDER_DNS_HOST="${CLASSICAL_LANDER_DNS_HOST:4}"
    CLASSICAL_LANDER_DNS_HOST_RESOLVED="$(dnsip_ "$CLASSICAL_LANDER_DNS_HOST" | cut -d " " -f 1)"
  else
    CLASSICAL_LANDER_DNS_HOST_RESOLVED="$CLASSICAL_LANDER_DNS_HOST"
  fi
  
  if false # if true, use the QEMU host as the backend
  then
    NH_BACKEND_HTTP_HOST="$(( ((10<<24)+(2<<8)+2) ))"
  else
    NH_BACKEND_HTTP_HOST="$(dotquad2numeric "$CLASSICAL_LANDER_DNS_HOST_RESOLVED")"
  fi
  
  GID_NBD_HYPERBOLIC="$(tar -xOf /overlay.tar ./tmp/dg/vars/gid-nbd-hyperbolic)"
  [[ "$GID_NBD_HYPERBOLIC" =~ ^[0-9]+$ ]]
  (( "$GID_NBD_HYPERBOLIC" > 0 ))
  
  modprobe unix
  NH_PREPARE_ONLY=n \
  NH_IMAGE_SIZE="$NH_IMAGE_SIZE" \
  NH_CACHE_ENABLE=y \
  NH_CACHE_USER_A="$NH_CACHE_USER_A" \
  NH_CACHE_USER_B="$NH_CACHE_USER_B" \
  NH_CACHE_USER_C="$NH_CACHE_USER_C" \
  NH_CACHE_USER_D="$NH_CACHE_USER_D" \
  NH_CACHE_BLOCK_SIZE_LOG="$NH_CACHE_BLOCK_SIZE_LOG" \
  NH_CACHE_CHECKSUM_FILE=./rootfs.hyp \
  NH_CACHE_BACKING_FILE="$NH_CACHE_BACKING_FILE" \
  NH_CACHE_BACKING_OFFSET="$NH_CACHE_BACKING_OFFSET" \
  NH_FRONTEND_UNIX_ENABLE=y \
  NH_FRONTEND_UNIX_SOCKET=/tmp/nbd-hyperbolic-socket \
  NH_FRONTEND_TCP_ENABLE=n \
  NH_BACKEND_HTTP_TOKEN_REFUND=y \
  NH_BACKEND_HTTP_PARALLELISM="$CLASSICAL_LANDER_HTTP_PARALLELISM" \
  NH_BACKEND_HTTP_PORT="$CLASSICAL_LANDER_HTTP_PORT" \
  NH_BACKEND_HTTP_HOST="$NH_BACKEND_HTTP_HOST" \
  NH_BACKEND_HTTP_HOSTNAME="$CLASSICAL_LANDER_HTTP_HOST" \
  NH_BACKEND_HTTP_URL="$CLASSICAL_LANDER_HTTP_PATH_DATA" \
  bash -c 'env >/tmp/env-nbd-hyperbolic ; exec /builds_tools/linuxtools setgid '"$GID_NBD_HYPERBOLIC"' /builds_tools/nbd-hyperbolic{,} </dev/null &>/tmp/stdamp-nbd-hyperbolic' & disown
  
  local i
  for i in $(seq 1 50)
  do
    if [ -S /tmp/nbd-hyperbolic-socket ]
    then
      break
    fi
    
    sleep 0.1
  done
  
  if [ ! -S /tmp/nbd-hyperbolic-socket ]
  then
    set +o xtrace
    echo "!! drats, nbd-hyperbolic didn't start properly"
    exit 1
  fi
  
  modprobe nbd
  nbd-client -unix /tmp/nbd-hyperbolic-socket /dev/nbd0
  ln -vsfT /dev/nbd0 /tmp/classical-lander-nbd-hyperbolic-ror-device
  
  boot_with_ror_device /tmp/classical-lander-nbd-hyperbolic-ror-device
}

function do_cbot()
{
  drivesel_w_or_icpv
  
  if [ "$DRIVE" == "(cancel)" ]
  then
    return
  fi
  
  gpt_test "$DRIVE"
  if [ "$GPT_TEST" != "y" ]
  then
    dialog_msgbox "That drive doesn't have a valid GPT on it. Giving up for now."
    return
  fi
  
  find_cache_partition "$DRIVE"
  if [ "$CACHE_PARTITION_FOUND" != "y" ]
  then
    dialog_msgbox "That drive doesn't have a cache partition. Giving up for now."
    return
  fi
  
  ln -vsfT "$DRIVE"                            /tmp/classical-lander-cache-partition-drive
  echo "$CACHE_PARTITION_INDEX"               >/tmp/classical-lander-cache-partition-index
  ln -vsfT "$CACHE_PARTITION_BDEV"             /tmp/classical-lander-cache-partition
  echo "$CLASSICAL_LANDER_RESERVED_AREA_SIZE" >/tmp/classical-lander-cache-partition-rsrvz
  
  # ok, now we need to save off stage1/stage2 data
  (
    dd_no_sync if=/dev/zero count="$COMMON_CACHE_PARTITION_CLEAR_ZONE"
    
    cat ./sg_pl_ini
    
    STUFF="$(echo manifest.{lst,sig,pub}.txt stage2.bin)"
    
    (
      for i in $STUFF
      do
        echo "$(stat -c %s ./classical/"$i")"
      done
    ) | dump_pad_to 4096
    
    (
      for i in $STUFF
      do
        cat ./classical/"$i"
      done
    )
  ) | dump_pad_to "$CLASSICAL_LANDER_RESERVED_AREA_ALIGN" >/tmp/save_off
  
  local SZ_SAVE_OFF
  SZ_SAVE_OFF="$(stat -c %s /tmp/save_off)"
  
  if ((SZ_SAVE_OFF>CLASSICAL_LANDER_RESERVED_AREA_SIZE))
  then
    dialog_msgbox "The size of the stage data exceeds the reserved area of the cache partition. The stage data cannot be saved to the cache partition, and consequently offline booting will not work. To fix this, you must increase CLASSICAL_LANDER_RESERVED_AREA_SIZE. Continuing anyways."
  else
    local PREV CURR
    PREV="$(dd_no_sync if=/tmp/classical-lander-cache-partition count="$SZ_SAVE_OFF" | sha256sum - | cut -d " " -f 1)"
    CURR="$(sha256sum /tmp/save_off | cut -d " " -f 1)"
    
    if [ "$CURR" != "$PREV" ]
    then
      dialog_menu_yes_no "The cache partition contents are not consistent with the stage data. Update the cache partition?"
      if [ "$DIALOG_OUTPUT" == "y" ]
      then
        dd_ if=/tmp/save_off of=/tmp/classical-lander-cache-partition
      fi
    fi
  fi
  
  # delete the save_off file as it uselessly takes up a lot of RAM at this point
  rm /tmp/save_off
  
  boot_with_backing_and_offset /tmp/classical-lander-cache-partition "$CLASSICAL_LANDER_RESERVED_AREA_SIZE" actual
}

function do_fbot()
{
  truncate -s "$NH_IMAGE_SIZE" /tmp/floating
  
  ln -vsfT /tmp/floating /tmp/classical-lander-cache-partition
  
  boot_with_backing_and_offset /tmp/classical-lander-cache-partition 0 floating
}

function do_rbot()
{
  drivesel
  
  if [ "$DRIVE" == "(cancel)" ]
  then
    return
  fi
  
  local BLKZ
  BLKZ="$(blockdev --getbsz "$DRIVE")"
  dmsetup create classical-lander-cache-dummy --table "0 $(( (BLKZ/512) )) zero"
  dmsetup mknodes
  local DEV_DUMMY
  DEV_DUMMY=/dev/mapper/classical-lander-cache-dummy
  
  local SZ
  SZ="$(blockdev --getsize64 "$DRIVE")"
  dmsetup create classical-lander-cache-partition --table "0 $(( (SZ/512) )) snapshot ${DRIVE} ${DEV_DUMMY} N $(( (BLKZ/512) ))"
  dmsetup mknodes
  
  ln -vsfT /dev/mapper/classical-lander-cache-partition /tmp/classical-lander-cache-partition
  
  boot_with_backing_and_offset /tmp/classical-lander-cache-partition "$(( (COMMON_CACHE_PARTITION_OFFSET+CLASSICAL_LANDER_RESERVED_AREA_SIZE) ))" floating
}

function do_shel()
{
  if [ ! -f    /tmp/pid_serial_shell ]
  then
    bash -i </dev/ttyS0 &>/dev/ttyS0 & disown
    echo "$!" >/tmp/pid_serial_shell
  fi
}

function do_agin()
{
  echo b >/proc/sysrq-trigger
  reboot -f
  false
}

function do_srst()
{
  ./stage3.bin
  
  if [ "$MODEL" == "veysp" ]
  then
    kexec_veysp
  else
    kexec_"$ARCH"
  fi
  
  false
}

function do_util()
{
  local MENU
  MENU=()
  function add_to_menu_if_any() { MENU+=("$@") ;}
  add_to_menu_if_any "rtrn" "Return to main menu"
  add_to_menu_if_any "agin" "Reboot (via sysrq)"
  if [ "$CLASSICAL_LANDER_EMMC_PROBE_WORKAROUND" == "y" ]
  then
    add_to_menu_if_any "srst" "Pretend emmc probe failed (kexec self)"
  fi
  add_to_menu_if_any "shel" "Open shell on serial console"
  
  dialog_menu \
    "Choose an action:" \
    "${MENU[@]}"
  
  unset MENU
  unset add_to_menu_if_any
  
  case "$DIALOG_OUTPUT" in
    "rtrn")         ;;
    "agin") do_agin ;;
    "srst") do_srst ;;
    "shel") do_shel ;;
    *)      exit 1  ;;
  esac
}

function emmc_probe_workaround()
{
  emmc_probe_status
  
  if [ "$EMMC_PROBE_GOOD" != "y" ]
  then
    do_srst
  fi
}

function fixes()
{
  if [ "$CLASSICAL_LANDER_EMMC_PROBE_WORKAROUND" == "y" ]
  then
    emmc_probe_workaround
  fi
}

function main()
{
  fixes
  
  while [ 1 ]
  do
    # clear inter-command-passing-variable
    ICPV=""
    
    local MENU
    MENU=()
    function add_to_menu_if_any() { MENU+=("$@") ;}
    function add_to_menu_if_x64() { if [ "$ARCH" == "x64" ]; then add_to_menu_if_any "$@"; fi ;}
    function add_to_menu_if_arm() { if [ "$ARCH" == "arm" ]; then add_to_menu_if_any "$@"; fi ;}
    add_to_menu_if_any "cbot" "Boot OS with cache partition"
    add_to_menu_if_any "fbot" "Boot OS in floating mode (hard RAM cache)"
    add_to_menu_if_any "rbot" "Boot OS from read-only media"
    add_to_menu_if_any "newg" "Partition a drive with GPT (clear everything)"
    add_to_menu_if_any "mbrg" "Partition a drive with GPT (convert from MBR)"
    add_to_menu_if_any "part" "Create a cache partition on a drive with GPT"
    add_to_menu_if_any "util" "Miscellaneous utilities ..."
    add_to_menu_if_any "quit" "Quit to shell"
    
    dialog_menu \
        "Choose an action:" \
        "${MENU[@]}"
    
    unset MENU
    unset add_to_menu_if_any
    unset add_to_menu_if_x64
    unset add_to_menu_if_arm
    
    case "$DIALOG_OUTPUT" in
      "cbot") do_cbot ;;
      "fbot") do_fbot ;;
      "rbot") do_rbot ;;
      "newg") do_newg ;;
      "mbrg") do_mbrg ;;
      "part") do_part ;;
      "util") do_util ;;
      "quit") exit 0  ;;
      *)      exit 1  ;;
    esac
  done
}

if false # for testing in qemu
then
  ICPV="/dev/vda"
  do_cbot
  exec bash -i
fi

# allow setting LOADONLY=y and then source-ing the script to test
# individual functions by not doing anything when LOADONLY=y
if [ "${LOADONLY-}" != "y" ]
then
  # if the bypass is enabled, jump right in to a floating boot
  if [ "$CLASSICAL_LANDER_BYPASS" == "y" ]
  then
    do_fbot
  fi
  
  # also, if we have a trusted ./rootfs.sqs from stageF, boot it
  # without further ado
  if [ -e ./rootfs.sqs ]
  then
    boot_with_ror_device ./rootfs.sqs
  fi
  
  main
  exit 1
fi
