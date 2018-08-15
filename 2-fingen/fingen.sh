#!/usr/bin/env bash

set -o xtrace
set -o errexit
set -o nounset
set -o pipefail
shopt -s failglob
shopt -s nullglob

ARG1="$1"
shift

if [ "$ARG1" == "genmac" ]
then
  MAC="$(dd if=/dev/urandom bs=1 count=6 2>/dev/null | od -A n -t x1 | sed -e 's/^ //' -e 's/ /:/g')"
  MAC="${MAC:0:1}2${MAC:2}"
  echo "$MAC"
  
  exit
fi

# options (boot_style=chip):
# iso - update ISO image (not supported right now)
# isocl - re-create ISO image from scratch (not supported right now)
# flash - upload stage1 and flash firmware
# qemu - run ISO in qemu emulation

# options (boot_style=fel):
# aut - autonomous mode (no network dependency)

# additional options:
# spike* - selective corruption (not supported right now)
# inhibit - don't actually flash

OPT_ISO=n
OPT_ISOCL=n
OPT_ROOTFS=n
OPT_STAGE2=n
OPT_FLASH=n
OPT_QEMU=n
OPT_AUT=n
OPT_SPIKE1=n
OPT_SPIKE2K=n
OPT_SPIKE2M=n
OPT_SPIKE2B=n
OPT_INHIBIT=n

for i in "$@"
do
  [ "$i" == "iso"     ] && { OPT_ISO=y; }
  [ "$i" == "isocl"   ] && { OPT_ISOCL=y; OPT_ISO=y; }
  [ "$i" == "rootfs"  ] && { OPT_ROOTFS=y; }
  [ "$i" == "stage2"  ] && { OPT_STAGE2=y; }
  [ "$i" == "flash"   ] && { OPT_FLASH=y; OPT_STAGE2=y; }
  [ "$i" == "qemu"    ] && { OPT_QEMU=y; OPT_ISO=y; }
  [ "$i" == "aut"     ] && { OPT_AUT=y; }
  [ "$i" == "spike1"  ] && { OPT_SPIKE1=y; }
  [ "$i" == "spike2k" ] && { OPT_SPIKE2K=y; }
  [ "$i" == "spike2m" ] && { OPT_SPIKE2M=y; }
  [ "$i" == "spike2b" ] && { OPT_SPIKE2B=y; }
  [ "$i" == "inhibit" ] && { OPT_INHIBIT=y; }
done

CONFIG="$(basename "$ARG1" .sh)"

if [ ! -f ./config/"$CONFIG".sh ]
then
  echo "fatal: no such config ./config/'$CONFIG'.sh"
  exit 1
fi

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
        slurp_config "${LINE:9}"
      fi
    done
  )
}

echo "======> ENTER SLURP_CONFIG"
eval "$(slurp_config "$CONFIG")"
echo "======> LEAVE SLURP_CONFIG"

function firstline()
{
  local X
  IFS= read X
  echo "$X"
  cat >&2
}

function finhub_()
{
  [ -f ./local/vars-"$FINHUB_VARSET".sh ]
  
  # set the varset
  ln -vsfT ./vars-"$FINHUB_VARSET".sh ./local/vars.sh >&2
  
  # run finhub
  bash ./finhub.sh "$@"
}

function push_always()
{
  local NAME_REMOTE PATH_LOCAL
  
  NAME_REMOTE="$1"
  PATH_LOCAL="$2"
  
  finhub_ upload "$NAME_REMOTE" "$PATH_LOCAL"
}

function push_cached()
{
  local NAME_REMOTE PATH_LOCAL
  
  NAME_REMOTE="$1"
  PATH_LOCAL="$2"
  
  [ -n "$FINHUB_VARSET" ]
  
  mkdir -p  ./local/persist/already/"$FINHUB_VARSET"
  if [ ! -f ./local/persist/already/"$FINHUB_VARSET"/"$NAME_REMOTE" ]
  then
    push_always "$NAME_REMOTE" "$PATH_LOCAL"
    touch   ./local/persist/already/"$FINHUB_VARSET"/"$NAME_REMOTE"
  fi
}

function push_common_rootfs()
{
  . ./build/chroot/srcsel_rootfs_variables
  CSUM_ROOTFS_HYP="$(sha256sum ./build/chroot/"$SRCSEL_ROOTFS".hyp | cut -d " " -f 1)"
  push_cached rootfs.bin-"$CSUM_ROOTFS_HYP".bin ./local/gengen-build-btrfs-gentoo-builds-rootfs-mirror"$SRCSEL_ROOTFS".sqs
}

function push_commit()
{
  finhub_ commit
}

