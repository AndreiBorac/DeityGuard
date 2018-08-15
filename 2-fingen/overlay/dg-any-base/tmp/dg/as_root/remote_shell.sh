#!/bin/false

function do_remote_shell()
{
  ipt_inp_tcp_ports rsh "$REMOTE_SHELL_PORT"
  
  socat -t1000000 OPENSSL-LISTEN:"$REMOTE_SHELL_PORT",pf=ip4,reuseaddr,fork,cert=/tmp/dg/kp/"$REMOTE_SHELL_KEY"_server.pem,cafile=/tmp/dg/kp/"$REMOTE_SHELL_KEY"_client.crt EXEC:'env -i bash --norc --noprofile' </dev/null &>/tmp/dg/stdamp-rsh-socat & disown
}
