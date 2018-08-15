#!/bin/false

. /builds/elvopt

rm -rf --one-file-system /builds/flashpagan
mkdir -p                 /builds/flashpagan
cd                       /builds/flashpagan

[ "$(sha256sum /sources/special_libmpsse-"$OPTION_VERSION_LIBMPSSE_COMMIT".tar.gz | cut -d " " -f 1)" == "$OPTION_VERSION_LIBMPSSE_COMMIT_SHA" ]
tar -xf        /sources/special_libmpsse-"$OPTION_VERSION_LIBMPSSE_COMMIT".tar.gz

(
  cd ./libmpsse-*
  patch -p1 </tmp/patch-libmpsse-pb-b001-makefile-fix-1
  cd ./src
  ./configure --disable-python
  make
)

gcc --std=c99 -Os -W{error,all,extra} -I ./libmpsse-*/src -DLIBFTDI1=1 -o ./flashpagan /tmp/flashpagan.c ./libmpsse-*/src/libmpsse.a -l{usb-1.0,ftdi1}
