#!/bin/false

function do_portage_fix()
{
  if is_gentoo
  then
    cat >>/etc/portage/make.conf <<'EOF'
FETCHCOMMAND="sudo -g netwild /usr/bin/wget -t 5 -T 60 --passive-ftp -O \"\${DISTDIR}/\${FILE}\" \"\${URI}\""
EOF
  local CORES
  CORES="$(nproc)"
  local CORESP1
  CORESP1="$(( (CORES+1) ))"
  cat >>/etc/portage/make.conf <<EOF
MAKEOPTS="-j${CORESP1}"
EOF
  fi
}
