#!/bin/false

function do_create_user_gentoo()
{
  # here we use UID/GID 999 for compatibility with Ubuntu LiveCDs
  groupadd -g 999 user
  useradd -u 999 -g 999 -m -G users,wheel,audio -s /bin/bash user
  usermod -p '*' user
}

function do_create_user_buildroot()
{
  mkdir -p /home
  echo -e "user\nuser" | adduser -s /bin/bash user
}

function do_create_user()
{
  do_create_user_"$OS_RELEASE_ID"
  
  # generally we stick to umask 022. for enchanced security though, we
  # make the home directory itself 0700 to prevent other users from
  # reading files under the home directory
  
  chmod 0700 /home/user
}
