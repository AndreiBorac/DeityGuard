#!/bin/false

function ssh_()
{
  $FINGEN_OBJ_API_SSH_NETESC ssh -i ./local/kp user@"$(cat ./local/ip)" "$@"
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
  
  ssh_ 'cat >'"$REMOTE_DIRECTORY"'/'"$REM" <"$LCL"
}

function obj_api_commit()
{
  true
}
