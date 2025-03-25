param (
    [Parameter (Mandatory=$true,HelpMessage="Enter Username to Run this with")]
    [string]$user,
    [Parameter (Mandatory=$true,HelpMessage="Enter the base url to run the script with")]
    [string]$base_url
)

$credentials = Get-Credential -Credential $user

#Get an authorization token for the rest of the API calls, prompting for a two factor code as needed. Works with powershell 5.1 and Powershell core
$pair = "$($credentials.username):$($credentials.GetNetworkCredential().Password)"
$encodedCreds = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($pair))
$basicAuthValue = "Basic $encodedCreds"

$totp = Read-Host "Enter your 2 factor code. Press enter to skip if not required"
if ([string]::IsNullOrEmpty($totp)){
    $basicAuthHeaders = @{
        Authorization = $basicAuthValue
    }
}
else {
    $basicAuthHeaders = @{
        Authorization = $basicAuthValue
        'totp-auth' = $totp
    }
}

$login_url = $base_url + '/api/v3/auth/jwt?useBody=true'
$token = (Invoke-RestMethod -Uri $login_url -Method Get  -Headers $basicAuthHeaders -ContentType 'application/json').data.v3_user_token
if($token){
    write-host "we are Authorized, continuing"
}
else{
    Write-Host "Invalid username, password, one time code, or base url. Exiting please try again."
    exit
}
<#
Creating a header to use for further authentication
$headers = @{
    Authorization="Bearer $token"
}
#>