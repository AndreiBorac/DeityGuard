#!/bin/false

function cross_compile_setup()
{
  local i
  for i in /builds/brarm-output-"$ARMVER"/host/usr/bin/arm-linux-*
  do
    local j
    j="$(echo "$i" | sed -e 's@^/builds/brarm-output-'"$ARMVER"'/host/usr/bin/arm-linux-@@')"
    cat >/tmp/cross_compile-"$j" <<EOF
#!/usr/bin/env bash
export PATH="/builds/brarm-output-$ARMVER/host/usr/bin:\$PATH"
exec arm-linux-$j "\$@"
EOF
    cat /tmp/cross_compile-"$j"
    chmod a+x /tmp/cross_compile-"$j"
  done
}

cross_compile_setup
