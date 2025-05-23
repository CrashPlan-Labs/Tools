param(
    [Parameter (Mandatory=$true,HelpMessage="Enter Username to Run this with")]
    [string]$User,
    [Parameter (Mandatory=$true, HelpMessage="Input file, list of Paths to restore. These can be files, directories, path seperators can be / or \. If you want to do a full restore provide the root path for the OS in the input file.")]
    [string]$InputFile,
    [Parameter (Mandatory=$false,HelpMessage="Target location that exists on disk for the files to be restored (C:/pushrestore/ is default, and use / instead of \")]
    [string]$TargetDirectory,
    [Parameter (Mandatory=$false, HelpMessage="Enter us1, us2, or eu1")]
    [ValidateSet('us1', 'us2', 'eu1', 'other')]
    [string]$CloudLocation,
    [Parameter (Mandatory=$true,HelpMessage="Source device GUID")]
    [string]$SourceComputerGUID,
    [Parameter (Mandatory=$true,HelpMessage="Target Device Guid")]
    [string]$TargetComputerGuid
)

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function AssignCloudUrl($CloudLocation){
    $CloudLocation = $CloudLocation.ToLower()
    switch($CloudLocation){
        "us2"{
            return "https://console.us2.crashplan.com"
        }
        "us1"{
            return "https://console.us1.crashplan.com"
        }
        "eu1"{
            return "https://console.cpg.eu5.crashplan.com"
        }
        "other" {
            return Read-Host -Prompt "Please input the console URL (e.g. https://console.us.crashplan.com)"
        }
    }
}

# Current Prompt for required info if not provided in command

if ($CloudLocation -eq ""){
    $promptedCloudLocation = Read-Host -Prompt "Please provide the target console. Enter us1, us2, or eu1, or Other to provide a custom server address."
    $BaseUrl = AssignCloudUrl($promptedCloudLocation)
}
else {
    $BaseUrl = AssignCloudUrl($CloudLocation)
}
if ($TargetDirectory -eq "") {
    $TargetDirectory = Read-Host -Prompt "What is the target location that exists on disk for the files to be restored (C:/pushrestore/ is default, and use / instead of \)" 
}

$UserAgent = "PushRestoreScript"
$pushRestorePathsAtATime = 10000

<#
Push restores can be combined with this code:

$target_location = "C:\ComblinedPath\"
$sourceLocation = "C:\pushrestore\"

$restores = Get-childitem -path $sourceLocation
foreach ($restore in $restores) {
    write-host $restore.FullName
    Copy-Item -Path "$(${restore}.FullName)/*" -Destination $target_location -Recurse -ErrorAction SilentlyContinue
}
#>

$credentials = Get-Credential -Credential $User

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

$login_url = $BaseUrl + '/api/v3/auth/jwt?useBody=true'
$token = (Invoke-RestMethod -Uri $login_url -Method Get  -Headers $basicAuthHeaders -ContentType 'application/json' -SessionVariable session -UserAgent $userAgent).data.v3_user_token
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

$sourceGUIDUri = $BaseUrl + '/api/Computer/' + $SourceComputerGUID + '?idType=guid&active=true&incBackupUsage=true'
$targetGUIDUri = $BaseUrl + '/api/Computer/' + $TargetComputerGuid + '?idType=guid&active=true&incBackupUsage=true'

$SourceComputer=Invoke-RestMethod -Method GET -Uri $sourceGUIDUri -Headers $headers -WebSession $session -UserAgent $UserAgent
$targetComputer=Invoke-RestMethod -Method GET -Uri $targetGUIDUri -Headers $headers -WebSession $session -UserAgent $UserAgent
$sourceUserUri = $BaseUrl + '/api/user/' + $SourceComputer.data.userUid + '?idType=uid'
$targetUserUri = $BaseUrl + '/api/user/' + $targetComputer.data.userUid  + '?idType=uid'

if (!($TargetDirectory)) {
    $TargetDirectory = "C:/pushrestore/"
}

$SourceUser=Invoke-RestMethod -Method GET -Uri $sourceUserUri -Headers $headers -WebSession $session -UserAgent $UserAgent
$targetUser=Invoke-RestMethod -Method GET -Uri $targetUserUri -Headers $headers -WebSession $session -UserAgent $UserAgent

#$SourceComputer.data.active  $SourceComputer.data.name $SourceComputer.data.lastConnected 
Write-Host "Source Computer information: Username:" $SourceUser.data.username " Org Name: " $SourceUser.data.orgName " Device Name:" $SourceComputer.data.name " Device last connected: " $SourceComputer.data.lastConnected
Write-Host "Target Computer information: Username:" $targetUser.data.username " Org Name: " $targetUser.data.orgName " Device Name:" $targetComputer.data.name " Device last connected: " $targetComputer.data.lastConnected
Write-Host "Restoring files or paths listed in $InputFile"
Write-Host "Files will go here on the target device: $TargetDirectory"

$conformation = Read-Host "If the above information is correct enter Y/y to continue. press any other key to exit."

if (!($conformation -ilike 'y')){
 exit
}
Write-Host 'Starting restore of' $SourceComputer.data.name 'to '$targetComputer.data.name

$ServerGUID = ($SourceComputer).data.backupUsage.serverGuid

$DataKeyTokenPostValues = @{
    computerGuid = $SourceComputerGUID
}

#Define the push restore function
function pushRestore($inputPaths,$SourceComputerGUID,$TargetComputerGuid,$TargetDirectory,$ServerGUID) {
    Write-Host "$(get-date): Kicking off restore of provided paths."
    # Initialize an array to hold the JSON objects
    $jsonArray = @()

    foreach ($line in $inputPaths) {  
        # Create a hashtable for each file
        $line=$line.Replace("\","/")
        if ($line -match ".*/$"){
            $type="directory"
        }
        else {
            $type="file"
        }
        $pathObject = @{
            type = $type
            path = "$line"
            selected = $true
        }

        # Add the hashtable to the array
        $jsonArray += $pathObject
    }

    $DataKeyToken = ((Invoke-RestMethod -Headers $headers -Uri "$BaseUrl/api/DataKeyToken" -Method Post -Body (ConvertTo-Json $DataKeyTokenPostValues) -ContentType application/json -WebSession $session -UserAgent $UserAgent).data.dataKeyToken)

    $WebRestorePostValues = @{
        computerGuid = $SourceComputerGUID
        dataKeyToken = $DataKeyToken
    }
    $body =  ConvertTo-Json $WebRestorePostValues

    $WebRestoreSessionID = ((Invoke-RestMethod -Headers $headers -Uri "$BaseUrl/api/WebRestoreSession" -Method Post -Body $body -ContentType application/json -WebSession $session -UserAgent $UserAgent).data.webRestoreSessionId)
    Write-Host "Retrieved web restore session"
    $PrePushRestoreJobBody = @{
        pushRestoreStrategy = "TARGET_DIRECTORY"
        existingFiles = "RENAME_ORIGINAL"
        filePermissions = "CURRENT"
        numFiles = 1
        numBytes = 1
        webRestoreSessionId = $WebRestoreSessionID
        sourceGuid = $SourceComputerGUID
        targetNodeGuid = $ServerGUID
        acceptingGuid = $TargetComputerGuid
        restorePath = $TargetDirectory
        pathSet = $jsonArray
        restoreFullPath = $true
    }
    #Write-Host (ConvertTo-Json $PrePushRestoreJobBody)
    $PushRestoreJobBody = (ConvertTo-Json $PrePushRestoreJobBody)
    #Write-Host = "PushRestore Uri : $PushRestoreServer/api/PushRestoreJob"
    Invoke-RestMethod -Headers $headers -Uri "$BaseUrl/api/PushRestoreJob" -Method Post -Body $PushRestoreJobBody -ContentType "application/json" -WebSession $session -UserAgent $UserAgent
    Start-Sleep -Seconds 1
}

# Read all lines from the input file into the pushRestore array, and call the pushRestore function for each group of paths
Get-Content -Path $InputFile -ReadCount $pushRestorePathsAtATime  | ForEach-Object { pushRestore $_ $SourceComputerGUID $TargetComputerGuid $TargetDirectory $ServerGUID}
