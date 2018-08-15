#!/bin/false

XFCE4_STRATEGY=2

function xf4co_cat()
{
  cat > "$1"
}

function xf4co_catx()
{
  cat > "$1"
  chmod a+x "$1"
}

function xf4co_app()
{
  tee -a "$1" >/dev/null
}

function xf4co_appx()
{
  tee -a "$1" >/dev/null
  chmod a+x "$1"
}

# optionless stuff that should always be executed goes here
# no input
function xf4co_leader()
{
  # disable annoying default autostarts
  for i in bluetooth-applet evolution-alarm-notify gnome-keyring-pkcs11 gnome-keyring-secrets gnome-keyring-ssh gnome-power-manager gnome-volume-control-applet jockey-gtk nm-applet nvidia-autostart polkit-gnome-authentication-agent-1 print-applet pulseaudio ubuntuone-launch update-notifier xfce4-settings-helper-autostart xfce4-tips-autostart zeitgeist-datahub
  do
    mkdir -p .config/autostart
    xf4co_cat .config/autostart/"$i".desktop << 'EOF'
[Desktop Entry]
Hidden=true

EOF
  done
}

# configures custom handler applications ("helpers")
function xf4co_helpers()
{
  while read CATEGORY COMMANDS_SANS_PARAMETER COMMANDS_WITH_PARAMETER
  do
    mkdir -p .local/share/xfce4/helpers
    xf4co_cat .local/share/xfce4/helpers/custom-"$CATEGORY".desktop << EOF
[Desktop Entry]
Version=1.0
Encoding=UTF-8
Name=custom-$CATEGORY
Icon=emblem-noread
NoDisplay=true
Type=X-XFCE-Helper
X-XFCE-Category=$CATEGORY
X-XFCE-Commands=$COMMANDS_SANS_PARAMETER
X-XFCE-CommandsWithParameter=$COMMANDS_WITH_PARAMETER

EOF
    
    mkdir -p .config/xfce4
    xf4co_app .config/xfce4/helpers.rc << EOF
$CATEGORY=custom-$CATEGORY

EOF
  done
}

# configures xfce4-terminal with settings appropriate for programmers
# no input
function xf4co_terminal()
{
  mkdir -p .config/Terminal
  xf4co_cat .config/Terminal/terminalrc << 'EOF'
[Configuration]
MiscAlwaysShowTabs=TRUE
MiscBell=FALSE
MiscBordersDefault=TRUE
MiscCursorBlinks=FALSE
MiscCursorShape=TERMINAL_CURSOR_SHAPE_BLOCK
MiscDefaultGeometry=80x24
MiscInheritGeometry=FALSE
MiscMenubarDefault=TRUE
MiscMouseAutohide=FALSE
MiscToolbarsDefault=FALSE
MiscConfirmClose=TRUE
MiscCycleTabs=TRUE
MiscTabCloseButtons=TRUE
MiscTabCloseMiddleClick=TRUE
MiscTabPosition=GTK_POS_TOP
MiscHighlightUrls=TRUE
ScrollingLines=1000000
ScrollingBar=TERMINAL_SCROLLBAR_LEFT
ScrollingOnOutput=FALSE
TitleMode=TERMINAL_TITLE_REPLACE
CommandUpdateRecords=FALSE
FontName=DejaVu Sans Mono 9
ColorBackground=#ffffffffffff
ColorForeground=#000000000000
ColorCursor=#afaf00000000

EOF
}

