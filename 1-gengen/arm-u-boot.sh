#!/bin/false

. /builds/elvopt
CORESP1=$(( (CORES+1) ))
V="$OPTION_VERSION_U_BOOT"

mkdir -p /builds/arm-u-boot-"$ARMVER"
cd       /builds/arm-u-boot-"$ARMVER"

( [ "$FLAG_PRISTINE" == "y" ] && rm -rf --one-file-system ./u-boot-* ) || true

if [ ! -d ./u-boot-"$V" ]
then
  tar -xf /sources/special_u-boot-"$V".tar.bz2
fi

cd ./u-boot-"$V"

function make_()
{
  make CROSS_COMPILE=arm-linux-gnueabihf- "$@"
}

function make_()
{
  make CROSS_COMPILE=armv7a-hardfloat-linux-gnueabi- "$@"
}

. /tmp/common-cross-compile.sh

function make_()
{
  make CROSS_COMPILE=/tmp/cross_compile- "$@"
}

rm -rf --one-file-system                        /builds/arm-u-boot-final-"$ARMVER"/

for i in "${OPTION_U_BOOT_BOARD_NAME_LIST[@]}"
do
  rm -f ./.config
  make_ distclean
  make_ "$i"_defconfig
  cat >>./.config <<'EOF'
CONFIG_USB_EHCI_HCD=n
EOF
  make_ olddefconfig
  make_ -j"$CORESP1" || make_
  mkdir -p                                      /builds/arm-u-boot-final-"$ARMVER"/"$i"/
  cp --reflink=auto ./u-boot-sunxi-with-spl.bin /builds/arm-u-boot-final-"$ARMVER"/"$i"/
done
