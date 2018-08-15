#!/bin/false

. /builds/elvopt
CORESP1=$(( (CORES+1) ))

function glob()
{
  GLOB=$(
    shopt -s nullglob
    GLOB=($1)
    echo "GLOB:'$1':'${GLOB[*]}'" >&2
    if [ "${#GLOB[@]}" != 1 ]
    then
      echo "BAD:GLOB:'$1':'${GLOB[*]}':${#GLOB[@]};" >&2
      exit 1
    fi
    echo "${GLOB[0]}"
  )
  echo "$GLOB"
}

function cp_()
{
  cp --reflink=auto "$@"
}

mkdir -p /builds/coreboot/source
cd       /builds/coreboot/source

function verify()
{
  local AC
  AC="$(sha256sum "$1" | cut -d " " -f 1)"
  [ "$AC" == "$2" ]
}

function clean()
{
  local WHICH="$1"
  
  ( rm -rf --one-file-system ./coreboot-* ) || true
  
  verify  /sources/special_coreboot-"$OPTION_VERSION_COREBOOT_COMMIT".tar.gz "$OPTION_VERSION_COREBOOT_COMMIT_SHA"
  tar -xf /sources/special_coreboot-"$OPTION_VERSION_COREBOOT_COMMIT".tar.gz
  
  (
    cd ./coreboot-*/3rdparty/vboot
    verify                       /sources/special_coreboot-vboot-"$OPTION_VERSION_COREBOOT_VBOOT_COMMIT".tar.gz "$OPTION_VERSION_COREBOOT_VBOOT_COMMIT_SHA"
    tar --strip-components=1 -xf /sources/special_coreboot-vboot-"$OPTION_VERSION_COREBOOT_VBOOT_COMMIT".tar.gz
  )
}

function toolchain()
{
  # load the tarballs even if we don't need to build the toolchain
  D=./util/crossgcc/tarballs
  mkdir -p "$D"
  local i
  for i in /sources/special_for_coreboot_*
  do
    j="$(echo "$i" | sed -e 's@^/sources/special_for_coreboot_@@')"
    ln -vsfT "$i" "$D"/"$j"
  done
  
  if [ ! -d /builds/coreboot-toolchain-xgcc ]
  then
    # disable useless thing that fails uselessly
    sed -i -e 's/^CROSSGCC_COMMIT=.*$//' ./util/crossgcc/buildgcc
    
    # toolchain build
    MAKE_BUILDGCC_OPTIONS="-b"
    make crossgcc-i386 BUILDGCC_OPTIONS="-b" CPUS="$CORESP1"
    make crossgcc-arm  BUILDGCC_OPTIONS="-b" CPUS="$CORESP1"
    
    # save the toolchain
    cp_ -ax ./util/crossgcc/xgcc /builds/coreboot-toolchain-xgcc
    
    # now get rid of the built toolchain so the below cp_ works
    rm -rf --one-file-system ./util/crossgcc/xgcc || true
  fi
  
  # get the saved toolchain
  cp_ -ax /builds/coreboot-toolchain-xgcc ./util/crossgcc/xgcc
}

function deblob()
{
  rm -f \
     3rdparty/vboot/tests/futility/data/* \
     src/cpu/dmp/vortex86ex/dmp_kbd_fw_part1.inc \
     src/vendorcode/amd/agesa/f*/Proc/CPU/Family/0x*/F*MicrocodePatch*.c \
     src/vendorcode/amd/agesa/f*/Proc/CPU/Family/0x*/*/F*MicrocodePatch*.c \
     src/vendorcode/amd/agesa/f*/Proc/GNB/Nb/Family/*/F*NbSmuFirmware.h \
     src/vendorcode/amd/agesa/f*/Proc/GNB/PCIe/Family/*/F*PcieAlibSsdt.h \
     src/vendorcode/amd/agesa/f*/Proc/GNB/Modules/GnbInit*/GnbSmuFirmware*.h \
     src/vendorcode/amd/agesa/f15tn/Proc/GNB/Modules/GnbInitTN/PcieAlibSsdt*.h \
     src/vendorcode/amd/agesa/f16kb/Proc/GNB/Modules/GnbInitKB/AlibSsdtKB.h \
     src/vendorcode/amd/agesa/f16kb/Proc/GNB/Modules/GnbInitKB/excel925.h \
     src/vendorcode/amd/agesa/f16kb/Proc/GNB/Modules/GnbInitKB/GnbSamuPatchKB.h \
     src/vendorcode/amd/cimx/rd890/HotplugFirmware.h
}

