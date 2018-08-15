#!/bin/false

function do_open_serial_shell()
{
  if mkdir /tmp/dg/did-open-serial-shell
  then
    if [ -c /dev/ttyS0 ]
    then
      bash -i </dev/ttyS0 &>/dev/ttyS0 & disown
    fi
  fi
}