# configures the xfce4 desktop environment (most everything goes here)
# expects input
function xf4co_desktop()
{
  mkdir -p .config/autostart
  rm -f .config/autostart/init.sh
  xf4co_app .config/autostart/init.sh << 'EOF'
#!/bin/false

set -x

xset b off
xset m 0 0

# fix -very- annoying tab bug in vnc
xfconf-query -c xfce4-keyboard-shortcuts -p /xfwm4/custom/'<'Super'>'Tab -r

xfconf-query -c xfce4-session -p /general/PromptOnLogout -n -t bool -s false

xfconf-query -c xsettings -p /Net/ThemeName -n -t string -s Xfce-4.6
xfconf-query -c xsettings -p /Xft/DPI -n -t uint -s 96
xfconf-query -c xsettings -p /Xft/HintStyle -n -t string -s hintfull

xfconf-query -c xfwm4 -p /general/click_to_focus -n -t bool -s false
xfconf-query -c xfwm4 -p /general/raise_on_click -n -t bool -s false
xfconf-query -c xfwm4 -p /general/focus_delay -n -t int -s 0
xfconf-query -c xfwm4 -p /general/box_move -n -t bool -s true
xfconf-query -c xfwm4 -p /general/box_resize -n -t bool -s true

EOF
  
  read USE_COMPOSITING
  xf4co_app .config/autostart/init.sh << EOF
xfconf-query -c xfwm4 -p /general/use_compositing -n -t bool -s $USE_COMPOSITING

EOF

  xf4co_app .config/autostart/init.sh << 'EOF'
# 1:R 2:G 3:B (?)
function set_solid_background()
{
  xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitor0/image-show -n -t bool -s false
  xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitor0/color1 -n -t uint -s "$1" -t uint -s "$2" -t uint -s "$3" -t uint -s 65536
}

EOF
  
  read SSB_R SSB_G SSB_B
  
  xf4co_app .config/autostart/init.sh << EOF
set_solid_background $SSB_R $SSB_G $SSB_B

EOF
  
  xf4co_app .config/autostart/init.sh << 'EOF'
#for i in home filesystem trash removable
#do
#  xfconf-query -c xfce4-desktop -p /desktop-icons/file-icons/show-$i -n -t bool -s false
#done

xfconf-query -c xfce4-desktop -p /desktop-icons/style -n -t int -s 0

EOF
  
  if [ "$XFCE4_STRATEGY" == "1" ]
  then
    xf4co_app .config/autostart/init.sh << 'EOF'
sleep 3
xfce4-panel -x
sleep 3

EOF
  fi
  
  if [ "$XFCE4_STRATEGY" == "2" ]
  then
    xf4co_app .config/autostart/init.sh << 'EOF'
echo "... waiting for xfce4-panel to come up ..."
while ! ps -eo uid,pid,cmd | egrep -q '[ ]*'"$UID"'[ ]+[0-9]+[ ]+xfce4-panel'
do
  sleep 0.25
done

echo "... ordering xfce4-panel to quit ..."
sleep 0.25
xfce4-panel -q || true
sleep 0.25

echo "... waiting for xfce4-panel to die ..."
while ps -eo uid,pid,cmd | egrep -q '[ ]*'"$UID"'[ ]+[0-9]+[ ]+xfce4-panel'
do
  echo "... waiting for xfce4-panel to die ..."
  killall xfce4-panel
  sleep 0.25
done

EOF
  fi
  
  if [ "$XFCE4_STRATEGY" == "1" ]
  then
    xf4co_app .config/autostart/init.sh << 'EOF'
# 1:id 2:name 3:desc 4:icon 5:in_terminal 6:exec
function new_panel_launcher()
{
  cat > .config/xfce4/panel/launcher-"$1".rc << DBLEOF
[Global]
MoveFirst=false
ArrowPosition=0

[Entry 0]
Name=$2
Icon=$4
Exec=$6
Terminal=$5
StartupNotify=false

DBLEOF
}

EOF
    
    X=200
    
    while read V_NAME V_DESC V_ICON V_PATH V_TERM V_WAIT V_EXEC
    do
      X="$((X+1))"
      I="$X"
      xf4co_app .config/autostart/init.sh << EOF
new_panel_launcher $I $V_NAME $V_DESC $V_ICON $V_TERM "$V_EXEC"

EOF
    done
    
    MAX_ID_LAUNCHER="$X"
    
    for X in `seq 301 320`
    do
      xf4co_app .config/autostart/init.sh << EOF
cat > .config/xfce4/panel/separator-$X.rc << 'DBLEOF'
separator-type=2

DBLEOF

EOF
    done
    
    xf4co_app .config/autostart/init.sh << 'EOF'
cat > .config/xfce4/panel/xfce4-menu-101.rc << 'DBLEOF'
use_default_menu=true
menu_file=
icon_file=/usr/share/pixmaps/xfce4_xicon1.png
show_menu_icons=true
button_title=Xfce Menu
show_button_title=false

DBLEOF

cat > .config/xfce4/panel/tasklist-104.rc << 'DBLEOF'
grouping=1
width=300
all_workspaces=false
expand=true
flat_buttons=true
show_handles=true
fixed_width=false

DBLEOF

cat > .config/xfce4/panel/systray-105.rc << 'DBLEOF'
[Global]
ShowFrame=false
Rows=1

DBLEOF

cat > .config/xfce4/panel/pager-106.rc << 'DBLEOF'
rows=1
scrolling=true
show-names=false

DBLEOF

cat > .config/xfce4/panel/clock-108.rc << 'DBLEOF'
DigitalFormat=%R
TooltipFormat=%A %d %B %Y
ClockType=2
ShowFrame=false
ShowSeconds=false
ShowMilitary=true
ShowMeridiem=false
TrueBinary=false
FlashSeparators=false

DBLEOF

cat > .config/xfce4/panel/panels.xml << 'DBLEOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE config SYSTEM "config.dtd">
<panels>
  <panel>
    <properties>
      <property name="size" value="32"/>
      <property name="monitor" value="0"/>
      <property name="screen-position" value="11"/>
      <property name="fullwidth" value="1"/>
      <property name="xoffset" value="0"/>
      <property name="yoffset" value="1166"/>
      <property name="handlestyle" value="0"/>
      <property name="autohide" value="0"/>
      <property name="transparency" value="20"/>
      <property name="activetrans" value="0"/>
    </properties>
    <items>
      <item name="xfce4-menu" id="101"/>
      <item name="tasklist" id="104"/>
      <item name="systray" id="105"/>
      <item name="pager" id="106"/>
      <item name="clock" id="108"/>
EOF
    
    X=200
    
    while [ "$((X<MAX_ID_LAUNCHER))" == "1" ]
    do
      X="$((X+1))"
      I="$X"
      
      xf4co_app .config/autostart/init.sh << EOF
      <item name="launcher" id="$X"/>
EOF
    done
    
    xf4co_app .config/autostart/init.sh << EOF
    </items>
  </panel>
</panels>

DBLEOF

xfce4-panel -r </dev/null &>/dev/null &

# fix -very- annoying tab bug in vnc
xfconf-query -c xfce4-keyboard-shortcuts -p /xfwm4/custom/'<'Super'>'Tab -r

EOF
  fi
  
  if [ "$XFCE4_STRATEGY" == "2" ]
  then
    mkdir -p .config/xfce4/xfconf/xfce-perchannel-xml
    xf4co_cat .config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>

<channel name="xfce4-panel" version="1.0">
  <property name="panels" type="uint" value="1">
    <property name="panel-0" type="empty"/>
  </property>
</channel>
EOF
    
    xf4co_app .config/autostart/init.sh << EOF

xfconf-query -c xfce4-panel -r -R -p /

xfconf-query -c xfce4-panel -p /panels -n -t uint -s 1

xfconf-query -c xfce4-panel -p /panels/panel-0/position -n -t string -s "p=6;x=960;y=17"
xfconf-query -c xfce4-panel -p /panels/panel-0/length -n -t uint -s 100
xfconf-query -c xfce4-panel -p /panels/panel-0/position-locked -n -t bool -s true
xfconf-query -c xfce4-panel -p /panels/panel-0/plugin-ids -n -t int -s 1 -t int -s 2 -t int -s 3 -t int -s 4 -t int -s 5 -t int -s 6 -t int -s 7 -t int -s 8 -t int -s 9 -t int -s 10 -t int -s 11 -t int -s 12 -t int -s 13 -t int -s 14 -t int -s 15 -t int -s 16 -t int -s 17 -t int -s 18 -t int -s 19 -t int -s 20
xfconf-query -c xfce4-panel -p /panels/panel-0/size -n -t uint -s 32
xfconf-query -c xfce4-panel -p /panels/panel-0/length-adjust -n -t bool -s false

xfconf-query -c xfce4-panel -p /plugins/plugin-1 -n -t string -s applicationsmenu
xfconf-query -c xfce4-panel -p /plugins/plugin-1/show-button-title -n -t bool -s false
xfconf-query -c xfce4-panel -p /plugins/plugin-2 -n -t string -s tasklist
xfconf-query -c xfce4-panel -p /plugins/plugin-3 -n -t string -s separator
xfconf-query -c xfce4-panel -p /plugins/plugin-3/expand -n -t bool -s true
xfconf-query -c xfce4-panel -p /plugins/plugin-3/style -n -t uint -s 0
xfconf-query -c xfce4-panel -p /plugins/plugin-4 -n -t string -s systray
xfconf-query -c xfce4-panel -p /plugins/plugin-5 -n -t string -s pager
xfconf-query -c xfce4-panel -p /plugins/plugin-6 -n -t string -s clock

EOF
    
    X=7
    
    while read L_NAME L_DESC L_ICON L_PATH L_TERM L_WAIT L_EXEC
    do
      if [ "$L_PATH" == "~" ]
      then
        L_PATH="$HOME"
      fi
      
      mkdir -p .config/xfce4/panel/launcher-"$X"
      xf4co_cat .config/xfce4/panel/launcher-"$X"/12345678901.desktop << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=$L_NAME
Comment=$L_DESC
Icon=$L_ICON
Exec=$L_EXEC
Path=$L_PATH
Terminal=$L_TERM
StartupNotify=$L_WAIT

EOF
      xf4co_app .config/autostart/init.sh << EOF
xfconf-query -c xfce4-panel -p /plugins/plugin-"$X" -n -t string -s launcher
xfconf-query -c xfce4-panel -p /plugins/plugin-"$X"/items -a -n -t string -s 12345678901.desktop

EOF
      
      X="$((X+1))"
    done
    
    xf4co_app .config/autostart/init.sh << 'EOF'

xfce4-panel </dev/null >/dev/null 2>&1 &
disown

# fix -very- annoying tab bug in vnc
xfconf-query -c xfce4-keyboard-shortcuts -p /xfwm4/custom/'<'Super'>'Tab -r

EOF
  fi
  
  xf4co_catx .config/autostart/init0.sh << 'EOF'
#!/bin/sh
cd ~
bash .config/autostart/init.sh > .init.sh.log 2>&1
EOF
  
  cat > .config/autostart/init0.sh.desktop << EOF
[Desktop Entry]
Type=Application
Exec=$HOME/.config/autostart/init0.sh
Hidden=False
Terminal=False
StartupNotify=False
Version=0.9.4
Encoding=UTF-8
Name=init.sh

EOF
}