function deblob_test()
{
  for i in \
    ./3rdparty/vboot/tests/futility/data/bios_link_mp.bin \
    ./3rdparty/vboot/tests/futility/data/bios_mario_mp.bin \
    ./3rdparty/vboot/tests/futility/data/bios_peppy_mp.bin \
    ./3rdparty/vboot/tests/futility/data/bios_zgb_mp.bin \
    ./3rdparty/vboot/tests/futility/data/dingdong.signed \
    ./3rdparty/vboot/tests/futility/data/dingdong.unsigned \
    ./3rdparty/vboot/tests/futility/data/fw_gbb.bin \
    ./3rdparty/vboot/tests/futility/data/fw_vblock.bin \
    ./3rdparty/vboot/tests/futility/data/hoho.signed \
    ./3rdparty/vboot/tests/futility/data/hoho.unsigned \
    ./3rdparty/vboot/tests/futility/data/kern_preamble.bin \
    ./3rdparty/vboot/tests/futility/data/minimuffin.signed \
    ./3rdparty/vboot/tests/futility/data/minimuffin.unsigned \
    ./3rdparty/vboot/tests/futility/data/rec_kernel_part.bin \
    ./3rdparty/vboot/tests/futility/data/vmlinuz-amd64.bin \
    ./3rdparty/vboot/tests/futility/data/vmlinuz-arm.bin \
    ./3rdparty/vboot/tests/futility/data/zinger_mp_image.bin \
    ./3rdparty/vboot/tests/futility/data/zinger.signed \
    ./3rdparty/vboot/tests/futility/data/zinger.unsigned \
    ./3rdparty/vboot-d187cd3fc792f8bcefbee4587c83eafbd08441fc \
    ./src/cpu/dmp/vortex86ex/dmp_kbd_fw_part1.inc \
    ./src/vendorcode/amd/agesa/f10/Proc/CPU/Family/0x10/RevC/F10MicrocodePatch01000085.c \
    ./src/vendorcode/amd/agesa/f10/Proc/CPU/Family/0x10/RevC/F10MicrocodePatch01000086.c \
    ./src/vendorcode/amd/agesa/f10/Proc/CPU/Family/0x10/RevC/F10MicrocodePatch01000098.c \
    ./src/vendorcode/amd/agesa/f10/Proc/CPU/Family/0x10/RevC/F10MicrocodePatch010000b6.c \
    ./src/vendorcode/amd/agesa/f10/Proc/CPU/Family/0x10/RevD/F10MicrocodePatch010000c4.c \
    ./src/vendorcode/amd/agesa/f10/Proc/CPU/Family/0x10/RevD/F10MicrocodePatch010000c5.c \
    ./src/vendorcode/amd/agesa/f12/Proc/CPU/Family/0x10/RevC/F10MicrocodePatch01000085.c \
    ./src/vendorcode/amd/agesa/f12/Proc/CPU/Family/0x10/RevC/F10MicrocodePatch010000c6.c \
    ./src/vendorcode/amd/agesa/f12/Proc/CPU/Family/0x10/RevC/F10MicrocodePatch010000c7.c \
    ./src/vendorcode/amd/agesa/f12/Proc/CPU/Family/0x10/RevC/F10MicrocodePatch010000c8.c \
    ./src/vendorcode/amd/agesa/f12/Proc/CPU/Family/0x10/RevD/F10MicrocodePatch010000c4.c \
    ./src/vendorcode/amd/agesa/f12/Proc/CPU/Family/0x10/RevD/F10MicrocodePatch010000c5.c \
    ./src/vendorcode/amd/agesa/f12/Proc/CPU/Family/0x10/RevE/F10MicrocodePatch010000bf.c \
    ./src/vendorcode/amd/agesa/f12/Proc/CPU/Family/0x12/F12MicrocodePatch03000002.c \
    ./src/vendorcode/amd/agesa/f12/Proc/CPU/Family/0x12/F12MicrocodePatch0300000e.c \
    ./src/vendorcode/amd/agesa/f12/Proc/CPU/Family/0x12/F12MicrocodePatch0300000f.c \
    ./src/vendorcode/amd/agesa/f12/Proc/GNB/Nb/Family/LN/F12NbSmuFirmware.h \
    ./src/vendorcode/amd/agesa/f12/Proc/GNB/PCIe/Family/LN/F12PcieAlibSsdt.h \
    ./src/vendorcode/amd/agesa/f14/Proc/CPU/Family/0x10/RevC/F10MicrocodePatch01000085.c \
    ./src/vendorcode/amd/agesa/f14/Proc/CPU/Family/0x10/RevC/F10MicrocodePatch010000c6.c \
    ./src/vendorcode/amd/agesa/f14/Proc/CPU/Family/0x10/RevC/F10MicrocodePatch010000c7.c \
    ./src/vendorcode/amd/agesa/f14/Proc/CPU/Family/0x10/RevC/F10MicrocodePatch010000c8.c \
    ./src/vendorcode/amd/agesa/f14/Proc/CPU/Family/0x10/RevD/F10MicrocodePatch010000c4.c \
    ./src/vendorcode/amd/agesa/f14/Proc/CPU/Family/0x10/RevD/F10MicrocodePatch010000c5.c \
    ./src/vendorcode/amd/agesa/f14/Proc/CPU/Family/0x10/RevE/F10MicrocodePatch010000bf.c \
    ./src/vendorcode/amd/agesa/f14/Proc/CPU/Family/0x14/F14MicrocodePatch0500000B.c \
    ./src/vendorcode/amd/agesa/f14/Proc/CPU/Family/0x14/F14MicrocodePatch0500001A.c \
    ./src/vendorcode/amd/agesa/f14/Proc/CPU/Family/0x14/F14MicrocodePatch05000029.c \
    ./src/vendorcode/amd/agesa/f14/Proc/CPU/Family/0x14/F14MicrocodePatch05000119.c \
    ./src/vendorcode/amd/agesa/f14/Proc/GNB/Nb/Family/0x14/F14NbSmuFirmware.h \
    ./src/vendorcode/amd/agesa/f14/Proc/GNB/PCIe/Family/0x14/F14PcieAlibSsdt.h \
    ./src/vendorcode/amd/agesa/f15/Proc/CPU/Family/0x10/RevC/F10MicrocodePatch01000085.c \
    ./src/vendorcode/amd/agesa/f15/Proc/CPU/Family/0x10/RevC/F10MicrocodePatch010000c6.c \
    ./src/vendorcode/amd/agesa/f15/Proc/CPU/Family/0x10/RevC/F10MicrocodePatch010000c7.c \
    ./src/vendorcode/amd/agesa/f15/Proc/CPU/Family/0x10/RevC/F10MicrocodePatch010000c8.c \
    ./src/vendorcode/amd/agesa/f15/Proc/CPU/Family/0x10/RevD/F10MicrocodePatch010000c5.c \
    ./src/vendorcode/amd/agesa/f15/Proc/CPU/Family/0x10/RevD/F10MicrocodePatch010000d9.c \
    ./src/vendorcode/amd/agesa/f15/Proc/CPU/Family/0x10/RevE/F10MicrocodePatch010000bf.c \
    ./src/vendorcode/amd/agesa/f15/Proc/CPU/Family/0x15/OR/F15OrMicrocodePatch06000425.c \
    ./src/vendorcode/amd/agesa/f15/Proc/CPU/Family/0x15/OR/F15OrMicrocodePatch0600050D_Enc.c \
    ./src/vendorcode/amd/agesa/f15/Proc/CPU/Family/0x15/OR/F15OrMicrocodePatch06000624_Enc.c \
    ./src/vendorcode/amd/agesa/f15tn/Proc/CPU/Family/0x15/TN/F15TnMicrocodePatch0600110F_Enc.c \
    ./src/vendorcode/amd/agesa/f15tn/Proc/GNB/Modules/GnbInitTN/GnbSmuFirmwareTN.h \
    ./src/vendorcode/amd/agesa/f15tn/Proc/GNB/Modules/GnbInitTN/PcieAlibSsdtTNFM2.h \
    ./src/vendorcode/amd/agesa/f15tn/Proc/GNB/Modules/GnbInitTN/PcieAlibSsdtTNFS1.h \
    ./src/vendorcode/amd/agesa/f16kb/Proc/CPU/Family/0x16/KB/F16KbId7001MicrocodePatch.c \
    ./src/vendorcode/amd/agesa/f16kb/Proc/GNB/Modules/GnbInitKB/AlibSsdtKB.h \
    ./src/vendorcode/amd/agesa/f16kb/Proc/GNB/Modules/GnbInitKB/excel925.h \
    ./src/vendorcode/amd/agesa/f16kb/Proc/GNB/Modules/GnbInitKB/GnbSamuPatchKB.h \
    ./src/vendorcode/amd/agesa/f16kb/Proc/GNB/Modules/GnbInitKB/GnbSmuFirmwareKB.h \
    ./src/vendorcode/amd/cimx/rd890/HotplugFirmware.h
  do
    if [ -f "$i" ]
    then
      exit 1
    fi
  done
}

