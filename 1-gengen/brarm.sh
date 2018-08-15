#!/bin/false

. /builds/elvopt

V="$OPTION_VERSION_BUILDROOT"

ODIR=/builds/brarm-output-"$ARMVER"
[ "$FLAG_PRISTINE" == "y" ] && rm -rf --one-file-system "$ODIR"

(
  rm -rf --one-file-system "$ODIR"/target/sources
  
  if [ "$FLAG_SOURCES" == "y" ]
  then
    mkdir -p "$ODIR"/target/sources
    
    function getsrc()
    {
      local fn="$1"
      
      cp --reflink=always /sources/"$fn" "$ODIR"/target/sources/
    }
    
    . /tmp/buildroot-dependencies
  fi
)

rm -rf --one-file-system /builds/brarm-"$ARMVER"
mkdir -p                 /builds/brarm-"$ARMVER"
cd                       /builds/brarm-"$ARMVER"

(
  mkdir ./sources
  
  for i in /sources/special_for_buildroot_*
  do
    j="$(echo "$i" | sed -e 's@/sources/special_for_buildroot_@@')"
    ln -vsfT "$i" ./sources/"$j"
  done
)

# install localsources packages
(
  mkdir ./localsources
  cd ./localsources
  
  mkdir ./flashpagan
  cp /tmp/flashpagan.c ./flashpagan/
)

# install patches
(
  mkdir -p ./patches/busybox
  cat /tmp/patch-busybox-pb-b002-openvt-fix-1 >./patches/busybox/0001-openvt-fix-1.patch
  
  #mkdir -p ./patches/qemu
  #cat /tmp/patch-qemu-pb-2.8.0-exec-follow-2  >./patches/qemu/0001-exec-follow-2.patch
  #cat /tmp/patch-qemu-pb-2.8.0-getdents-fix-1 >./patches/qemu/0001-getdents-fix-1.patch
  
  mkdir -p ./patches/libmpsse
  cat /tmp/patch-libmpsse-pb-b001-makefile-fix-1 >./patches/libmpsse/0001-makefile-fix-1.patch
  
  mkdir -p ./patches/tint2
  cat /tmp/patch-tint2-pb-b001-no-pollute-env-1 >./patches/tint2/0001-no-pollute-env-1.patch
)

[ "$(sha256sum /sources/special_buildroot-"$OPTION_VERSION_BUILDROOT".tar.bz2 | cut -d " " -f 1)" == "$OPTION_VERSION_BUILDROOT_SHA" ]
tar -xf        /sources/special_buildroot-"$OPTION_VERSION_BUILDROOT".tar.bz2

cd ./buildroot-"$V"

# here we hope that patch order doesn't matter
for i in /tmp/patch-buildroot-pb-"$V"-*
do
  patch -p1 <"$i"
done

# enable extra busybox features, but avoid changing modtime so as not to trigger rebuild every time
(
  touch -r ./package/busybox/busybox.config ./busybox.config.touch
  
  for i in STATIC STAT FEATURE_STAT_FORMAT BLOCKDEV TELNETD FEATURE_TELNETD_STANDALONE
  do
    sed -i -e 's/^# CONFIG_'"$i"' is not set/CONFIG_'"$i"'=y/' ./package/busybox/busybox.config
  done
  
  touch -r ./busybox.config.touch ./package/busybox/busybox.config
)

mkdir -p "$ODIR"

if egrep -q '^#brarm-purge$' /builds/elvopt
then
  ( rmdir /builds/brarm-output-"$ARMVER"/wunst/enable-* ) || true
fi

function wunst()
{
  if egrep -q '^#brarm-'"$1"'$' /builds/elvopt
  then
    mkdir -p /builds/brarm-output-"$ARMVER"/wunst/enable-"$1"
  fi
  
  if [ -d /builds/brarm-output-"$ARMVER"/wunst/enable-"$1" ]
  then
    return 0
  else
    return 1
  fi
}

function wunst_enable()
{
  local PN
  PN="$1"
  
  local PNUP
  PNUP="$(echo "$PN" | tr '[a-z\-]' '[A-Z_]')"
  
  cat >>"$ODIR"/.config <<EOF
BR2_PACKAGE_$PNUP=y
EOF
}

function wunst_plain()
{
  local PN
  PN="$1"
  
  if wunst "$PN"
  then
    wunst_enable "$PN"
  fi
}

function armver_ca7()
{
  cat >"$ODIR"/.config <<'EOF'
BR2_arm=y
BR2_cortex_a7=y
BR2_ARM_FPU_VFPV4D16=y
BR2_ARM_INSTRUCTIONS_THUMB2=y
EOF
}

function armver_ca17()
{
  cat >"$ODIR"/.config <<'EOF'
BR2_arm=y
BR2_cortex_a17=y
BR2_ARM_FPU_VFPV4=y
BR2_ARM_INSTRUCTIONS_THUMB2=y
EOF
}

armver_"$ARMVER"

cat >>"$ODIR"/.config <<EOF
BR2_DL_DIR="/builds/brarm-$ARMVER/sources"
BR2_GLOBAL_PATCH_DIR="/builds/brarm-$ARMVER/patches"
EOF

cat >>"$ODIR"/.config <<'EOF'
BR2_TARGET_TZ_INFO=y
EOF

cat >>"$ODIR"/.config <<'EOF'
BR2_SHARED_STATIC_LIBS=y
EOF

cat >>"$ODIR"/.config <<'EOF'
BR2_TOOLCHAIN_BUILDROOT_WCHAR=y
BR2_TOOLCHAIN_BUILDROOT_LOCALE=y
BR2_PTHREAD_DEBUG=y
BR2_TOOLCHAIN_BUILDROOT_CXX=y
BR2_KERNEL_HEADERS_4_4=y
BR2_ROOTFS_DEVICE_CREATION_DYNAMIC_EUDEV=y
BR2_ROOTFS_MERGED_USR=y
EOF

. /tmp/brarm-packages.sh

if wunst everything
then
  for i in "${BRARM_PACKAGES[@]}"
  do
    wunst_enable "$i"
  done
else
  for i in "${BRARM_PACKAGES[@]}"
  do
    wunst_plain "$i"
  done
fi

cat >>"$ODIR"/.config <<'EOF'
BR2_TARGET_ROOTFS_TAR=n
#BR2_TARGET_ROOTFS_CPIO=y
#BR2_TARGET_ROOTFS_CPIO_XZ=y
BR2_TARGET_ROOTFS_SQUASHFS=y
BR2_TARGET_ROOTFS_SQUASHFS4_XZ=y
EOF

cat >>"$ODIR"/.config <<'EOF'
BR2_PACKAGE_QEMU_CUSTOM_TARGETS="x86_64-linux-user"
EOF

make olddefconfig    O="$ODIR"

CLEAN="" # list of packages to force rebuild of (don't use this there's a separate gengen command for this now)
for i in $CLEAN
do
  make "$i"-dirclean O="$ODIR"
done

make                 O="$ODIR"

# as in squashfs.sh, make rootfs.sqs a multiple of the nbd-hyperbolic
# sector size (128KiB). incidentally, this is also the default
# squashfs block size (but the image is not padded to this size by
# squashfs)

SQSF="$(readlink -f "$ODIR"/images/rootfs.squashfs)"
SIZE="$(stat -c %s "$SQSF")"
BLKZ="$(( (128*1024) ))"
SIZE="$(( (((SIZE+(BLKZ-1))/BLKZ)*BLKZ) ))"
truncate -s "$SIZE" "$SQSF"
