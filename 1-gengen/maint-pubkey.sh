#!/usr/bin/env bash

set -o xtrace
set -o errexit
set -o nounset
set -o pipefail
shopt -s failglob
shopt -s nullglob

cd ./files/pubkey

function gpg_()
{
  gpg --no-default-keyring --keyring gengen "$@"
}

function g()
{
  if [ ! -f ./"$1" ]
  then
    gpg_ --keyserver pgp.mit.edu --recv-keys "$1"
    gpg_ --armor --export "$1" >./"$1".tmp
    mv ./"$1"{.tmp,}
  fi
  
  if [ ! -h ./"$2" ]
  then
    ln -vsfT ./"$1" ./"$2"
  fi
}

g 2D182910 gentoo_releng_1
g 96D8BF6D gentoo_portage_1
g 7E7D47A7 linuxlibre_1
g D31D7652 u_boot_1
