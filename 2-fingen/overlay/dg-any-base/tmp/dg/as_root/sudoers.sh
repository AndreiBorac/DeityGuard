#!/bin/false

function do_sudoers()
{
  cat >/etc/sudoers <<'EOF'
# try to emulate Debian/Ubuntu way of doing things
Defaults env_reset
Defaults secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

root   ALL=(ALL:ALL) NOPASSWD: ALL
user   ALL=(ALL:ALL) NOPASSWD: ALL
%wheel ALL=(ALL:ALL) NOPASSWD: ALL
EOF
  
  if is_gentoo
  then
    cat >>/etc/sudoers <<'EOF'
portage ALL=(portage:netwild) NOPASSWD: ALL
EOF
  fi
}
