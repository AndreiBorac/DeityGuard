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
  obj_api_curl__ --fail --include --header "X-Auth-Token: ""$TOKEN" "$@"
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
  
  if [ "${1:0:11}" != "rootfs.bin-" ] && [ "${1:0:11}" != "stage2.bin-" ]
  then
    local ARG1
    ARG1="$OVH_OUTPUT"/"$OVH_CONTAINER"/"$1"
    ARG1="$(echo "$ARG1" | sed -e 's/:/%3A/g' -e 's/\//%2F/g')"
    local ARG2
    ARG2="$1"
    local ARG3
    ARG3="$(sha256sum "$2" | cut -d " " -f 1)"_"$(wc -c <"$2")"
    wget -O- "$BUCKET_DEPLOY_ENDPOINT"/"$ARG1"/"$ARG2"/"$ARG3"
  fi
}

function obj_api_commit()
{
  true
}
