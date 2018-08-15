#!/bin/false

set -o xtrace
set -o errexit
set -o nounset
set -o pipefail
shopt -s failglob || true
shopt -s nullglob || true

. /classical-insert-variables

# limit ./classical to 16m at first so we can't be tricked into resource exhaustion
mkdir -p ./classical
mount -t tmpfs none ./classical
mount -t tmpfs -o remount,size=16m none ./classical

check_checksum()
{
  VALID=n
  
  if [ "$(sha256sum "$1" | cut -d " " -f 1)" == "$2" ]
  then
    VALID=y
  else
    if false # if true, drop to shell on checksum failure
    then
      sh -i
    fi
  fi
}

check_signature()
{
  [ -f ./classical/manifest.lst.txt ]
  [ -f ./classical/manifest.sig.txt ]
  [ -f ./classical/manifest.pub.txt ]
  
  check_checksum ./classical/manifest.pub.txt "$CLASSICAL_INSERT_PKEY_AUTH"
  [ "$VALID" == "y" ] || return 0
  VALID=n
  
  if gpgv2 --keyring ./classical/manifest.pub.txt ./classical/manifest.sig.txt ./classical/manifest.lst.txt
  then
    VALID=y
  fi
}

offer()
{
  ACCEPTED=n
  
  # "parse" manifest
  MANIFEST_NR=
  STAGE2_CSUM=
  STAGE2_SIZE=
  STAGE2_DATE=
  STAGE2_DNS_HOST=
  STAGE2_HTTP_PORT=
  STAGE2_HTTP_HOST=
  STAGE2_HTTP_PATH=
  manifestly()
  {
    MANIFEST_NR="$1"
    
    if [ "$2" == "$MACHINE_NAME" ]
    then
      STAGE2_CSUM="$3"
      STAGE2_SIZE="$4"
      STAGE2_DATE="$5"
      STAGE2_DNS_HOST="$6"
      STAGE2_HTTP_PORT="$7"
      STAGE2_HTTP_HOST="$8"
      STAGE2_HTTP_PATH="$9"
    fi
  }
  # disable tracing while loading the manifest as it causes potentially lots of useless output
  set +o xtrace
  . ./classical/manifest.lst.txt
  set -o xtrace
  
  [ -n "$MANIFEST_NR" ]
  [ -n "$STAGE2_CSUM" ]
  [ -n "$STAGE2_SIZE" ]
  [ -n "$STAGE2_DATE" ]
  [ -n "$STAGE2_DNS_HOST" ]
  [ -n "$STAGE2_HTTP_PORT" ]
  [ -n "$STAGE2_HTTP_HOST" ]
  [ -n "$STAGE2_HTTP_PATH" ]
  
  # disable kernel messages to console
  cat /proc/sys/kernel/printk | tee /tmp/saved_printk
  echo 0 | tee /proc/sys/kernel/printk
  
  # clear screen (unless debugging)
  if [ "$DEBUG_MODEL" != "y" ]
  then
    set +o xtrace
    clear
  fi
  
  # clear input
  while IFS= read -r -s -t 1; do true; done
  REPLY=""
  
  # display info
  echo "===== INFO ====="
  echo "MANIFEST_NR: ${MANIFEST_NR}"
  echo "STAGE2_CSUM: ${STAGE2_CSUM}"
  echo "STAGE2_SIZE: ${STAGE2_SIZE}"
  echo "STAGE2_DATE: ${STAGE2_DATE}"
  echo "STAGE2_FROM: ${STAGE2_DNS_HOST}:${STAGE2_HTTP_PORT}:${STAGE2_HTTP_HOST}:${STAGE2_HTTP_PATH}"
  
  # prompt user
  if [ "$CLASSICAL_INSERT_BYPASS" != "y" ]
  then
    IFS= read -r -p "[$1] boot this? (y/q/N) "
  else
    # if the bypass is set, fake an accept
    REPLY=y
  fi
  
  # restore kernel messages to console
  cat /tmp/saved_printk | tee /proc/sys/kernel/printk
  
  if [ "$REPLY" == "y" ]
  then
    ACCEPTED=y
  fi
  
  if [ "$REPLY" == "q" ]
  then
    echo "!! bye"
    exit 1
  fi
  
  # re-enable tracing
  set -o xtrace
  
  mount -o remount,size="$(( (STAGE2_SIZE+(16*(1024**2))) ))" none ./classical
}

attempt()
{
  check_checksum ./classical/stage2.bin "$STAGE2_CSUM"
  [ "$VALID" == "y" ] || return 0
  chmod a+x      ./classical/stage2.bin
  exec           ./classical/stage2.bin
  exit 1
}

# checks that the argument is not the empty string and has fewer than
# 20 digits, so it can reasonably be subjected to bash arithmancy
valid()
{
  local X
  X="$1"
  
  VALID=n
  
  if [ -n "$X" ] && [ "$(( (${#X} < 20) ))" == "1" ]
  then
    VALID=y
  fi
}

try_clean()
{
  rm -f ./classical/manifest.lst.txt ./classical/manifest.sig.txt ./classical/manifest.pub.txt ./classical/stage2.bin
}

