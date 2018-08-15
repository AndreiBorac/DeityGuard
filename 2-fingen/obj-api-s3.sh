#!/bin/false

function s3cmd_()
{
  $FINGEN_OBJ_API_S3_NETESC AWS_ACCESS_KEY="$S3_ACCESS_KEY" AWS_SECRET_KEY="$S3_SECRET_KEY" s3cmd --host="$S3_HOST" --host-bucket="$S3_HOST_BUCKET" "$@"
}

function obj_api_test()
{
  which s3cmd
}

function obj_api_stat()
{
  s3cmd_ ls s3://"$S3_CONTAINER"
}

function obj_api_create()
{
  s3cmd_ mb s3://"$S3_CONTAINER"
}

function obj_api_upload()
{
  local REM="$1"
  local LCL="$2"
  
  s3cmd_ put --acl-public "$(readlink -f "$LCL")" s3://"$S3_CONTAINER"/"$REM"
}

function obj_api_commit()
{
  true
}
