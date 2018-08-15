#!/bin/false

function ssh_prep()
{
  mkdir -m 0700 -p ./local/socket
  
  if ! mountpoint -q ./local/socket
  then
    sudo mount -t tmpfs none ./local/socket
  fi
  
  if [ ! -S ./local/socket/ssh ]
  then
    local RL_IDENTITY_FILE
    RL_IDENTITY_FILE="$(readlink -f "$IDENTITY_FILE")"
    
    echo "$REMOTE_HOST" "$HOST_KEY_TYPE" "$HOST_KEY_SCAN" >./build/ukhf
    local RL_UKHF_FILE
    RL_UKHF_FILE="$(readlink -f ./build/ukhf)"
    
    $FINGEN_OBJ_API_SCP_NETESC ssh -fN -o IdentityFile="$RL_IDENTITY_FILE" -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$RL_UKHF_FILE" -o ControlMaster=yes -o ControlPath="$(readlink -f ./local/socket/ssh)" -o ControlPersist=3600 -o ServerAliveInterval=300 "$REMOTE_USER"@"$REMOTE_HOST"
    
    while [ ! -S ./local/socket/ssh ]
    do
      sleep 0.25
    done
  fi
}

function ssh_()
{
  ssh_prep
  ssh -o ControlPath="$(readlink -f ./local/socket/ssh)" ign@ign "$@"
}

function scp_()
{
  ssh_prep
  scp -o ControlPath="$(readlink -f ./local/socket/ssh)" "$LCL" ign@ign:"$REMOTE_DIRECTORY"/"$REM"
}

function obj_api_test()
{
  true
}

function obj_api_stat()
{
  ssh_ ls -lh "$REMOTE_DIRECTORY"
}

function obj_api_create()
{
  true
}

function obj_api_upload()
{
  local REM="$1"
  local LCL="$2"
  
  scp_ "$LCL" "$REM"
}

function obj_api_commit()
{
  true
}
