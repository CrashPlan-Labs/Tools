#!/bin/bash
#define api_key,secret, and base_url
# $bearer_token will be the value used for further authentication
api_key='"<clientID>"'
api_secret='<Secret>'
base_url='<base_url>'

LOGIN_RESPONSE=$(/usr/bin/curl -X POST -su ${api_key}:${api_secret} -H "Content-Type: application/json" "${base_url}/api/v3/oauth/token?grant_type=client_credentials")

V3_USER_TOKEN=$(jq -r '.access_token' <<< "$LOGIN_RESPONSE")

echo "API key: $api_key"
echo "Auth token: $V3_USER_TOKEN"

#Further auth can be passed using: "curl -H "Authorization: Bearer ${V3_USER_TOKEN}"