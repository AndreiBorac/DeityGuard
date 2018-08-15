#!/bin/false

function do_timezone()
{
  local TZ
  TZ="$1"
  
  (
    function f_gentoo()
    {
      echo "$TZ" >/etc/timezone
      emerge --config sys-libs/timezone-data
    }
    
    function f_buildroot()
    {
      ln -vsfT /usr/share/zoneinfo/uclibc/"$TZ" /etc/TZ
    }
    
    f_"$OS_RELEASE_ID"
  )
}
