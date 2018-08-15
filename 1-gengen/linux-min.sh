#!/bin/false

. /builds/elvopt
CORESP1=$(( (CORES+1) ))
V="$OPTION_VERSION_LINUX_LIBRE"

for i in d16
do
  mkdir -p /builds/linux-libre-x64-min-"$i"
  cd       /builds/linux-libre-x64-min-"$i"
  ( rm -rf --one-file-system ./linux-* ) || true
  
  tar -xf /sources/special_linux-libre-"$V"-gnu.tar.xz
  cd ./linux-"$V"
  
  . /tmp/linux-config-x64-min-"$i".sh
  
  make -j"$CORESP1"
done
