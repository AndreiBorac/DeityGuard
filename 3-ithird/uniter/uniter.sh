#!/usr/bin/env bash

set -o xtrace
set -o errexit
set -o nounset
set -o pipefail
shopt -s failglob
shopt -s nullglob

which debootstrap

if [ "$(id -u)" != "0" ]
then
  exec sudo ./uniter.sh "$@"
fi

function umount_()
{
  while mountpoint -q "$1"
  do
    umount "$1"
  done
}

if [ ! -d             ./local/offload/artful ]
then
  debootstrap artful  ./local/offload/artful
fi

if ! mountpoint -q    ./local/offload/artful/tmp
then
  mount -t tmpfs none ./local/offload/artful/tmp
fi

if ! mountpoint -q    ./local/offload/artful/proc
then
  mount --bind /proc  ./local/offload/artful/proc
fi

# ruby is required for bootstrapping

tee                   ./local/offload/artful/tmp/pkgs <<'EOF'
ruby haveged lzop meld xorriso vlock
EOF

tee                   ./local/offload/artful/tmp/script <<'EOF'

set -o xtrace
set -o errexit
set -o nounset
set -o pipefail
shopt -s failglob
shopt -s nullglob

cat >/etc/apt/sources.list <<'DBLEOF'
deb http://archive.ubuntu.com/ubuntu/  artful          main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu/ artful-security main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/  artful-updates  main restricted universe multiverse
DBLEOF

export LC_ALL=C

if [ ! -f /var/cache/apt/last_update ] || [[ "$(date --rfc-3339=ns -r /var/cache/apt/last_update)" < "$(date --rfc-3339=ns --date '30 minutes ago')" ]]
then
  apt-get update
  touch   /var/cache/apt/last_update
fi

apt-get -y -d upgrade
apt-get -y -d install $(cat /tmp/pkgs)

EOF

chroot                ./local/offload/artful bash /tmp/script

umount_               ./local/offload/artful/tmp
umount_               ./local/offload/artful/proc

function cp_rs()
{
  local from="$1"
  local dest="$2"
  
  mkdir -p ./local/offload/"$hostname"/dir/"$dest"
  RL="$(readlink -f "$from")"
  (     cd ./local/offload/"$hostname"/dir/"$dest" ; cp -rs "$RL" ./ )
}

function host_ubuntu()
{
  local hostname
  hostname="$1"
  
  umount_             ./local/offload/"$hostname"
  mkdir -p            ./local/offload/"$hostname"
  mount -t tmpfs none ./local/offload/"$hostname"
  
  cp_rs ./local/offload/artful/etc/apt/sources.list /etc/apt/
  
  cp_rs ./local/offload/artful/var/lib/apt /var/lib/
  
  cp_rs ./local/offload/artful/var/cache/apt /var/cache/
}

function host_profile()
{
  local hostname
  hostname="$1"
  
  cp_rs ./local/profiles/"$hostname" /profile/
}

function host_final()
{
  local hostname
  hostname="$1"
  
  if [ ! -f       ./local/offload/rel_"$hostname" ]
  then
    touch -d '@0' ./local/offload/rel_"$hostname"
  fi
}


#host_ubuntu  some_name
#host_profile some_name
#host_final   some_name

function main()
{
  hostname="$1"
  channel="$(cat ./local/offload/chn_"$hostname")"
  
  (
    re='^[1-9]$'
    [[ "$channel" =~ $re ]]
  )
  
  [ -d ./local/offload/"$hostname" ]
  
  local RL
  RL="$(readlink -f ./local/offload/rel_"$hostname")"
  if [ "$2" == "all" ]
  then
    rm -f "$RL"
    host_final "$hostname"
  fi
  tar -C ./local/offload/"$hostname"/dir -c . --verbose --dereference --newer "$RL" --owner=0 --group=0 |    ./../pusher/pusher.rb "$channel"
  touch "$RL"
}

if [ "${1-}" != "" ]
then
  main "$1" "${2-}"
fi

echo "+OK (uniter.sh)"
