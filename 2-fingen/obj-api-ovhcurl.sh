#!/bin/false

# https://www.ovh.com/us/g1576.dedicated_cloud_swift_start-up_guide

function obj_api_test()
{
  which curl
}

function obj_api_curl__()
{
  $FINGEN_OBJ_API_OVHCURL_AND_BUCKET_NETESC curl "$@"
}

function obj_api_curl_()
{
  function obj_api_curl_auth_()
  {
    obj_api_curl__ --header "Content-type: application/json" --data @<(echo '{"auth": {"tenantName": "'"$OVH_AUTH_TENANT_NAME"'", "passwordCredentials": {"username": "'"$OVH_AUTH_USERNAME"'", "password": "'"$OVH_AUTH_PASSWORD"'"}}}') "$OVH_AUTH_ENDPOINT" | ( egrep -o '[0-9a-f]{32}' || true ) | head -n 1
  }
  local TOKEN
  TOKEN="$(obj_api_curl_auth_)"
  local RE
  RE='^[0-9a-f]{32}$'
  [[ $TOKEN =~ $RE ]]
  obj_api_curl__ --fail --include --header "X-Auth-Token: ""$OVH_XAUTHTOKEN" "$@"
}

function obj_api_stat()
{
  obj_api_curl_ --head "$OVH_ENDPOINT"/"$OVH_CONTAINER"/
  obj_api_curl_        "$OVH_ENDPOINT"/"$OVH_CONTAINER"/
}

function obj_api_create()
{
  obj_api_curl_ -X PUT --header "X-Container-Read: .r:*" "$OVH_ENDPOINT"/"$OVH_CONTAINER"/
}

function obj_api_upload()
{
  obj_api_curl_ --upload-file "$2" "$OVH_ENDPOINT"/"$OVH_CONTAINER"/"$1"
}

function obj_api_commit()
{
  true
}
