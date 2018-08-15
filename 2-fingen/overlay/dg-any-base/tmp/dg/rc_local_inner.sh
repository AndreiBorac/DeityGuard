#!/bin/false

set -o xtrace
set -o errexit
set -o nounset
set -o pipefail
shopt -s failglob
shopt -s nullglob

ARG1="${1-}"

. /tmp/dg/conf
f_defs

if [ -d /tmp/dg/as_"$ARG1" ]
then
  for i in /tmp/dg/as_"$ARG1"/*
  do
    if [ -f "$i" ]
    then
      . "$i"
    fi
  done
fi

f_"$ARG1"

echo '+OK (rc_local_inner.sh) ['"$ARG1"']'