function do_xinitrc_xfce4()
{
  which xfce4-session || return 0
  
  xf4co_leader
  xf4co_helpers <<'EOF'
TerminalEmulator /usr/bin/xfce4-terminal /usr/bin/xfce4-terminal -e "%s"
WebBrowser /bin/true /bin/true "%s"
MailReader /bin/true /bin/true "%s"
EOF
  xf4co_terminal
  
  cat >>/tmp/xf4co_desktop <<'EOF'
false
20480 10240 0
EOF
  
  # launcher syntax: V_NAME V_DESC V_ICON V_PATH V_TERM V_WAIT V_EXEC
  
  if which firefox
  then
    sudo tee /usr/local/bin/dg-firefox <<'EOF'
#!/usr/bin/env bash

set -o xtrace
set -o errexit
set -o nounset
set -o pipefail
shopt -s failglob
shopt -s nullglob

USERJS_VER=31ec621d3f6442890081530b6366171775075449
USERJS_SHA=54eaae76048b8f1bbd84918144c56e8cfc39bb2895d3d5825ba0ebf053f856d2

tdir="$(mktemp -d)"
cd "$tdir"
mkdir ./tmp
sudo mount -t tmpfs none ./tmp
cd ./tmp

(
  sudo -g netwild wget -O./user.js https://raw.githubusercontent.com/ghacksuserjs/ghacks-user.js/"$USERJS_VER"/user.js
  
  x_sha="$(sha256sum ./user.js | cut -d " " -f 1)"
  
  [ "$x_sha" == "$USERJS_SHA" ]
)

mkdir -p ./.mozilla/firefox/default.default

cat >./.mozilla/firefox/profiles.ini <<'DBLEOF'
[General]
StartWithLastProfile=1

[Profile0]
Name=default
IsRelative=1
Path=default.default
Default=1
DBLEOF

sed \
  -e 's/^user_pref("network.cookie.cookieBehavior", 2);$/user_pref("network.cookie.cookieBehavior", 1);/' \
  <./user.js >./.mozilla/firefox/default.default/prefs.js

ln -vsfT ~ ./home

for i in Desktop Documents Downloads Music Pictures Public Templates Videos
do
  if [ -d ~/"$i" ]
  then
    ln -vsft ./ ~/"$i"
  fi
done

sudo -g netwild env HOME="$PWD" firefox --private --no-remote

cd ./..

sudo umount ./tmp
rmdir ./tmp

cd ./..

rmdir "$tdir"
EOF
    sudo chmod a+x /usr/local/bin/dg-firefox
    cat >>/tmp/xf4co_desktop <<'EOF'
firefox firefox firefox ~ false false dg-firefox
EOF
  fi
  
  if which chromium-browser
  then
    sudo tee /usr/local/bin/dg-chromium-browser <<'EOF'
#!/usr/bin/env bash
exec sudo -g netwild chromium-browser --incognito
EOF
    sudo chmod a+x /usr/local/bin/dg-chromium-browser
    cat >>/tmp/xf4co_desktop <<'EOF'
chromium chromium chromium-browser ~ false false dg-chromium-browser
EOF
  fi
  
  cat >>/tmp/xf4co_desktop <<'EOF'
xfce4-terminal xfce4-terminal utilities-terminal ~ false false xfce4-terminal
EOF
  
  cat >>/tmp/xf4co_desktop <<'EOF'
xflock4 xflock4 changes-prevent ~ false false xflock4
EOF
  
  xf4co_desktop </tmp/xf4co_desktop
  
  do_xinitrc_enter
  cat >>./.xinitrc <<EOF
exec xfce4-session
EOF
  do_xinitrc_leave
}
