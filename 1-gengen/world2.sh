#!/bin/false

. /builds/elvopt
CORESP1=$(( (CORES+1) ))

cat >>/etc/portage/make.conf <<DBLEOF
MAKEOPTS="-j${CORESP1}"
DBLEOF

(
  for i in {1..2}
  do
    EMERGE_EXTRAOPTS=""
    if [ "$FLAG_BACKTRACK" == "y" ]
    then
      EMERGE_EXTRAOPTS="--backtrack=30"
    fi
    cat /etc/portage/make.conf
    cat /var/lib/portage/world || true
    cat /var/lib/portage/world_sets
    for i in /etc/portage/sets/*
    do
      cat "$i"
    done
    for i in /etc/portage/package.use/*
    do
      cat "$i"
    done
    for i in /var/lib/portage/world{,_sets} /etc/portage/package.{{,un}mask,accept_keywords,license}/* /etc/portage/profile/use.mask/*
    do
      cat "$i"
    done
    emerge --verbose --update --deep --newuse $EMERGE_EXTRAOPTS @world
    if [ "$FLAG_NOCLEAN" != "y" ]
    then
      emerge --depclean
    fi
    revdep-rebuild
    if [ "$FLAG_ONCEOVER" == "y" ]
    then
      break
    fi
  done
) 2>&1 | tee /var/log/emg."`date +%s.%Ns`"
