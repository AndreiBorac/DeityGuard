#!/bin/false

. /builds/elvopt
CORESP1=$(( (CORES+1) ))
V="$OPTION_VERSION_LINUX_LIBRE"

mkdir -p /builds/linux-libre-"$ARMVER"-"$TARGET"
cd       /builds/linux-libre-"$ARMVER"-"$TARGET"

( [ "$FLAG_PRISTINE" == "y" ] && rm -rf --one-file-system ./linux-* ) || true

tar -xf /sources/special_linux-libre-"$V"-gnu.tar.xz
cd ./linux-"$V"
rm -rf --one-file-system ./extra
(
  for i in "${LINUX_PATCHES[@]}"
  do
    if [ "$i" != "" ]
    then
      patch -p1 <"$i"
    fi
  done
)

if [ "$ARMVER" != "x64" ]
then
  . /tmp/common-cross-compile.sh
  
  function make_()
  {
    make ARCH=arm CROSS_COMPILE=/tmp/cross_compile- "$@"
  }
  
  LINUX_ARCH=arm
  LINUX_IMAGE=zImage
else
  function make_()
  {
    make "$@"
  }
  
  LINUX_ARCH=x86
  LINUX_IMAGE=bzImage
fi

. /tmp/linux-config-"$TARGET".sh

make_ -j"$CORESP1"

function verify()
{
  local AC
  AC="$(sha256sum "$1" | cut -d " " -f 1)"
  [ "$AC" == "$2" ]
}

ZOLDIR=/tmp/zol_fH79tnJ9

if true # if true, enable zfs support
then
  if [ "$ARMVER" == "x64" ]
  then
    (
      mkdir -p "$ZOLDIR"
      
      LINUX_SOURCE_PATH="$(readlink -f .)"
      
      inotifywait -m -r . --format '%e %w%f' >"$ZOLDIR"/accesses &
      PID_INOTIFYWAIT="$!"
      
      pushd   "$ZOLDIR"
      
      verify /sources/special_for_zfs_spl-"$OPTION_VERSION_ZFS".tar.gz "$OPTION_VERSION_ZFS_SPL_SHA"
      verify /sources/special_for_zfs_zfs-"$OPTION_VERSION_ZFS".tar.gz "$OPTION_VERSION_ZFS_ZFS_SHA"
      
      mkdir ./spl
      (
        cd ./spl
        tar --strip-components=1 -xf /sources/special_for_zfs_spl-"$OPTION_VERSION_ZFS".tar.gz
        sh autogen.sh
        ./configure --with-linux="$LINUX_SOURCE_PATH"
        make -j"$CORESP1"
      )
      SPL_SOURCE_PATH="$(readlink -f ./spl)"
      
      mkdir ./zfs
      (
        cd ./zfs
        tar --strip-components=1 -xf /sources/special_for_zfs_zfs-"$OPTION_VERSION_ZFS".tar.gz
        sh autogen.sh
        ./configure --with-config=kernel --with-linux="$LINUX_SOURCE_PATH" --with-spl="$SPL_SOURCE_PATH"
        make -j"$CORESP1"
      )
      
      function tar_ko()
      {
        find . -type f | ( egrep -i '\.ko$' || true ) | LC_ALL=C sort | tar --files-from - --mtime='1999-01-01 00:00:00Z' --create
      }
      
      if false # for testing purposes only; do not enable in production
      then
        mkdir -p /tmp/zfs_on_linux/special_zfs
        tar_ko  >/tmp/zfs_on_linux/special_zfs/ko.tar
      fi
      
      TAR_KO_SIZ="$(tar_ko | wc -c)"
      TAR_KO_SHA="$(tar_ko | sha256sum - | cut -d " " -f 1)"
      
      popd
      
      # give inotifywait time to finish processing events. TODO: replace
      # this with something more robust.
      sleep 0.25
      
      kill "$PID_INOTIFYWAIT"
      wait || true
      
      DSTDIR="$ZOLDIR"/special_zfs/headers
      
      mkdir -p "$DSTDIR"
      
      cat "$ZOLDIR"/accesses |\
        ( egrep -v 'ISDIR' || true ) |\
        ( egrep 'OPEN' || true ) |\
        cut -d " " -f 2 |\
        sort |\
        uniq |\
        xargs -I'{}' cp --verbose --parents '{}' "$DSTDIR"
      
      declare -p OPTION_VERSION_ZFS TAR_KO_SIZ TAR_KO_SHA >"$ZOLDIR"/special_zfs/version
      
      gzip -d </sources/special_for_zfs_spl-"$OPTION_VERSION_ZFS".tar.gz >"$ZOLDIR"/special_zfs/spl.tar
      gzip -d </sources/special_for_zfs_zfs-"$OPTION_VERSION_ZFS".tar.gz >"$ZOLDIR"/special_zfs/zfs.tar
    )
  fi
fi

rm -rf --one-file-system                      /builds/linux-libre-final-"$ARMVER"-"$TARGET"

make_  modules_install       INSTALL_MOD_PATH=/builds/linux-libre-final-"$ARMVER"-"$TARGET"

V="$(ls -1                                    /builds/linux-libre-final-"$ARMVER"-"$TARGET"/lib/modules | head -n 1)"
mkdir -p                                      /builds/linux-libre-final-"$ARMVER"-"$TARGET"/lib/modules/"$V"/{headers,firmware,boot,special_zfs}

make_ headers_install        INSTALL_HDR_PATH=/builds/linux-libre-final-"$ARMVER"-"$TARGET"/lib/modules/"$V"/headers

# for now, make firmware install is done with || true since 4.14.8 no longer supports this
# TODO: find out why, and what command(s) replace make firmware install and integrate them here
make_ firmware_install        INSTALL_FW_PATH=/builds/linux-libre-final-"$ARMVER"-"$TARGET"/lib/modules/"$V"/firmware || true

cp   ./.config                                /builds/linux-libre-final-"$ARMVER"-"$TARGET"/lib/modules/"$V"/boot/config
cp   ./arch/"$LINUX_ARCH"/boot/"$LINUX_IMAGE" /builds/linux-libre-final-"$ARMVER"-"$TARGET"/lib/modules/"$V"/boot/"$LINUX_IMAGE"
if [ "$ARMVER" != "x64" ]
then
  cp ./arch/"$LINUX_ARCH"/boot/dts/*.dtb      /builds/linux-libre-final-"$ARMVER"-"$TARGET"/lib/modules/"$V"/boot/
fi

if [ -d "$ZOLDIR"/special_zfs ]
then
  (
    cd  "$ZOLDIR"/special_zfs
    cp -vax ./                                /builds/linux-libre-final-"$ARMVER"-"$TARGET"/lib/modules/"$V"/special_zfs/
  )
fi

(
  cd                                          /builds/linux-libre-final-"$ARMVER"-"$TARGET"/lib/modules/"$V"
  
  mksquashfs ./{kernel,headers,firmware,boot,special_zfs} ./modules.* ./boot/modules.sqs
)
