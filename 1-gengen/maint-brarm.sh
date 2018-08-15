#!/usr/bin/env bash

set -o xtrace
set -o errexit
set -o nounset
set -o pipefail
shopt -s failglob
shopt -s nullglob

OPTION_VERSION_BUILDROOT=2017.11
OPTION_VERSION_BUILDROOT_SHA=ad6928741afdc5503ef849d1482825b5c31583e467e19212a303e1b25514a3b4

[ -d ./build ] || sudo mkdir -m 0000 ./build
mountpoint -q ./build && sudo umount ./build
mountpoint -q ./build && exit 1
sudo mount -t tmpfs none ./build
cd ./build

# you must have lzip and lunzip installed or buildroot will try to
# build them before downloading anything which kind of interferes with
# the download prevention patch we apply to buildroot. UPDATE: now
# they are faked here.

mkdir ./bin
ln -vsfT "$(which false)" ./bin/lzip
ln -vsfT "$(which false)" ./bin/lunzip
RL_BIN="$(readlink -f ./bin)"
export PATH="$RL_BIN":"$PATH"

if [ ! -f ./../local/buildroot-"$OPTION_VERSION_BUILDROOT".tar.bz2 ]
then
  wget  -O./../local/buildroot-"$OPTION_VERSION_BUILDROOT".tar.bz2.tmp https://buildroot.org/downloads/buildroot-"$OPTION_VERSION_BUILDROOT".tar.bz2
  mv      ./../local/buildroot-"$OPTION_VERSION_BUILDROOT".tar.bz2{.tmp,}
fi
[ "$(sha256sum ./../local/buildroot-"$OPTION_VERSION_BUILDROOT".tar.bz2 | cut -d " " -f 1)" == "$OPTION_VERSION_BUILDROOT_SHA" ]
tar --strip-components=1 -xf ./../local/buildroot-"$OPTION_VERSION_BUILDROOT".tar.bz2
for i in ./../files/patch-buildroot-pb-"$OPTION_VERSION_BUILDROOT"-{download-log-only-1,squashfs-url-fix-1,mmc-utils-url-fix-1,openbox-url-fix-1,argp-url-fix-1,sunxi-tools-revamp-1,extra-packages-1}
do
  patch -p1 <"$i"
done
rm -f /tmp/buildroot-dl-wrapper-log

cat ./../brarm.sh | egrep '^BR2_' | egrep -v '^BR2_(DL|GLOBAL_PATCH)_DIR=' >./.config
. ./../files/brarm-packages.sh
for PN in "${BRARM_PACKAGES[@]}"
do
  PNUP="$(echo "$PN" | tr '[a-z\-]' '[A-Z_]')"
  
  cat >>./.config <<EOF
BR2_PACKAGE_$PNUP=y
EOF
done
make olddefconfig
if [ "${1-}" == "xconfig" ]
then
  exec make xconfig
fi
make source

(
  function buildroot_dl_wrapper_log_entry()
  {
    if [ "${ARGV[0]}" != "-b" ] || [ "${ARGV[1]}" != "wget" ] || [ "${ARGV[2]}" != "-o" ] || [ "${ARGV[4]}" != "-H" ] || [ "${ARGV[6]}" != "--" ]
    then
      set +o xtrace
      echo "!! unexpected dl_wrapper invocation" >&2
      echo "!! note that only wget is supported, not git" >&2
      echo "!! bye" >&2
      exit 1
    fi
    local OUT
    OUT="$(basename "${ARGV[3]}")"
    local URL
    URL="${ARGV[7]}"
    
    echo "getsrc special_for_buildroot_'$OUT' '$URL'"
  }
  
  . /tmp/buildroot-dl-wrapper-log
) | sort | uniq >./../files/buildroot-dependencies

echo "+OK (maint-brarm.sh)"
