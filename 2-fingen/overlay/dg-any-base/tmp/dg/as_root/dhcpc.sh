#!/bin/false

function do_dhcpc()
{
  local IFACE="$1"
  
  ifconfig "$IFACE" || return 0 # try to work even without ethernet
  
  #if ! ( ifconfig "$IFACE" || true ) | egrep -q 'inet '
  #then
  #  # start trying to bring up the interface, but continue right away
  #  # so we do not block if the network is down
  #  busybox udhcpc -i "$IFACE" </dev/null &>/tmp/dg/stdamp-udhcpc & disown
  #fi
  
  # run even if the interface is already configured, because prior
  # invocations of udhcpc should have been one-shot and the dhcp
  # client needs to keep running to renew the lease from time to time
  rm -f     /tmp/dg/udhcpc.script
  touch     /tmp/dg/udhcpc.script
  chmod a+x /tmp/dg/udhcpc.script
  cat     >>/tmp/dg/udhcpc.script <<'EOF'
#!/usr/bin/env bash

set -o xtrace
set -o errexit
set -o nounset
set -o pipefail
shopt -s failglob
shopt -s nullglob

EOF
  cat     >>/tmp/dg/udhcpc.script <<EOF
IFACE='$IFACE'
EOF
  cat     >>/tmp/dg/udhcpc.script <<'EOF'
if [ "$1" == "deconfig" ]
then
  ifconfig "$IFACE" 0.0.0.0
fi

if [ "$1" == "bound" ] || [ "$1" == "renew" ]
then
  ifconfig "$IFACE" "$ip" netmask "$subnet"
  router="$(echo "$router" | cut -d " " -f 1)"
  route del default || true
  route add default gw "$router"
  ifconfig "$IFACE"
fi
EOF
  chmod a+x /tmp/dg/udhcpc.script
  busybox udhcpc -i "$IFACE" -s /tmp/dg/udhcpc.script </dev/null &>/tmp/dg/stdamp-udhcpc & disown
}
