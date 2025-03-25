#Get an authorization token for the rest of the API calls, prompting for a two factor code as needed. Works with powershell 5.1 and Powershell core
param (
    [Parameter (Mandatory=$true,HelpMessage="Enter Username to Run this with")]
    [string]$api_client,
    [Parameter (Mandatory=$true,HelpMessage="Enter the base url to run the script with")]
    [string]$base_url
)

$credentials = Get-Credential  -Credential $api_client

$pair = "$($credentials.username):$($credentials.GetNetworkCredential().Password)"
$encodedCreds = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($pair))
$basicAuthValue = "Basic $encodedCreds"

$basicAuthHeaders = @{
    Authorization = $basicAuthValue
}

$login_url = $base_url + '/api/v3/oauth/token?grant_type=client_credentials'
$login_response = $(Invoke-RestMethod -Uri $login_url -Method Post  -Headers $basicAuthHeaders -Body "" -ContentType 'application/json' -UseBasicParsing)
$token = ($login_response).access_token
if($token){
    write-host "we are Authorized, continuing"
}
else{
    Write-Host "Invalid api key, secret, or base url. Exiting please try again."
    exit
}
Write-Host "API Client: ${api_client}"
Write-Host "Access Token: ${token}"

<#
Creating a header to use for further authentication
$headers = @{
    Authorization="Bearer $token"
}
#>