MACHINE_NAME=test_t400

ETH_HWADDR="f2:03:eb:57:5a:94"

FINHUB_VARSET=test

#include model-t400.8
#include fetch-local

function f_defs()
{
  ROOTSHADOW='*'
  TZDATA_TZ=GMT
  PKEY_COMMON='# pubkey goes here'
  PKEY_ROOT="$PKEY_COMMON"
  PKEY_USER="$PKEY_COMMON"
}

#include x64-common

# overrides

FLASHPAGAN_STRATEGY=conv
