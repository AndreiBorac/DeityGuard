#!/usr/bin/env bash

set -o xtrace
set -o nounset
set -o errexit
set -o nounset
set -o pipefail
shopt -s failglob
shopt -s nullglob

SSH_HOST="$(cat         ./local/boomerang-ssh-host)"
SSH_USER="$(cat         ./local/boomerang-ssh-user)"
SSH_AUTH="$(readlink -f ./local/boomerang-ssh-auth)"

LOCAL_DIR="$(cat        ./local/boomerang-local-dir)"

function ssh_()
{
  ssh -o IdentityFile="$SSH_AUTH" "$SSH_USER"@"$SSH_HOST" "$@"
}

function shellesc()
{
  echo -n "'"
  sed -e 's/'"'"'/'"'"'"'"'"'"'"'"'/g'
  echo -n "'"
}

OPT_MAINT_BRARM_XCONFIG_HELPER=n
OPT_MAINT_BRARM_HELPER=n

[ "$1" == "--maint-brarm-xconfig-helper" ] && { shift; OPT_MAINT_BRARM_XCONFIG_HELPER=y; }
[ "$1" == "--maint-brarm-helper"         ] && { shift; OPT_MAINT_BRARM_HELPER=y; }

ARGV=("$@")

function export_loadable_variables()
{
  declare -p "$@"
}

function export_loadable_variables_ifset()
{
  local i
  for i in "$@"
  do
    if [ "${!i+set}" == "set" ]
    then
      export_loadable_variables "$i"
    fi
  done
}

VARS="$(export_loadable_variables LOCAL_DIR ARGV && export_loadable_variables_ifset GENGEN_NETESC)"
VARS="$(echo "$VARS" | shellesc)"

if mountpoint -q ./build
then
  touch ./build/CACHEDIR.TAG
fi

if [ -d ./local ]
then
  touch ./local/CACHEDIR.TAG
fi

OPTS_SSH=""

if [ "$OPT_MAINT_BRARM_XCONFIG_HELPER" == "y" ]
then
  
  OPTS_SSH="$OPTS_SSH -X"
fi

tar -c -h --exclude-tag-all=CACHEDIR.TAG . | ssh_ $OPTS_SSH '
set -o xtrace
set -o errexit
set -o nounset
set -o pipefail

mkdir -p                 /tmp/boomerang-gengen
( cd                     /tmp/boomerang-gengen/root ; ./gengen.sh -c ) || true
mountpoint -q            /tmp/boomerang-gengen && sudo umount /tmp/boomerang-gengen
mountpoint -q            /tmp/boomerang-gengen && exit 1
sudo mount -t tmpfs none /tmp/boomerang-gengen
mkdir                    /tmp/boomerang-gengen/root
cd                       /tmp/boomerang-gengen/root

tar -x
VARS='"$VARS"'
echo VARS='"'"'$VARS'"'"'
eval "$VARS"
ln -vsfT "$LOCAL_DIR"/ ./local
env
"${ARGV[@]}"
'

if [ "$OPT_MAINT_BRARM_HELPER" == "y" ]
then
  A="$(mktemp)"
  ssh_ 'cat /tmp/boomerang-gengen/root/files/buildroot-dependencies' >"$A"
  cat "$A" >./files/buildroot-dependencies
  rm -f "$A"
fi

echo "+OK (boomerang.sh)"
