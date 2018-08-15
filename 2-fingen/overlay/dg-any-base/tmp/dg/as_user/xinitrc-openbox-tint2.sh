#!/bin/false

function do_xinitrc_openbox_tint2()
{
  which openbox || return 0
  which tint2   || return 0
  
  cat /.live/ror/etc/xdg/tint2/tint2rc | egrep -v '^launcher_item_app' >./.tint2rc
  echo 'launcher_apps_dir = ~/.tint2la' >>./.tint2rc
  echo 'panel_position = top center horizontal' >>./.tint2rc
  
  local TERMPROG
  TERMPROG=xterm
  if which lxterminal
  then
    TERMPROG=lxterminal
    mkdir -p ./.config/lxterminal
    cat     >./.config/lxterminal/lxterminal.conf <<'EOF'
[general]
fontname=DejaVu Sans Mono 9
bgcolor=#ffffffffffff
fgcolor=#000000000000
EOF
  fi
  
  if which leafpad
  then
    mkdir -p ./.config/leafpad
    cat     >./.config/leafpad/leafpadrc <<'EOF'
0.8.18.1
600
400
DejaVu Sans Mono 9
0
0
0
EOF
  fi
  
  mkdir -p ~/.tint2la
  cat     >./.tint2la/001-"$TERMPROG".desktop <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=$TERMPROG
Comment=$TERMPROG
#Icon=/usr/share/tint2/default_icon.png
Icon=/usr/share/icons/Adwaita/24x24/apps/utilities-terminal.png
Exec=$TERMPROG
Path=~
Terminal=false
StartupNotify=false
EOF
  
  if which dillo
  then
    cat   >./.tint2la/002-dillo.desktop <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=dillo
Comment=dillo
Icon=/usr/share/icons/Adwaita/24x24/apps/web-browser.png
Exec=sudo -g netwild dillo
Path=~
Terminal=false
StartupNotify=false
EOF
  fi
  
  do_xinitrc_enter
  cat >>~/.xinitrc <<'EOF'
xrdb -merge <<'DBLEOF'
Xft.autohint: 0
Xft.antialias: 1
Xft.hinting: true
Xft.hintstyle: hintfull
Xft.dpi: 96
Xft.rgba: rgb
Xft.lcdfilter: lcddefault
DBLEOF
mkdir -p ./.config/fontconfig
cat     >./.config/fontconfig/fonts.conf <<'DBLEOF'
<?xml version='1.0'?>
<!DOCTYPE fontconfig SYSTEM 'fonts.dtd'>
<fontconfig>
 <match target="font">
  <edit mode="assign" name="rgba">
   <const>rgb</const>
  </edit>
  <edit mode="assign" name="hinting">
   <bool>true</bool>
  </edit>
  <edit mode="assign" name="hintstyle">
   <const>hintfull</const>
  </edit>
  <edit mode="assign" name="antialias">
   <bool>true</bool>
  </edit>
  <edit mode="assign" name="lcdfilter">
    <const>lcddefault</const>
  </edit>
 </match>
</fontconfig>
DBLEOF
openbox &
xsetroot -solid '#'502800
tint2 -c ./.tint2rc
EOF
  do_xinitrc_leave
}
