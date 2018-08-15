#!/bin/false

function do_sshd_pkey_user()
{
  if [ -n "$1" ]
  then
    mkdir -p   ~/.ssh
    echo "$1" >~/.ssh/authorized_keys2
  fi
}
