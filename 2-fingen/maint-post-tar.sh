#!/usr/bin/env bash

set -o xtrace
set -o errexit
set -o nounset
set -o pipefail
shopt -s failglob
shopt -s nullglob

ITHIRD_CHANNEL="$1"

(
  re='^[1-9]$'
  [[ "$ITHIRD_CHANNEL" =~ $re ]]
)

tar -C ./local -c obj_api_none --dereference | bash ./ithird/pusher.rb "$ITHIRD_CHANNEL"
