FINHUB_VARSET=global

#include model-t400
#include fetch-global

function f_defs()
{
  ROOTSHADOW='*'
  TZDATA_TZ=GMT
  PKEY_COMMON=
  PKEY_ROOT="$PKEY_COMMON"
  PKEY_USER="$PKEY_COMMON"
}

#include x64-common

MANAGE_SSH_HOST_KEY=n

# be conservative
FLASHPAGAN_STRATEGY=conv
FLASHPAGAN_SPI_SPEED_HZ=5000000

if [ "$DEBUG_MODEL" == "y" ]
then
  LINUX_CMDLINE="console=ttyS0,115200n8"
  SERIAL_CONSOLE=y
fi
