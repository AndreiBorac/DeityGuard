#!/bin/false

function do_ntpdate()
{
  if which ntpdate
  then
    sudo -g netwild ntpdate -b -p 1 -t 5 time-{a,b,c,d}.nist.gov </dev/null &>/tmp/dg/stdamp-ntpdate & disown
  fi
}
