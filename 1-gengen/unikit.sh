#!/bin/false

. /builds/elvopt

rm -rf --one-file-system /builds/unikit
mkdir                    /builds/unikit
cd                       /builds/unikit

function cp_()
{
  cp --reflink=auto "$@"
}

function cp_from()
{
  (
    cd "$1"
    shift
    cp --reflink=auto -vax "$@"
  )
}

function rand_uint_4()
{
  dd if=/dev/urandom bs=1 count=4 2>/dev/null | od -A none -t u4 | egrep -o '[0-9]+'
}

function prepare_root_image()
{
  local DN
  DN="$1"
  shift
  
  local BN
  BN="$1"
  shift
  
  # note that we don't invalidate the (possibly uploaded) sqs files by
  # changing the salts here and recalculating the hyp files. we only
  # invalidate the hyp and inf files which stay with the unikit data.
  
  if [ "$DN"/"$BN".sqs -nt "$DN"/"$BN".hyp ] || [ "$DN"/"$BN".sqs -nt "$DN"/"$BN".inf ]
  then
    local CSUM_ROOTFS
    CSUM_ROOTFS="$(sha256sum "$DN"/"$BN".sqs | cut -d " " -f 1)"
    
    local NH_IMAGE_SIZE
    NH_IMAGE_SIZE="$(stat -c %s "$(readlink -f "$DN"/"$BN".sqs)")"
    
    local NH_CACHE_BLOCK_SIZE_LOG
    NH_CACHE_BLOCK_SIZE_LOG=17
    
    local BLKZ
    BLKZ="$(( (2**NH_CACHE_BLOCK_SIZE_LOG) ))"
    
    if (( (((NH_IMAGE_SIZE+(BLKZ-1))/BLKZ)*BLKZ) != NH_IMAGE_SIZE ))
    then
      set +o xtrace
      echo "!! root sqs not a multiple of the nbd-hyperbolic block size"
      exit 1
    fi
    
    local NH_CACHE_USER_A NH_CACHE_USER_B NH_CACHE_USER_C NH_CACHE_USER_D
    NH_CACHE_USER_A="$(rand_uint_4)"
    NH_CACHE_USER_B="$(rand_uint_4)"
    NH_CACHE_USER_C="$(rand_uint_4)"
    NH_CACHE_USER_D="$(rand_uint_4)"
    
    NH_PREPARE_ONLY=y \
    NH_IMAGE_SIZE="$NH_IMAGE_SIZE" \
    NH_CACHE_BLOCK_SIZE_LOG="$NH_CACHE_BLOCK_SIZE_LOG" \
    NH_CACHE_USER_A="$NH_CACHE_USER_A" \
    NH_CACHE_USER_B="$NH_CACHE_USER_B" \
    NH_CACHE_USER_C="$NH_CACHE_USER_C" \
    NH_CACHE_USER_D="$NH_CACHE_USER_D" \
    NH_CACHE_BACKING_FILE="$(readlink -f "$DN"/"$BN".sqs)" \
    NH_CACHE_BACKING_OFFSET=0 \
    /builds/nbd-hyperbolic-x64/nbd-hyperbolic >"$DN"/"$BN".hyp.tmp
    
    cat >"$DN"/"$BN".inf.tmp <<EOF
CSUM_ROOTFS=${CSUM_ROOTFS}
NH_IMAGE_SIZE=${NH_IMAGE_SIZE}
NH_CACHE_BLOCK_SIZE_LOG=${NH_CACHE_BLOCK_SIZE_LOG}
NH_CACHE_USER_A=${NH_CACHE_USER_A}
NH_CACHE_USER_B=${NH_CACHE_USER_B}
NH_CACHE_USER_C=${NH_CACHE_USER_C}
NH_CACHE_USER_D=${NH_CACHE_USER_D}
EOF
    
    mv "$DN"/"$BN".hyp{.tmp,}
    mv "$DN"/"$BN".inf{.tmp,}
    
    touch "$DN"/"$BN".{hyp,inf}
    
    mkdir -p /builds/rootfs-mirror
    cp --reflink=auto --parents --verbose "$DN"/"$BN".sqs /builds/rootfs-mirror/
  fi
}

. /tmp/bincop.sh

# include x64 binaries

bincop_reset
BINCOP_DEST=./x64
BINCOP_ROOT=
BINCOP_PATH=({usr/{local/,},}{s,}bin)
# reverse PATH order. this is due to gentoo yukiness where a lot of
# stuff earlier in PATH is symlinked to stuff later in PATH, which
# confuses bincop which is really only desiged to handle unique
# basenames
BINCOP_PATH=({,usr/{,local/}}{,s}bin)
# more gentoo yukiness
BINCOP_LD_LIBRARY_PATH_GCC="$(cat /etc/ld.so.conf.d/05gcc-x86_64-pc-linux-gnu.conf | sort | head -n 1 | sed -e 's@^/@@')"
BINCOP_LD_LIBRARY_PATH=(lib64 usr/lib64 "$BINCOP_LD_LIBRARY_PATH_GCC")
BINCOP_ZERO_POINT=(lib64/ld-linux-x86-64.so.2)
BINCOP_TOOLCHAIN_PREFIX=""