function apply_patches()
{
  for i in "$@"
  do
    patch -p1 </tmp/patch-coreboot-pb-b002-"$i"
  done
}

function hotfix()
{
  # the following fixes are equivalent to libreboot's
  # 0001-HOTFIX-AMD-fam10h-fam15h-don-t-use-microcode-updates.patch,
  # except for excluding the hunk applied to
  # src/cpu/amd/family_10h-family_15h/Makefile.inc, since it
  # apparently isn't actually needed to build (perhaps because we are
  # already setting CONFIG_CPU_MICROCODE_CBFS_NONE=y anyways)
  
  F=./src/cpu/amd/family_10h-family_15h/Kconfig
  cp "$F" "$F".old
  sed -e '/select CPU_MICROCODE_MULTIPLE_FILES/d' -i "$F"
  diff "$F".old "$F" || true
  rm -f "$F".old
  
  F=./src/cpu/Makefile.inc
  cp "$F" "$F".old
  sed -e 's/^ifneq ($(CONFIG_CPU_MICROCODE_MULTIPLE_FILES), y)$/CUT_FROM_HERE_3\nCUT_FROM_HERE_2\nCUT_FROM_HERE_1/' -i "$F"
  sed -e '/^CUT_FROM_HERE_1$/,/^endif$/d' -i "$F"
  sed -e '/^CUT_FROM_HERE_2$/,/^endif$/d' -i "$F"
  sed -e '/^CUT_FROM_HERE_3$/,/^endif$/d' -i "$F"
  sed -e '/^ifneq ($(CONFIG_CPU_MICROCODE_MULTIPLE_FILES), y)$/,/PATTERN-2/d' -i "$F"
  diff "$F".old "$F" || true
  rm -f "$F".old
}

