#!/bin/false

function do_autologin()
{
  function f_gentoo()
  {
    sed -e 's!^c1:12345:respawn:/sbin/agetty 38400 tty1 linux$!c1:12345:respawn:/sbin/agetty -a root --noclear 38400 tty1 linux!' </etc/inittab >/etc/inittab.tmp
    mv /etc/inittab{.tmp,}
    telinit q
    killall -w agetty || true
  }
  function f_buildroot()
  {
    openvt -sw login -f root </dev/tty0 &>/dev/null & disown
  }
  f_"$OS_RELEASE_ID"
  unset f_{gentoo,buildroot}
}
