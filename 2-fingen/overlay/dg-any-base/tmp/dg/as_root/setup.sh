#!/bin/false

function do_setup_dmifind()
{
  egrep -q "$1" /sys/firmware/dmi/tables/DMI || egrep -q "$1" /sys/firmware/devicetree/base/model
}

function do_setup()
{
  chmod 1777 /tmp/dg
  
  HARDWARE_ID=""
  
  if do_setup_dmifind 'KGPE-D16';          then HARDWARE_ID="d16"   ; fi
  if do_setup_dmifind 'ThinkPad T400';     then HARDWARE_ID="t400"  ; fi
  if do_setup_dmifind 'LeMaker Banana Pi'; then HARDWARE_ID="banpi" ; fi
  if do_setup_dmifind 'Google Speedy';     then HARDWARE_ID="veysp" ; fi
  
  [ -n "$HARDWARE_ID" ]
  
  readonly HARDWARE_ID
  
  function is_t400()  { [ "$HARDWARE_ID" == "t400"  ]; }
  function is_d16()   { [ "$HARDWARE_ID" == "d16"   ]; }
  function is_banpi() { [ "$HARDWARE_ID" == "banpi" ]; }
  function is_veysp() { [ "$HARDWARE_ID" == "veysp" ]; }
  
  is_t400 || is_d16 || is_banpi || is_veysp
  
  OS_RELEASE_ID="$( . /etc/os-release ; echo "$ID" )"
  
  readonly OS_RELEASE_ID
  
  function is_gentoo()    { [ "$OS_RELEASE_ID" == "gentoo"    ]; }
  function is_buildroot() { [ "$OS_RELEASE_ID" == "buildroot" ]; }
  
  is_gentoo || is_buildroot
  
  function if_declared()
  {
    local if_declared_a
    if if_declared_a="$(type -t "$1")"
    then
      if [ "$if_declared_a" == "function" ]
      then
        "$@"
      fi
    fi
  }
  
  (
    declare -p HARDWARE_ID OS_RELEASE_ID | sed -e 's/^declare -r /declare -g -r /'
    declare -f is_{t400,d16,banpi,veysp} is_{gentoo,buildroot}
    declare -f if_declared
  ) >/tmp/dg/setup
}