mkdir -p "$BINCOP_DEST"
#echo "${BINCOP_LD_LIBRARY_PATH[@]}" >"$BINCOP_DEST"/ld_library_path
echo "${BINCOP_LD_LIBRARY_PATH[@]/#//}" | tr ' ' ':' >"$BINCOP_DEST"/ld_library_path
bincop_add_zero_point
# runtime
COMMON_BINARIES=()
COMMON_BINARIES+=(busybox bash dd cp gpgv2 cpio kexec dialog sgdisk partx udevadm dmsetup nbd-client dtc)
# runtime (debugging)
COMMON_BINARIES+=(strace)
# x64-specific
bincop_add_binaries /lib64/udev/scsi_id openvt dnsip
# fingen
# tar needed to dynamically create overlay tar file
COMMON_BINARIES+=(tar xz mkimage)
# x64-specific
bincop_add_binaries ssh-keygen /lib64/libnss_files.so.2 fel /builds/flashpagan/flashpagan
bincop_add_binaries /builds/coreboot/cbfstool xorriso isohybrid
bincop_add_binaries "${COMMON_BINARIES[@]}"

# include all available brarm images and binaries (UPDATE: for
# uniformity with gentoo, do not include the system squashfs; instead,
# generate and include nbd-hyperbolic metadata)

function add_brarm()
{
  local ARMVER
  for ARMVER in "${ALLARMVERS[@]}"
  do
    if [ -d                      /builds/brarm-output-"$ARMVER" ]
    then
      ln -vsfT ./rootfs.squashfs /builds/brarm-output-"$ARMVER"/images/system.sqs
      prepare_root_image         /builds/brarm-output-"$ARMVER"/images system
      cp_ -vax --parents         /builds/brarm-output-"$ARMVER"/images/system.{hyp,inf} ./
      
      bincop_reset
      BINCOP_DEST=./builds/brarm-output-"$ARMVER"/target
      BINCOP_ROOT=/builds/brarm-output-"$ARMVER"/target
      BINCOP_PATH=({usr/{local/,},}{s,}bin)
      BINCOP_LD_LIBRARY_PATH=(usr/lib)
      BINCOP_ZERO_POINT=(usr/lib/ld-uClibc.so.0)
      BINCOP_TOOLCHAIN_PREFIX=/builds/brarm-output-"$ARMVER"/host/usr/bin/arm-linux-
      
      mkdir -p "$BINCOP_DEST"
      bincop_add_zero_point
      # runtime
      bincop_add_binaries "${COMMON_BINARIES[@]}" /usr/lib/udev/scsi_id coreutils
      # fingen
      bincop_add_binaries ssh-keygen sunxi-fel flashpagan
      bincop_add_binaries cbfstool
      # arm only (debugging)
      bincop_add_binaries gdbserver #mmc addpart delpart resizepart
    fi
  done
}
add_brarm

# include all tools (all arches)

function add_tools()
{
  local TOOL
  for TOOL in "$@"
  do
    local ARMVER
    for ARMVER in x64 "${ALLARMVERS[@]}"
    do
      if [ -d /builds/"$TOOL"-"$ARMVER" ]
      then
        cp_ -vax --parents /builds/"$TOOL"-"$ARMVER" ./
      fi
    done
  done
}
add_tools nbd-hyperbolic unpranker instigator safepipe murmur linuxtools fanman gptize

# include x64 linux libre image

cp_ -vax /builds/linux-libre-final-x64-x64 ./builds/

# include x64 linux libre minimal images

if false
then
  for i in d16
  do
    mkdir -p                                                           ./builds/linux-libre-final-min-"$i"/
    cp_ /builds/linux-libre-x64-min-"$i"/linux-*/arch/x86/boot/bzImage ./builds/linux-libre-final-min-"$i"/
  done
fi

# include all available arm linux libre images

function add_arm_linux()
{
  local ARMVER
  for   ARMVER in "${ALLARMVERS[@]}"
  do
    for j in bpi rok
    do
      if [ -d              /builds/linux-libre-final-"$ARMVER"-"$j" ]
      then
        cp_ -vax --parents /builds/linux-libre-final-"$ARMVER"-"$j" ./
      fi
    done
  done
}
add_arm_linux

# include all available arm u-boot images

function add_arm_u_boot()
{
  local ARMVER
  for   ARMVER in "${ALLARMVERS[@]}"
  do
    if [ -d              /builds/arm-u-boot-final-"$ARMVER" ]
    then
      cp_ -vax --parents /builds/arm-u-boot-final-"$ARMVER" ./
    fi
  done
}
add_arm_u_boot

# include ancillary data (x64/gentoo)

# what's this for again?
cp_ -vax --parents /etc/ssl/openssl.cnf ./x64/

# for lspci
cp_ -vax --parents /usr/share/misc/pci.ids.gz ./x64/

# for lsusb
cp_ -vax --parents /usr/share/misc/usb.ids.gz ./x64/
cp_ -vax --parents /etc/udev/hwdb.bin ./x64/

# for dialog
cp_ -vax --parents /etc/terminfo ./x64/

# for isolinux
cp_ -vax --parents /usr/share/syslinux ./x64/

# include ancillary data (arm/buildroot)

function add_arm_ancillary()
{
  local ARMVER
  for   ARMVER in "${ALLARMVERS[@]}"
  do
    if [ -d                /builds/brarm-output-"$ARMVER" ]
    then
      local i
      for i in usr/share/terminfo
      do
        cp_ -vax --parents /builds/brarm-output-"$ARMVER"/target/"$i" ./
      done
    fi
  done
}
add_arm_ancillary

# coreboot ROMs
mkdir -p ./builds/coreboot
cp_ -vax --parents /builds/coreboot/*.{cfg,toc,rom} ./

# prepare root image and include nbd-hyperbolic metadata

prepare_root_image /builds gentoo
cp_ -vax --parents /builds/gentoo.{hyp,inf} ./

tar --owner=0 --group=0 --mtime=0 -c . | lzop -c >/builds/unikit.tzo

# for logging the size of the unikit
stat -c %s /builds/unikit.tzo
ls -alh    /builds/unikit.tzo