try_drive()
{
  try_clean
  
  local SIZ_SG_PL_INI
  SIZ_SG_PL_INI="$(stat -c %s ./sg_pl_ini)"
  
  local OFF
  OFF="$(( (COMMON_CACHE_PARTITION_OFFSET + COMMON_CACHE_PARTITION_CLEAR_ZONE + SIZ_SG_PL_INI) ))"
  
  dd_ if="$1" of=/tmp/scan_data skip="$OFF" count=4096 || return 0
  OFF="$(( (OFF+4096) ))"
  ( /builds_tools/safepipe 09 " " </tmp/scan_data ; echo ) >/tmp/scan
  read SZ_MANIFEST_LST_TXT SZ_MANIFEST_SIG_TXT SZ_MANIFEST_PUB_TXT SZ_STAGE2_BIN IGNORED </tmp/scan
  valid "$SZ_MANIFEST_LST_TXT"
  [ "$VALID" == "y" ] || return 0
  valid "$SZ_MANIFEST_SIG_TXT"
  [ "$VALID" == "y" ] || return 0
  valid "$SZ_MANIFEST_PUB_TXT"
  [ "$VALID" == "y" ] || return 0
  valid "$SZ_STAGE2_BIN"
  [ "$VALID" == "y" ] || return 0
  
  if [ "$(( SZ_MANIFEST_PUB_TXT <= CLASSICAL_INSERT_PKEY_MAXL ))" != "1" ]
  then
    return 0
  fi
  
  if [ "$(( (SZ_MANIFEST_LST_TXT + SZ_MANIFEST_SIG_TXT + SZ_MANIFEST_PUB_TXT) < (8*(1024**2)) ))" != "1" ]
  then
    return 0
  fi
  
  dd_ if="$1" of=./classical/manifest.lst.txt skip="$OFF" count="$SZ_MANIFEST_LST_TXT" || return 0
  OFF="$(( (OFF+SZ_MANIFEST_LST_TXT) ))"
  
  dd_ if="$1" of=./classical/manifest.sig.txt skip="$OFF" count="$SZ_MANIFEST_SIG_TXT" || return 0
  OFF="$(( (OFF+SZ_MANIFEST_SIG_TXT) ))"
  
  dd_ if="$1" of=./classical/manifest.pub.txt skip="$OFF" count="$SZ_MANIFEST_PUB_TXT" || return 0
  OFF="$(( (OFF+SZ_MANIFEST_PUB_TXT) ))"
  
  check_signature
  [ "$VALID" == "y" ] || return 0
  
  offer "$1"
  [ "$ACCEPTED" == "y" ] || return 0
  
  dd_ if="$1" of=./classical/stage2.bin skip="$OFF" count="$SZ_STAGE2_BIN" || return 0
  OFF="$(( (OFF+SZ_STAGE2_BIN) ))"
  
  attempt
}

try_each_drive()
{
  for i in $CLASSICAL_INSERT_PROBE
  do
    if [ -b "$i" ]
    then
      try_drive "$i"
    fi
  done
}

# before doing anything else, run fixes

emmc_probe_workaround()
{
  emmc_probe_status
  
  if [ "$EMMC_PROBE_GOOD" != "y" ]
  then
    # huh. cannot reproduce a probe fail in classical-insert.
    echo b >/proc/sysrq-trigger
    reboot -f
    false
  fi
}

fixes()
{
  if [ "$CLASSICAL_INSERT_EMMC_PROBE_WORKAROUND" == "y" ]
  then
    emmc_probe_workaround
  fi
}

fixes

# now, first thing we have to do is attempt a non-networked drive
# load. only if that fails (or the user rejects), we fall through to
# bringing up the network. but only if we're not debugging. if we're
# debugging, don't do this and allow network boot to be tried first.

if [ "$DEBUG_MODEL" != "y" ]
then
  try_each_drive
fi

# the network might not be up if we just did a disk boot.
eth_bring_up_if_down "$CLASSICAL_INSERT_ETHERNET_INTERFACE"

classical_resolve

try_network()
{
  try_clean
  
  classical_geturl manifest.lst.txt
  classical_geturl manifest.sig.txt
  classical_geturl manifest.pub.txt
  
  check_signature
  [ "$VALID" == "y" ] || return 0
  
  offer "$CLASSICAL_INSERT_ETHERNET_INTERFACE"
  [ "$ACCEPTED" == "y" ] || return 0
  
  (
    CLASSICAL_INSERT_DNS_HOST="$STAGE2_DNS_HOST"
    CLASSICAL_INSERT_HTTP_PORT="$STAGE2_HTTP_PORT"
    CLASSICAL_INSERT_HTTP_HOST="$STAGE2_HTTP_HOST"
    CLASSICAL_INSERT_HTTP_PATH="$STAGE2_HTTP_PATH"
    classical_resolve
    classical_geturl stage2.bin-"$STAGE2_CSUM".bin
    mv ./classical/stage2.bin-"$STAGE2_CSUM".bin ./classical/stage2.bin
  )
  
  attempt
}

while [ 1 ]
do
  try_network
  
  # clear input
  while IFS= read -r -s -t 1; do true; done
  REPLY=""
  
  if [ "$DEBUG_MODEL" != "y" ]
  then
    set +o xtrace
    clear
  fi
  
  echo "!! all methods exhausted"
  
  # prompt user
  IFS= read -r -p "try again? (q/Y) "
  
  if [ "$REPLY" == "q" ]
  then
    echo "!! bye"
    exit 1
  fi
  
  # re-enable tracing
  set -o xtrace
  
  try_each_drive
done