if [ "$BOOT_STYLE" == "chip" ]
then
  if [ "$OPT_ISOCL" == "y" ]
  then
    rm -f ./local/output/bootcd.iso
  fi
  
  finhub_ pubkey
  FINHUB_PUBKEY="$(finhub_ pubkey | firstline)"
  FINGEN_EXTRA_OPTIONS=CLASSICAL_INSERT_PKEY_AUTH="$FINHUB_PUBKEY" bash ./finfin.sh chip "$CONFIG" $([ "$OPT_ISO" == "y" ] && echo bootcd)
  
  if [ "$OPT_ISO" == "y" ]
  then
    false # not supported for the time being
  fi
  
  CSUM_STAGE1="$(sha256sum ./build/chroot/stage1.bin | cut -d " " -f 1)"
  
  # push stage1
  if [ "$OPT_FLASH" == "y" ]
  then
    push_cached stage1.bin-"$CSUM_STAGE1".bin ./build/chroot/stage1.bin
  fi
  
  # push stage2
  CSUM_STAGE2="$(sha256sum ./build/chroot/stage2.bin | cut -d " " -f 1)"
  SIZE_STAGE2="$(wc -c    <./build/chroot/stage2.bin)"
  push_cached stage2.bin-"$CSUM_STAGE2".bin ./build/chroot/stage2.bin
  
  # push rootfs
  push_common_rootfs
  
  # update and push manifest (last)
  finhub_ manifest "$MACHINE_NAME" "$CSUM_STAGE2" "$SIZE_STAGE2" "$CLASSICAL_STAGE2_DNS_HOST" "$CLASSICAL_STAGE2_HTTP_PORT" "$CLASSICAL_STAGE2_HTTP_HOST" "$CLASSICAL_STAGE2_HTTP_PATH" "$CSUM_STAGE1" "$CSUM_ROOTFS_HYP"
  for i in lst sig pub
  do
    push_always manifest."$i".txt ./build/manifest."$i".txt
  done
  
  push_commit
  
  if [ "$OPT_FLASH" == "y" ] && [ "$OPT_INHIBIT" == "n" ]
  then
    (
      cd ./build
      
      HOSTARCH="$(cat ./../local/hostarch)"
      
      if [ "$HOSTARCH" == "x64" ]
      then
        function flashpagan_()
        {
          sudo LD_LIBRARY_PATH=./chroot/x64/usr/lib64 ./chroot/x64/builds/flashpagan/flashpagan 256 "$(stat -c %s ./inp.bin)" "$FLASHPAGAN_SPI_SPEED_HZ" "$@"
        }
      else
        function flashpagan_()
        {
          sudo LD_LIBRARY_PATH=./chroot/usr/lib       ./chroot/usr/bin/flashpagan               256 "$(stat -c %s ./inp.bin)" "$FLASHPAGAN_SPI_SPEED_HZ" "$@"
        }
      fi
      
      cat ./boot.rom >./inp.bin
      
      function flashpagan_strategy_wrrd()
      {
        flashpagan_ flash
        flashpagan_ read
        
        local CSUM_INP CSUM_OUT
        CSUM_INP="$(sha256sum ./inp.bin | cut -d " " -f 1)"
        CSUM_OUT="$(sha256sum ./out.bin | cut -d " " -f 1)"
        [ "$CSUM_INP" == "$CSUM_OUT" ]
      }
      
      function flashpagan_strategy_conv()
      {
        flashpagan_ flashrobust
      }
      
      flashpagan_strategy_"$FLASHPAGAN_STRATEGY"
    )
  fi
  
  if [ "$OPT_QEMU" == "y" ]
  then
    qemu-system-x86_64 -serial stdio -m 1024 -k en-us -cdrom ./local/output/bootcd.iso -boot order=d
  else
    tail -n 8 ./build/manifest.lst.txt | sed -e 's/[0-9a-f]\{56\} /... /'
  fi
elif [ "$BOOT_STYLE" == "fel" ]
then
  FINGEN_EXTRA_OPTIONS=
  
  if [ "$OPT_AUT" == "y" ]
  then
    FINGEN_EXTRA_OPTIONS=STAGEF_AUTONOMOUS=y
  fi
  
  FINGEN_EXTRA_OPTIONS="$FINGEN_EXTRA_OPTIONS" bash ./finfin.sh fel "$CONFIG"
  
  if [ "$OPT_AUT" != "y" ]
  then
    CSUM_STAGE3="$(sha256sum                  ./build/chroot/init-stage3a | cut -d " " -f 1)"
    push_cached stage3.bin-"$CSUM_STAGE3".bin ./build/chroot/init-stage3a
    push_common_rootfs
    push_commit
  fi
  
  (
    cd ./build
    
    for i in proc sys dev
    do
      sudo mkdir -p ./chroot/"$i"
      sudo mount --bind /"$i" ./chroot/"$i"
    done
    
    function which_()
    {
      sudo chroot ./chroot busybox which "$1"
    }
    
    if   WHICH_FEL="$(which_ fel)"
    then
      true
    elif WHICH_FEL="$(which_ sunxi-fel)"
    then
      true
    else
      set +o errexit
      echo "!! could not find (sunxi-)fel binary"
      exit 1
    fi
    
    sudo chroot ./chroot "$WHICH_FEL" \
         -v \
         uboot            ./fel-u-boot \
         write 0x42000000 ./fel-kernel \
         write 0x43000000 ./fel-fdtree \
         write 0x43100000 ./fel-script \
         write 0x43300000 ./fel-initrd
    
    for i in proc sys dev
    do
      sudo umount ./chroot/"$i"
    done
  )
else
  echo "fatal: unrecognized BOOT_STYLE='$BOOT_STYLE'"
  exit 1
fi

echo "+OK (fingen.sh)"
