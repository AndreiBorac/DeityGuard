#!/bin/false

function do_xinitrc_xterm_fullscreen()
{
  which xterm || return 0
  
  do_xinitrc_enter
  cat >>~/.xinitrc <<'EOF'
GEOMETRY="$(xdpyinfo | egrep '^  dimensions:' | egrep -o '[0-9]+x[0-9]+' | head -n 1)"
DPY_W="$(echo "$GEOMETRY" | egrep -o '[0-9]+' | head -n 1)"
DPY_H="$(echo "$GEOMETRY" | egrep -o '[0-9]+' | tail -n 1)"
xterm -geometry $(( (DPY_W/6) ))x$(( (DPY_H/13) )) +vb
EOF
  do_xinitrc_leave
}
