#!/usr/bin/env bash

set -o xtrace
set -o errexit
set -o nounset
set -o pipefail
shopt -s failglob
shopt -s nullglob

set +o xtrace

MAC="$(dd if=/dev/urandom bs=1 count=6 2>/dev/null | od -A n -t x1 | sed -e 's/^ //' -e 's/ /:/g')"
MAC="${MAC:0:1}2${MAC:2}"
echo "$MAC"
