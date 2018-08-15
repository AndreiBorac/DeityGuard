#!/bin/false

function swift_()
{
  (
    export OS_AUTH_URL OS_TENANT_ID OS_TENANT_NAME OS_USERNAME OS_PASSWORD OS_REGION_NAME
    $FINGEN_OBJ_API_SWIFT_NETESC swift -V 2 "$@"
  )
}

function obj_api_test()
{
  which swift
}

function obj_api_stat()
{
  swift_ stat "$SWIFT_CONTAINER"
}

function obj_api_create()
{
  swift_ post "$SWIFT_CONTAINER"
  swift_ post --header "X-Container-Read: .r:*" "$SWIFT_CONTAINER"
}

function obj_api_upload()
{
  swift_ upload --object-name="$1" "$SWIFT_CONTAINER" "$2"
}

function obj_api_commit()
{
  true
}
