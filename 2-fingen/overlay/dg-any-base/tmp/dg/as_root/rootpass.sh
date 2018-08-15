#!/bin/false

function do_rootpass()
{
  sed -i -e 's@^root:[^:]*@root:'"$1"'@' /etc/shadow
}

function do_rootpass_none()
{
  passwd -d root
}
