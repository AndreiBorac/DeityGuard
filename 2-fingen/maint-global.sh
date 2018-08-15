#!/usr/bin/env bash

set -o xtrace
set -o errexit
set -o nounset
set -o pipefail
shopt -s failglob
shopt -s nullglob

ARG1="${1-}"

OPT_DIET=n
OPT_NORT=n
OPT_POST=n

for i in "$@"
do
  if [ "$i" == "diet" ]; then OPT_DIET=y; fi
  if [ "$i" == "nort" ]; then OPT_NORT=y; fi
  if [ "$i" == "post" ]; then OPT_POST=y; fi
done

if [ -f ./local/persist/finhub/manifest.lst.txt ]
then
  mv    ./local/persist/finhub/manifest.lst.txt{,.restore}
fi

CONFIGS="$(echo ./config/global-*)"

if [ "$OPT_DIET" == "y" ]
then
  CONFIGS=./config/global-t400.8-mac1.sh
  CONFIGS=./config/global-d16.4.sh
fi

for i in $CONFIGS
do
  ./fingen.sh "$i" flash inhibit
  
  if [ -f ./build/boot.rom ]
  then
    cp    ./build/boot.rom ./local/obj_api_none/boot.bin-"$(basename "$i" .sh)".bin
  fi
done

FILES="manifest.lst.txt manifest.pub.txt manifest.sig.txt"

for i in $CONFIGS
do
  FILES="$FILES boot.bin-""$(basename "$i" .sh)"".bin"
done

function manifestly()
{
  FILES="$FILES stage2.bin-${3}.bin stage1.bin-${10}.bin"
  
  if [ "$OPT_NORT" == "n" ]
  then
    FILES="$FILES rootfs.bin-${11}.bin"
  fi
}

if [ -f ./local/obj_api_none/manifest.lst.txt ]
then
  .     ./local/obj_api_none/manifest.lst.txt
else
  .     ./local/persist/finhub/manifest.lst.txt
fi

FILES="$(echo "$FILES" | tr ' ' '\n' | sort | uniq | tr '\n' ' ')"

(
  cat <<'EOF'
#!/usr/bin/env bash

set -o xtrace
set -o errexit
set -o nounset
set -o pipefail
shopt -s failglob
shopt -s nullglob

if ! which curl
then
  sudo apt-get -y install curl
fi

. ./vars-global-maint.sh

. ./obj-api-ovhcurl-and-bucket.sh
EOF
  
  echo FINGEN_OBJ_API_OVHCURL_AND_BUCKET_NETESC=
  
  for i in $FILES
  do
    if [ "${i:0:11}" == "rootfs.bin-" ]
    then
      echo 'if [ "$(curl --head "$OVH_OUTPUT"/"$OVH_CONTAINER"/'"$i"' | head -n 1 | cut -d " " -f 2)" == 404 ]'
      echo 'then'
    fi
    
    echo obj_api_upload "'$(basename "$i")'" "'$i'"
    
    if [ "${i:0:11}" == "rootfs.bin-" ]
    then
      echo 'fi'
    fi
  done
) >/tmp/doit.sh

tar -cf ./local/obj_api_none/tar.tar \
    -C "$(readlink -f /tmp/)" ./doit.sh \
    -C "$(readlink -f ./)" ./obj-api-ovhcurl-and-bucket.sh \
    -C "$(readlink -f ./local/)" ./vars-global-maint.sh \
    -C "$(readlink -f ./local/obj_api_none/)" $FILES

if [ -f ./local/persist/finhub/manifest.lst.txt.restore ]
then
  mv    ./local/persist/finhub/manifest.lst.txt{.restore,}
else
  rm -f ./local/persist/finhub/manifest.lst.txt
fi

if [ "$OPT_POST" == "y" ]
then
  ITHIRD_CHANNEL=2
  tar -C ./local/obj_api_none/ -c ./tar.tar | bash ./ithird/pusher.rb "$ITHIRD_CHANNEL"
fi

echo "+OK (maint-global.sh)"
