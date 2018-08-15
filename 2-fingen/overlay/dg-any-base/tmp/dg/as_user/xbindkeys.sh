#!/bin/false

function do_xbindkeys()
{
  if is_veysp && which xbindkeys && which xdotool
  then
    mkdir -p  ./.xbindkeys.in
    
    touch     ./.xbindkeys.in/alt-up.sh
    chmod a+x ./.xbindkeys.in/alt-up.sh
    cat      >./.xbindkeys.in/alt-up.sh <<'EOF'
#!/bin/sh

if WINNAME="$(xdotool getactivewindow getwindowname)"
then
  if [ "$WINNAME" == "xterm" ] || [ "$WINNAME" == "LXTerminal" ]
  then
    xdotool keyup Up   keyup Alt keydown Shift key Prior keyup Shift keydown Alt
    exit
  fi
fi

xdotool     keyup Up   keyup Alt               key Prior             keydown Alt
EOF
    
    touch     ./.xbindkeys.in/alt-down.sh
    chmod a+x ./.xbindkeys.in/alt-down.sh
    cat      >./.xbindkeys.in/alt-down.sh <<'EOF'
#!/bin/sh

if WINNAME="$(xdotool getactivewindow getwindowname)"
then
  if [ "$WINNAME" == "xterm" ] || [ "$WINNAME" == "LXTerminal" ]
  then
    xdotool keyup Down keyup Alt keydown Shift key Next  keyup Shift keydown Alt
    exit
  fi
fi

xdotool     keyup Down keyup Alt               key Next              keydown Alt
EOF
    
    touch     ./.xbindkeys.in/ctrl-alt-m.sh
    chmod a+x ./.xbindkeys.in/ctrl-alt-m.sh
    cat      >./.xbindkeys.in/ctrl-alt-m.sh <<'EOF'
#!/bin/sh

TMPFIL="$(mktemp)"

xinput list-props 'Elan Touchpad' >"$TMPFIL"

NEXTV=1

if egrep -q '^'$'\t''Device Enabled \([0-9]+\):'$'\t'1'$' "$TMPFIL"
then
  NEXTV=0
fi

xinput set-prop 'Elan Touchpad' 'Device Enabled' "$NEXTV"

rm -f "$TMPFIL"
EOF
    
    cat >./.xbindkeysrc <<'EOF'
"~/.xbindkeys.in/alt-up.sh"
    Alt + Up

"~/.xbindkeys.in/alt-down.sh"
    Alt + Down

"~/.xbindkeys.in/ctrl-alt-m.sh"
    Control+Alt + m
EOF
    
    mkdir -p ./.xinitrc.d
    cat     >./.xinitrc.d/xbindkeys.sh <<'EOF'
xbindkeys &
EOF
  fi
}
