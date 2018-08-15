#!/bin/false

function do_vlock()
{
  cat >"$(which xflock4)" <<'EOF'
#!/usr/bin/env bash
(
  sudo openvt -s -w -- vlock -a -s
) </dev/null >/tmp/log-vlock 2>&1 & disown
exit 0
EOF
}
