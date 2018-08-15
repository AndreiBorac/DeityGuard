#!/bin/false

. /builds/elvopt

function shell_adjust()
{
  [ -z "${SHELL_RESUME_TO+x}" ] # nesting not supported
  set +o xtrace
  #( ( set +o ; shopt -p ) | tr '\n' ' ' ; echo ) >&2
  SHELL_RESUME_TO="$(set +o ; shopt -p)"
  #( echo "SHELL_RESUME_TO=$SHELL_RESUME_TO" | tr '\n' ' ' ; echo ) >&2
  "$@"
  set -o xtrace
}

function shell_resume()
{
  set +o xtrace
  #( echo "SHELL_RESUME_TO=$SHELL_RESUME_TO" | tr '\n' ' ' ; echo ) >&2
  eval "$SHELL_RESUME_TO"
  set -o xtrace
  unset SHELL_RESUME_TO
  #( set +o ; shopt -p ) | tr '\n' ' ' >&2
  set -o errexit
}

mkdir -p /builds/portage
[ -f /builds/portage/original-make.conf ] || cp /etc/portage/make.conf /builds/portage/original-make.conf
cp /builds/portage/original-make.conf /etc/portage/make.conf

function enquote()
{
  echo "$1" | sed -e 's@["$]@\\\0@g'
}
FETCHCOMMANDA='echo "${DISTDIR}" "${FILE}" "${URI}"' # >>/tmp/fetchcommand'
FETCHCOMMANDB='cp /sources/"${FILE}" "${DISTDIR}"/"${FILE}"'
FETCHCOMMANDA="$(enquote "$FETCHCOMMANDA")"
FETCHCOMMANDB="$(enquote "$FETCHCOMMANDB")"
FETCHCOMMANDC="bash -c \"${FETCHCOMMANDA} ; ${FETCHCOMMANDB}\""
echo "FETCHCOMMAND='$FETCHCOMMANDC'" >>/etc/portage/make.conf

for i in /sources/special_portage-*
do
  j="$(echo "$i" | sed -e 's@/sources/special_@@')"
  cp --reflink=auto -vax "$i" /sources/"$j"
done

WHICH_WEBRSYNC="$(which emerge-webrsync)"
cp --reflink=auto -vax "$WHICH_WEBRSYNC" ./
patch -p2 </tmp/patch-portage-pb-b001-emerge-webrsync-1
./emerge-webrsync --verbose --revert="$FAKEDATE"

echo "GMT" >/etc/timezone
emerge --config sys-libs/timezone-data

echo "en_US.UTF-8 UTF-8" >/etc/locale.gen
locale-gen

cat >/etc/env.d/02locale <<'DBLEOF'
LANG="en_US.UTF-8"
LC_COLLATE="C"
DBLEOF

env-update
shell_adjust shopt -u failglob nullglob
# can't source /etc/profile with errexit enabled. some packages install profile scripts that do not expect errexit.
set +o errexit
set +o nounset
source /etc/profile
shell_resume

cat >/etc/conf.d/hostname <<'DBLEOF'
hostname="localhost"
DBLEOF

cat >/etc/conf.d/net <<'DBLEOF'
dns_domain_lo="localnetwork"
DBLEOF

cat >/etc/hosts <<'DBLEOF'
127.0.0.1 localhost
DBLEOF

passwd -d root

if false # old
then
  (
    cd /usr/portage
    
    for i in /tmp/patch-gentoo-pb-b002-*
    do
      patch -p1 <"$i"
    done
    
    for i in net-misc/tightvnc net-libs/nodejs
    do
      ebuild "$(echo ./"$i"/*.ebuild | tr ' ' '\n' | head -n 1)" manifest
    done
  )
fi

(
  rm -rf --one-file-system /usr/local/dg/gentoo-extras
  mkdir -p                 /usr/local/dg/gentoo-extras
  cd                       /usr/local/dg/gentoo-extras
  
  mkdir -p            ./profiles
  echo gentoo-extras >./profiles/repo_name
  
  mkdir -p ./metadata
  cat     >./metadata/layout.conf <<'EOF'
masters = gentoo
auto-sync = false
EOF
  
  patch -p2 </tmp/patch-gentoo-extras
  
  for i in net-misc/tightvnc net-libs/nodejs
  do
    ebuild "$(echo ./"$i"/*.ebuild | tr ' ' '\n' | head -n 1)" manifest
  done
  
  chown -R portage:portage .
  
  mkdir -p /etc/portage/repos.conf
  cat     >/etc/portage/repos.conf/gentoo-extras.conf <<'EOF'
[gentoo-extras]
location = /usr/local/dg/gentoo-extras
EOF
)
