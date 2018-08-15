#!/bin/false

function usefbdev()
{
  cat >/etc/X11/xorg.conf <<'EOF'
Section "Device"
  Identifier "device0"
  Driver "fbdev"
EndSection
EOF
}

function do_configure_x()
{
  if is_d16 || is_banpi
  then
    usefbdev
  fi
  
  if is_veysp
  then
    # touchpad driver not loaded by udev on veysp
    modprobe elan-i2c
  fi
  
  if is_buildroot
  then
    chmod +s /usr/bin/Xorg
  fi
}
