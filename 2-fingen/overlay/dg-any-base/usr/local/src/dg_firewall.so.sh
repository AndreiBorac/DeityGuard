#!/bin/false

# here we do not use 'function' to declare these functions because we
# want this to be compatible with busybox sh also, not just bash

:<<'EOF'
ipt_sudo_()
{
  local ID_U
  ID_U="$(id -u)"
  
  if [ "$ID_U" == "0" ]
  then
    "$@"
  else
    sudo "$@"
  fi
}

ipt_inp()
{
  if ipt_sudo_ iptables -N inp_"$1"
  then
    ipt_sudo_ iptables -A sel_INPUT   -j inp_"$1"
  fi
  
  ipt_sudo_ iptables -F inp_"$1"
}

ipt_fwd()
{
  if ipt_sudo_ iptables -N fwd_"$1"
  then
    ipt_sudo_ iptables -A sel_FORWARD -j fwd_"$1"
  fi
  
  ipt_sudo_ iptables -F fwd_"$1"
}

ipt_out()
{
  if ipt_sudo_ iptables -N out_"$1"
  then
    ipt_sudo_ iptables -A sel_OUTPUT  -j out_"$1"
  fi
  
  ipt_sudo_ iptables -F out_"$1"
}

ipt_inp_tcp_ports()
{
  local NAME="$1"
  shift
  
  ipt_inp "$NAME"
  
  local i
  for i in "$@"
  do
    ipt_sudo_ iptables -A inp_"$NAME" -p TCP --dport "$i" -j ACCEPT
  done
}
EOF

dg_firewall_sudo_()
{
  local ID_U
  ID_U="$(id -u)"
  
  if [ "$ID_U" == "0" ]
  then
    "$@"
  else
    sudo "$@"
  fi
}

dg_firewall_inp()
{
  if dg_firewall_sudo_ nft add   chain ip filter                          inp_"$1"
  then
    dg_firewall_sudo_  nft add   rule  ip filter sel_INPUT   counter jump inp_"$1"
  fi
  
  dg_firewall_sudo_    nft flush chain ip filter                          inp_"$1"
}

dg_firewall_fwd()
{
  if dg_firewall_sudo_ nft add   chain ip filter                          fwd_"$1"
  then
    dg_firewall_sudo_  nft add   rule  ip filter sel_FORWARD counter jump fwd_"$1"
  fi
  
  dg_firewall_sudo_    nft flush chain ip filter                          fwd_"$1"
}

dg_firewall_out()
{
  if dg_firewall_sudo_ nft add   chain ip filter                          out_"$1"
  then
    dg_firewall_sudo_  nft add   rule  ip filter sel_OUTPUT  counter jump out_"$1"
  fi
  
  dg_firewall_sudo_    nft flush chain ip filter                          out_"$1"
}

dg_firewall_inp_tcp_ports()
{
  local NAME="$1"
  shift
  
  dg_firewall_inp "$NAME"
  
  local i
  for i in "$@"
  do
    dg_firewall_sudo_ nft add rule ip filter inp_"$NAME" tcp dport "$i" counter accept
  done
}
