#!/bin/false

function do_xinitrc_enter()
{
  rm -f     ./.xinitrc
  touch     ./.xinitrc
  chmod a+x ./.xinitrc
  cat     >>./.xinitrc <<'EOF'
#!/usr/bin/env bash
(
set -o xtrace
set -o errexit
set -o nounset
set -o pipefail
shopt -s failglob
shopt -s nullglob
EOF
  
  if is_veysp
  then
    cat >>~/.xinitrc <<'EOF'
xinput set-prop 'Elan Touchpad' 'libinput Tapping Enabled' 1
EOF
  fi
  
  cat >>~/.xinitrc <<'EOF'
function f_xinitrc_d()
{
  if [ -d ./.xinitrc.d ]
  then
    local i
    for i in ./.xinitrc.d/*.sh
    do
      . "$i"
    done
  fi
}
f_xinitrc_d
EOF
}

function do_xinitrc_leave()
{
  cat >>~/.xinitrc <<'EOF'
) </dev/null &>/tmp/dg/stdamp-xinitrc
EOF
  
  touch /tmp/dg/vars/startx
}
