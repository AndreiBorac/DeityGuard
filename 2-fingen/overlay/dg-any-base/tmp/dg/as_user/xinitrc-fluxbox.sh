#!/bin/false

function do_xinitrc_fluxbox()
{
  which fluxbox || return 0
  
  do_xinitrc_enter
  cat >>~/.xinitrc <<'EOF'
fluxbox
EOF
  do_xinitrc_leave
}
