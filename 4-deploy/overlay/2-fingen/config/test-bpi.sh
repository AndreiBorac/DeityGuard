MACHINE_NAME=test_bpi

FINHUB_VARSET=test

#include model-bpi
#include fetch-local

function f_defs()
{
  ROOTSHADOW='*'
  TZDATA_TZ=GMT
  PKEY_COMMON='# pubkey goes here'
  PKEY_ROOT="$PKEY_COMMON"
  PKEY_USER="$PKEY_COMMON"
}

#include arm-common
