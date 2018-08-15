MACHINE_NAME=test_d16

FINHUB_VARSET=test

#include model-d16.4
#include fetch-local

FANMAN_CELSIUS_LO=40000
FANMAN_CELSIUS_HI=65000

FANMAN_PWM_IDLE=100
FANMAN_PWM_FULL=200

function f_defs()
{
  ROOTSHADOW='*'
  TZDATA_TZ=GMT
  PKEY_COMMON='# pubkey goes here'
  PKEY_ROOT="$PKEY_COMMON"
  PKEY_USER="$PKEY_COMMON"
}

#include x64-common