function seabiosfix()
{
  # suppress checking-out of SeaBIOS by the build system
  # this has to work for Makefile and the older Makefile.inc
  for i in ./payloads/external/SeaBIOS/Makefile*
  do
    sed -i -e 's/^config: checkout$/config:/' "$i"
  done
  
  # check out seabios
  (
    cd ./payloads/external/SeaBIOS
    
    verify  /sources/special_coreboot-seabios-"$OPTION_VERSION_COREBOOT_SEABIOS_COMMIT".tar.gz "$OPTION_VERSION_COREBOOT_SEABIOS_COMMIT_SHA"
    tar -xf /sources/special_coreboot-seabios-"$OPTION_VERSION_COREBOOT_SEABIOS_COMMIT".tar.gz
    ln -vsfT ./seabios-* ./seabios
    
    cd ./seabios
    
    for i in no-option-roms-1
    do
      patch -p1 </tmp/patch-seabios-pb-b001-"$i"
    done
  )
}

###
###
###

function config_common()
{
  cat >>./.config <<'EOF'
CONFIG_INCLUDE_CONFIG_FILE=n
CONFIG_CPU_MICROCODE_CBFS_NONE=y
CONFIG_ON_DEVICE_ROM_LOAD=n
CONFIG_CONSOLE_CBMEM=n
CONFIG_POST_DEVICE=n
CONFIG_POST_IO=n
CONFIG_VGA_ROM_RUN=n
CONFIG_DRIVERS_INTEL_WIFI=n
#CONFIG_ONBOARD_VGA_IS_PRIMARY=n
CONFIG_CONSOLE_SERIAL=y
CONFIG_DRIVERS_UART_8250IO=y
CONFIG_PAYLOAD_SEABIOS=y
CONFIG_DRIVERS_PS2_KEYBOARD=y
CONFIG_USE_OPTION_TABLE=n
EOF
  seabiosfix
  apply_patches no-option-table-1
}

