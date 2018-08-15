#!/usr/bin/env bash

set -o xtrace
set -o errexit
set -o nounset
set -o pipefail

MODE="$1"
FILE="$2"

[ -f "$FILE" ]
FILE="$(readlink -f "$FILE")"

cd ./build

cat "$FILE" >./inp.bin

function flashpagan_()
{
  sudo LD_LIBRARY_PATH=./chroot/x64/usr/lib64 ./chroot/x64/builds/flashpagan/flashpagan 256 "$(stat -c %s ./inp.bin)" "$FLASHPAGAN_SPI_SPEED_HZ" "$@"
}

function flashpagan_strategy_wrrd()
{
  flashpagan_ flash
  flashpagan_ read
  
  local CSUM_INP CSUM_OUT
  CSUM_INP="$(sha256sum ./inp.bin | cut -d " " -f 1)"
  CSUM_OUT="$(sha256sum ./out.bin | cut -d " " -f 1)"
  [ "$CSUM_INP" == "$CSUM_OUT" ]
}

function flashpagan_strategy_conv()
{
  flashpagan_ flashrobust
}

if [ "$MODE" == "t400" ] || [ "$MODE" == "d16" ]
then
  FLASHPAGAN_SPI_SPEED_HZ=5000000
  flashpagan_strategy_wrrd
fi
