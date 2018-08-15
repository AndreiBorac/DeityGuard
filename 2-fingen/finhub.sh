#!/usr/bin/env bash

# usage:
#
# ./finhub.sh create
# ./finhub.sh probe
# ./finhub.sh upload (remote-name) (local-path)
# ./finhub.sh commit
# ./finhub.sh pubkey
# ./finhub.sh manifest (machine-name) (stage2-digest) (stage2-size)

set -o xtrace
set -o errexit
set -o nounset
set -o pipefail
shopt -s failglob
shopt -s nullglob

ARG1="${1-}"
ARG2="${2-}"
ARG3="${3-}"
ARG4="${4-}"
ARG5="${5-}"
ARG6="${6-}"
ARG7="${7-}"
ARG8="${8-}"
ARG9="${9-}"
ARG10="${10-}"

set +o xtrace
. ./local/vars.sh
set -o xtrace

if ! mountpoint -q ./build
then
  [ -d ./build ] || sudo mkdir -m 0000 ./build
  mountpoint -q ./build || sudo mount -t tmpfs none ./build
fi

mountpoint -q ./build

. ./obj-api-"$OBJ_API".sh

function gpg_()
{
  local RL_GPG_HOMEDIR
  RL_GPG_HOMEDIR="$(readlink -f "$GPG_HOMEDIR")"
  if which gpg >/dev/null
  then
    gpg  --homedir="$RL_GPG_HOMEDIR" "$@"
  else
    gpg2 --homedir="$RL_GPG_HOMEDIR" "$@"
  fi
}

GPG_HOMEDIR=./local/persist/finhub/gnupg

if [ ! -d ./local/persist/finhub ]
then
  [ -d ./local ]
  mkdir -p ./local/persist/finhub
  
  mkdir -m 0700 -p "$GPG_HOMEDIR"
  UUIDGEN_R="$(cat /proc/sys/kernel/random/uuid)"
  cat >./build/script <<EOF
%echo KEYGEN
Key-Type: RSA
Key-Length: 4096
Subkey-Type: RSA
Subkey-Length: 4096
Name-Real: $UUIDGEN_R
Creation-Date: 1999-01-01
Expire-Date: 30y
%no-protection
%commit
EOF
  gpg_ --batch --gen-key ./build/script
  gpg_ --list-secret-keys
  
  touch ./local/persist/finhub/manifest.lst.txt
fi

function armor_all()
{
  cat ./local/persist/finhub/manifest.lst.txt | finhub_manifest_filter >./build/manifest.lst.txt
  
  gpg_ --armor --output ./build/manifest.sig.txt --detach-sig ./build/manifest.lst.txt
  
  gpg_ --export           >./build/manifest.pub.txt
  gpg_ --list-packets      ./build/manifest.pub.txt
  # check that the contents of what was exported is normal for a single public key
  local X
  X="$(gpg_ --list-packets ./build/manifest.pub.txt | egrep -o '^:[^:]+' | tr '\n' ';')"
  [ "$X" == ":public key packet;:user ID packet;:signature packet;:public sub key packet;:signature packet;" ]
}

function dump_pad_to()
{
  local ALIGN
  ALIGN="$1"
  local PAD_FILE
  PAD_FILE="$(mktemp)"
  cat >"$PAD_FILE"
  local SIZE
  SIZE="$(stat -c %s "$PAD_FILE")"
  SIZE="$(( (((SIZE+(ALIGN-1))/ALIGN)*ALIGN) ))"
  truncate -s "$SIZE" "$PAD_FILE"
  cat "$PAD_FILE"
  rm "$PAD_FILE"
}

case "$ARG1" in
  create)
    obj_api_test
    obj_api_create
    obj_api_stat
    ;;
  
  probe)
    obj_api_test
    obj_api_stat
    ;;
  
  upload)
    obj_api_test
    obj_api_upload "$ARG2" "$ARG3"
    ;;
  
  commit)
    obj_api_test
    obj_api_commit
    ;;
  
  pubkey)
    gpg_ --export | sha256sum - | cut -d " " -f 1
    ;;
  
  clean-manifest)
    rm -f ./local/persist/finhub/manifest.lst.txt
    ;;
  
  manifest)
    [ -f                      ./local/persist/finhub/serial ] ||\
      ( echo 1               >./local/persist/finhub/serial )
    SERIAL="$(cat             ./local/persist/finhub/serial)"
    echo "$(( (SERIAL+1) ))" >./local/persist/finhub/serial
    
    DATE="$(date -u +%Yy%mm%dd' @ '%H:%M:%S' (GMT)')"
    
    RE='^(0|([1-9][0-9]*))$'
    [[ $SERIAL =~ $RE ]]
    
    RE='^[-0-9A-Za-z_]+$'
    [[ $ARG2 =~ $RE ]]
    
    RE='^[0-9a-f]{64}$'
    [[ $ARG3 =~ $RE ]]
    
    RE='^(0|([1-9][0-9]*))$'
    [[ $ARG4 =~ $RE ]]
    
    RE='^[0-9]{4}y[0-9]{2}m[0-9]{2}d @ [0-9]{2}:[0-9]{2}:[0-9]{2} \(GMT\)$'
    [[ $DATE =~ $RE ]]
    
    PR_SERIAL="$(printf %06d "$SERIAL")"
    echo manifestly "$PR_SERIAL" "$ARG2" "$ARG3" "$ARG4" "'""$DATE""'" "'""$ARG5""'" "'""$ARG6""'" "'""$ARG7""'" "'""$ARG8""'" "'""$ARG9""'" "'""$ARG10""'" >./build/manifest.app.txt
    
    cat ./build/manifest.app.txt >>./local/persist/finhub/manifest.lst.txt
    
    armor_all
    ;;
  
  *)
    echo "unknown command '$ARG1'"
    exit 1
    ;;
esac

echo "+OK (finhub.sh)"
