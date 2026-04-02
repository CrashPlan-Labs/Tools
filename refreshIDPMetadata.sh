#!/bin/bash
# Usage: ./script.sh <username> <base_url> <idp_uid>

if [ $# -lt 3 ]; then
    echo "Usage: $0 <username> <base_url> <idp_uid>"
    echo "Example: $0 admin@example.com https://console.us1.crashplan.com 1234567890424242"
    exit 1
fi

api_user="$1"
base_url="$2"
IDP_UID="$3"

read -sp "Please enter your password: " api_password
echo
read -p "Please provide TOTP, hit enter to skip: " TOTP

LOGIN_RESPONSE=$(curl -su "${api_user}:${api_password}" -H "totp-auth: $TOTP"  -H "Content-Type: application/json" -X GET "$base_url/api/v3/auth/jwt?useBody=true")

V3_USER_TOKEN=$(jq -r '.data.v3_user_token' <<< "$LOGIN_RESPONSE")

echo $(curl -sX PUT "${base_url}/api/v1/SsoMetadata/${IDP_UID}" -H "Authorization: Bearer ${V3_USER_TOKEN}")