#!/bin/false

set -o xtrace
set -o errexit
set -o nounset
set -o pipefail
shopt -s failglob
shopt -s nullglob

(
  env
  
                bash /tmp/dg/rc_local_inner.sh root
  su - user -c "bash /tmp/dg/rc_local_inner.sh user"
  
  # the presence of a /tmp/dg/vars/startx file is used as a signal
  # that something configured a meaningful X session which we should
  # try to start here. also, don't try to start X if there is no
  # startx program.
  if which startx
  then
    if [ -f /tmp/dg/vars/startx ]
    then
      openvt -sw -- su - user -c 'env -i USER="$USER" HOME="$HOME" SHELL="$SHELL" bash -l -c "( set -o xtrace ; env ; startx )" &>/tmp/dg/stdamp-startx-inner' </dev/null &>/tmp/dg/stdamp-startx & disown
    fi
  fi
  
  echo '+OK (rc_local.sh)'
) </dev/null &>/tmp/dg/stdamp-rc_local.sh & disown