function config_qemu_q35()
{
  cat >./.config <<'EOF'
CONFIG_VENDOR_EMULATION=y
CONFIG_BOARD_EMULATION_QEMU_X86_Q35=y
EOF
  config_common
}

function config_t400()
{
  cat >./.config <<'EOF'
CONFIG_VENDOR_LENOVO=y
CONFIG_BOARD_LENOVO_T400=y
CONFIG_MAINBOARD_DO_NATIVE_VGA_INIT=y
CONFIG_FRAMEBUFFER_KEEP_VESA_MODE=y
EOF
  config_common
  apply_patches t400-no-ati-gfx-1
}

function config_d16()
{
  cat >./.config <<'EOF'
CONFIG_VENDOR_ASUS=y
CONFIG_BOARD_ASUS_KGPE_D16=y
EOF
  config_common
  apply_patches d16-no-mct-save-1
}

function config_veysp()
{
  cat >./.config <<'EOF'
CONFIG_VENDOR_GOOGLE=y
CONFIG_BOARD_GOOGLE_VEYRON_SPEEDY=y
EOF
  config_common
  sed -i -e 's/CONFIG_PAYLOAD_SEABIOS=y/#CONFIG_PAYLOAD_SEABIOS=y/' ./.config
  apply_patches arm-penguin-loader-1
}

function config_it()
{
  case "$1" in
    qemu_q35.4)
      config_qemu_q35
      cat >>./.config <<'EOF'
CONFIG_COREBOOT_ROMSIZE_KB_4096=y
CONFIG_CBFS_SIZE=0x400000
EOF
      ;;
    
    t400.4)
      config_t400
      cat >>./.config <<'EOF'
CONFIG_COREBOOT_ROMSIZE_KB_4096=y
CONFIG_CBFS_SIZE=0x3FD000
EOF
      ;;
    
    t400.8)
      config_t400
      cat >>./.config <<'EOF'
CONFIG_COREBOOT_ROMSIZE_KB_8192=y
CONFIG_CBFS_SIZE=0x7FD000
EOF
      ;;
    
    d16.4)
      config_d16
      cat >>./.config <<'EOF'
CONFIG_COREBOOT_ROMSIZE_KB_4096=y
CONFIG_CBFS_SIZE=0x400000
EOF
      ;;
    
    veysp.4)
      config_veysp
      cat >>./.config <<'EOF'
CONFIG_COREBOOT_ROMSIZE_KB_4096=y
CONFIG_CBFS_SIZE=0x400000
EOF
      ;;
    
    *)
      exit 1
      ;;
  esac
  
  cp ./.config /builds/coreboot/"$WHICH".cfs # config "seed"
  
  make olddefconfig
}

###
###
###

(
  ( shopt -u failglob ; rm -rf --one-file-system ./ich9gen-* ) || true
  verify  /sources/special_ich9gen-"$OPTION_VERSION_ICH9GEN_COMMIT".tar.gz "$OPTION_VERSION_ICH9GEN_COMMIT_SHA"
  tar -xf /sources/special_ich9gen-"$OPTION_VERSION_ICH9GEN_COMMIT".tar.gz
  (
    cd ./ich9gen-*
    make
  )
)

# clean out the fridge
( rm -f /builds/coreboot/*.{cfs,cfg,toc,rom} ) || true

for WHICH in qemu_q35.4 t400.{4,8} d16.4 veysp.4
do
  clean "$WHICH"
  (
    cd ./coreboot-*
    
    deblob
    deblob_test
    apply_patches no-ada-timeout-1
    toolchain
    
    config_it "$WHICH"
    cp_ ./.config /builds/coreboot/"$WHICH".cfg
    
    # parallel building is sadly broken in coreboot
    make V=1
    
    if [ "${WHICH:0:4}" == "t400" ]
    then
      DDIF="$(glob ./../ich9gen-*/ich9fdgbe_"${WHICH: -1}"m.bin)"
      dd if="$DDIF" of=./build/coreboot.rom conv=nocreat,notrunc
    fi
    
    ./build/cbfstool ./build/coreboot.rom print >/builds/coreboot/"$WHICH".toc
    
    cp_ ./build/coreboot.rom /builds/coreboot/"$WHICH".rom
    
    cp_ ./build/cbfstool /builds/coreboot/
  )
done
