#!/usr/bin/env bash

set -o xtrace
set -o errexit
set -o nounset
set -o pipefail
shopt -s failglob
shopt -s nullglob

FINHUB_VARSET="$1"
shift

[ -f ./local/vars-"$FINHUB_VARSET".sh ]

ln -vsfT ./vars-"$FINHUB_VARSET".sh ./local/vars.sh

bash ./finhub.sh "$@"
