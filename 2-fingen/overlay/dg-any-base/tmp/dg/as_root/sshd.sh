#!/bin/false

function do_sshd()
{
  # if there is a supplied host key, on arm, the host key is supplied
  # by supplementing the overlay in the initramfs building phase. this
  # can't be done for x64 because the overlay is in stage2 and the
  # private part of the host key could not be kept confidential that
  # way.
  
  if [ -d /tmp/dg/initramfs/ssh-host-key ]
  then
    local PFIX
    PFIX=/tmp/dg/initramfs/ssh-host-key/ssh_host_ed25519_key
    
    if [ -f "$PFIX" ] && [ -f "$PFIX".pub ]
    then
      cp "$PFIX"{,.pub} /etc/ssh/
    fi
    
    chmod 0400 /etc/ssh/ssh_host_*_key{,.pub}
    
    function f_gentoo() { rc-service sshd start ;}
    function f_buildroot() { /etc/init.d/_no_auto_start_sshd start ;}
    f_"$OS_RELEASE_ID"
    unset f_{gentoo,buildroot}
  fi
  
  dg_firewall_inp_tcp_ports sshd 22
}

function do_sshd_pkey_root()
{
  if [ -n "$1" ]
  then
    mkdir -p   /root/.ssh
    echo "$1" >/root/.ssh/authorized_keys2
  fi
}
