#!/bin/false

function do_firewall_netwild()
{
  local GID_NETWILD
  GID_NETWILD="$(cat /tmp/dg/vars/gid-netwild)"
  echo netwild:x:"$GID_NETWILD": >>/etc/group
  
  dg_firewall_out netwild
  dg_firewall_sudo_ nft add rule ip filter out_netwild skgid "$GID_NETWILD" counter accept
}
