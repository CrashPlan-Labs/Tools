#!/bin/bash
#define api_key,secret, and base_url
# $bearer_token will be the value used for further authentication
api_user='<username>'
api_password='<password>'
base_url='<console_address>'

read -p "Please provide TOTP, hit enter to skip: " TOTP

LOGIN_RESPONSE=$(curl -su "${api_user}:${api_password}" -H "totp-auth: $TOTP"  -H "Content-Type: application/json" -X GET "$base_url/api/v3/auth/jwt?useBody=true")

V3_USER_TOKEN=$(jq -r '.data.v3_user_token' <<< "$LOGIN_RESPONSE")

echo "Username: $api_user"
echo "Auth token: $V3_USER_TOKEN"

#Further auth can be passed using: "curl -H "Authorization: Bearer ${V3_USER_TOKEN}"