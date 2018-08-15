#!/bin/false

function obj_api_test()
{
  which ruby
  
  [ -n "$ITHIRD_INTERFACE" ]
  
  local re
  re='^[1-9]$'
  [[ "$ITHIRD_CHANNEL" =~ $re ]]
}

function obj_api_stat()
{
  echo "warning: cannot stat: ithird is unidirectional"
}

function obj_api_create()
{
  true
}

function obj_api_upload()
{
  local REM="$1"
  local LCL="$2"
  
  mkdir -p                         ./build/ithird
  ln -vsfT "$(readlink -f "$LCL")" ./build/ithird/"$REM"
}

function obj_api_commit()
{
  if [ -d ./build/ithird ]
  then
    function ithird_config_as_pusher()
    {
      local ifname="$1"
      local channel="$2"
      
      sudo ifconfig "$ifname" 10.183.215."$channel"01 netmask 255.255.255.252
      sudo arp -s 10.183.215."$channel"02 02:00:00:00:00:0"$channel"
    }
    
    ithird_config_as_pusher "$ITHIRD_INTERFACE" "$ITHIRD_CHANNEL"
    
    tar -C ./build/ithird -c . --dereference | bash ./ithird/pusher.rb "$ITHIRD_CHANNEL"
  fi
}
