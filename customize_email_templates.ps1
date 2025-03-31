param (
    [Parameter (Mandatory=$true,HelpMessage="Enter Username to Run this with")]
    [string]$user,
    [Parameter (Mandatory=$true,HelpMessage="Enter the base url to run the script with")]
    [string]$base_url
)
$userAgent = "CustomizeEmail"
$currentEmailTextCustomizationsFile = "current.json"
$customizedTemplatesFile = "customizedTemplates.json"

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
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

$token = (Invoke-RestMethod -Uri $login_url -Method Get  -Headers $basicAuthHeaders -ContentType 'application/json' -UserAgent $userAgent).data.v3_user_token
if($token){
    write-host "we are Authorized, continuing"
}
else{
    Write-Host "Invalid username, password, one time code, or base url. Exiting please try again."
    exit
}

$headers = @{
    Authorization="Bearer $token"
}

#get the customization content
$emailTemplate =  Invoke-RestMethod -Headers $headers -Uri "$base_url/api/v4/email-text-customization/view" -Method GET -ContentType "application/json" -UserAgent $userAgent
#output of the current state
$customizationsJson = $emailTemplate.data.emailTextCustomizations | ConvertTo-Json 
$customizationsJson = $customizationsJson -replace '\\u0026', '&' -replace '\\u0027', "'" -replace '\\u003c', '<' -replace '\\u003e', '>'

Write-Host "Created file with the current email text settings $currentEmailTextCustomizationsFile"
Out-File -InputObject $customizationsJson -FilePath $currentEmailTextCustomizationsFile -Encoding ascii

#creating a file that can be used to update the content
$conformationModify = Read-Host "Do you want to create a file to modify for updating email text? enter Y/y to continue. press any other key to skip"

if (($conformationModify -ilike 'y')){

    $emailTemplateJson = $emailTemplate.data.emailTextCustomizations | Select-Object category, segment, defaultContent |ConvertTo-Json 

    $updateAll = $emailTemplateJson -replace '"defaultContent":', '"content":'-replace '\\u0026', '&' -replace '\\u0027', "'" -replace '\\u003c', '<' -replace '\\u003e', '>'

    $updateAll = $updateAll -replace '\s*{\s*"category":\s*"GLOBAL",\s*"segment":\s*"SENDER_EMAIL",\s*"content":\s*"noreply@crashplan.com"\s*},\s',''

    $updateFinal= '{"emailTextCustomizations": '+$updateAll+'}'
    Write-Host "Created updateAll.json, update the 'content' lines with the new custom content, and remove any sections you don't want to update."
    Out-File -InputObject $updateFinal -FilePath "updateAll.json" -Encoding ascii
    Write-Host "`nModify the updateAll.json file to only inclide the category,segment, and content for the emails you want to customize and then save the file as $customizedTemplatesFile. If modification of $customizedTemplatesFile takes longer than 15 minutes you may need to run the script to upload the changes."
}

#updating the data, will exit if the custom file has not been created
$conformationUpdate = Read-Host "Do you want to update the email text? enter Y/y to continue, and have you created $customizedTemplatesFile? Press any other key to skip"
if (($conformationUpdate -ilike 'y') -and (Test-Path $customizedTemplatesFile -PathType Leaf) ){
    $uploadPath=$customizedTemplatesFile
    Invoke-RestMethod -Headers $headers -Uri "$base_url/api/v4/email-text-customization/update" -Method POST -InFile $uploadPath -ContentType "application/json" -UserAgent $userAgent
}
$conformationLogo = Read-Host "Do you want to modify the logo of the emails and have you created a custom header image? Enter Y/y to continue. Press any other key to skip"
if (($conformationLogo -ilike 'y')){
    #This section will let you update the header logo on the emails.
    $headerLogo = Read-Host "Please enter the full path to the new logo"
    $form = @{logo=get-item $headerLogo}
    Invoke-RestMethod -Headers $headers -Uri "$base_url/api/v3/EmailLogoCustomization" -Method POST -body $form -ContentType "multipart/form-data" -UserAgent $userAgent
}

Write-Host "`nTo test your new emails in the console CLI run 'test.email <email address>' to recieve example emails with the customizations."