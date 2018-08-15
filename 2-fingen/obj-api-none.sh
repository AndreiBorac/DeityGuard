#!/bin/false

function obj_api_test()
{
  true
}

function obj_api_stat()
{
  true
}

function obj_api_create()
{
  true
}

function obj_api_upload()
{
  local REM="$1"
  local LCL="$2"
  
  mkdir -p                            ./local/obj_api_none
  
  #if [ "${REM:0:11}" == "rootfs.bin-" ]
  #then
  #  ln -vsfT "$(readlink -f "$LCL")" ./local/obj_api_none/"$REM"
  #else
     cp       "$(readlink -f "$LCL")" ./local/obj_api_none/"$REM"
  #fi
}

function obj_api_commit()
{
  true
}
