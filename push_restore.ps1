[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

param(
    [Parameter (Mandatory=$false,HelpMessage="Enter Username to Run this with")]
    [string]$user,
    [Parameter (Mandatory=$false, HelpMessage="Input file, list of Paths to restore. These can be files, directories, path seperators can be / or \. If you want to do a full restore provide the root path for the OS in the input file.")]
    [string]$inputFile,
    [Parameter (Mandatory=$false,HelpMessage="Target location that exists on disk for the files to be restored (C:/pushrestore/ is default, and use / instead of \")]
    [string]$RestorePath,
    [Parameter (Mandatory=$false, HelpMessage="Enter us1, us2, or eu1")]
    [ValidateSet('us1', 'us2', 'eu1', 'other')]
    [string]$CloudLocation,
    [Parameter (Mandatory=$false,HelpMessage="Source device GUID")]
    [string]$SourceComputerGUID,
    [Parameter (Mandatory=$false,HelpMessage="Destination Device Guid")]
    [string]$DestinationComputerGUID
)

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
if ($Username -eq ""){
    $Username = Read-Host -Prompt "Enter Username to run this with: "
}
if ($CloudLocation -eq ""){
    $promptedCloudLocation = Read-Host -Prompt "Please provide the target console. Enter us1, us2, or eu1, or Other to provide a custom server address."
    $CloudLocation = AssignCloudUrl($promptedCloudLocation)
}
if ($SourceComputerGUID -eq ""){
    $SourceComputerGUID = Read-Host -Prompt "Enter the source device GUID: "
}
if ($DestinationComputerGUID -eq ""){
    $DestinationComputerGUID = Read-Host -Prompt "Enter the destination device GUID: "
}
if ($RestorePath -eq "") {
    $RestorePath = Read-Host -Prompt "What is the target location that exists on disk for the files to be restored (C:/pushrestore/ is default, and use / instead of \)" 
}

$BaseUrl = AssignCloudUrl($CloudLocation)

$userAgent = "PushRestoreScript"
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

$pass= Read-Host "Enter the password for $user" -AsSecureString

#Get an authorization token for the rest of the API calls, prompting for the 
$pair = "$($user):$([Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass)))"
$encodedCreds = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($pair))
$basicAuthValue = "Basic $encodedCreds"

$totp = Read-Host "Do you need to enter a 2 factor Code to continue? Press Y/y to enter one. Press enter to skip."

if (!($totp -ilike 'y')){
    $basicAuthHeaders = @{
        Authorization = $basicAuthValue
    }
}
else {
$oneTimeCode = Read-Host "Enter your two factor Authentication Code"
    $basicAuthHeaders = @{
        Authorization = $basicAuthValue
        'totp-auth' = $oneTimeCode
    }
}

$tokenUrl = $BaseUrl + '/api/v3/auth/jwt?useBody=true'
$token = (Invoke-RestMethod -Uri $tokenUrl -Method Get -Headers $basicAuthHeaders -SessionVariable session -UserAgent $userAgent).data.v3_user_token

if($token){
    write-host "we are Authorized, continuing."
}
else{
    Write-Host "Invalid username,password, or one time code. Exiting please try again."
    exit
}

$headers = @{
    Authorization="Bearer $token"
}

$sourceGUIDUri = $BaseUrl + '/api/Computer/' + $SourceComputerGUID + '?idType=guid&active=true&incBackupUsage=true'
$targetGUIDUri = $BaseUrl + '/api/Computer/' + $DestinationComputerGUID + '?idType=guid&active=true&incBackupUsage=true'

$SourceComputer=Invoke-RestMethod -Method GET -Uri $sourceGUIDUri -Headers $headers -WebSession $session -UserAgent $userAgent
$targetComputer=Invoke-RestMethod -Method GET -Uri $targetGUIDUri -Headers $headers -WebSession $session -UserAgent $userAgent
$sourceUserUri = $BaseUrl + '/api/user/' + $SourceComputer.data.userUid + '?idType=uid'
$targetUserUri = $BaseUrl + '/api/user/' + $targetComputer.data.userUid  + '?idType=uid'

if (!($RestorePath)) {
    $RestorePath = "C:/pushrestore/"
}

$SourceUser=Invoke-RestMethod -Method GET -Uri $sourceUserUri -Headers $headers -WebSession $session -UserAgent $userAgent
$targetUser=Invoke-RestMethod -Method GET -Uri $targetUserUri -Headers $headers -WebSession $session -UserAgent $userAgent

#$SourceComputer.data.active  $SourceComputer.data.name $SourceComputer.data.lastConnected 
Write-Host "Source Computer information: Username:" $SourceUser.data.username " Org Name: " $SourceUser.data.orgName " Device Name:" $SourceComputer.data.name " Device last connected: " $SourceComputer.data.lastConnected
Write-Host "Target Computer information: Username:" $targetUser.data.username " Org Name: " $targetUser.data.orgName " Device Name:" $targetComputer.data.name " Device last connected: " $targetComputer.data.lastConnected
Write-Host "Restoring files from $inputFilePath"
Write-Host "Files will go here on the target device: $RestorePath"

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
function pushRestore($inputPaths,$SourceComputerGUID,$DestinationComputerGUID,$RestorePath,$ServerGUID) {
    Write-Host "$(get-date): Kicking off restore of $($jsonArray.Length) paths."
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

    $DataKeyToken = ((Invoke-RestMethod -Headers $headers -Uri "$BaseUrl/api/DataKeyToken" -Method Post -Body (ConvertTo-Json $DataKeyTokenPostValues) -ContentType application/json -WebSession $session -UserAgent $userAgent).data.dataKeyToken)

    $WebRestorePostValues = @{
        computerGuid = $SourceComputerGUID
        dataKeyToken = $DataKeyToken
    }
    $body =  ConvertTo-Json $WebRestorePostValues

    $WebRestoreSessionID = ((Invoke-RestMethod -Headers $headers -Uri "$BaseUrl/api/WebRestoreSession" -Method Post -Body $body -ContentType application/json -WebSession $session -UserAgent $userAgent).data.webRestoreSessionId)
    Write-Host "Retrieved web restore session"
    $PrePushRestoreJobBody = @{
        pushRestoreStrategy = "TARGET_DIRECTORY"
        existingFiles = "RENAME_ORIGINAL"
        filePermissions = "CURRENT"
        numFiles = $jsonArray.Length
        numBytes = $jsonArray.Length
        webRestoreSessionId = $WebRestoreSessionID
        sourceGuid = $SourceComputerGUID
        targetNodeGuid = $ServerGUID
        acceptingGuid = $DestinationComputerGUID
        restorePath = $RestorePath
        pathSet = $jsonArray
        restoreFullPath = $true
    }
    #Write-Host (ConvertTo-Json $PrePushRestoreJobBody)
    $PushRestoreJobBody = (ConvertTo-Json $PrePushRestoreJobBody)
    #Write-Host = "PushRestore Uri : $PushRestoreServer/api/PushRestoreJob"
    Invoke-RestMethod -Headers $headers -Uri "$BaseUrl/api/PushRestoreJob" -Method Post -Body $PushRestoreJobBody -ContentType "application/json" -WebSession $session -UserAgent $userAgent
    Start-Sleep -Seconds 1
}

# Read all lines from the input file into the pushRestore array, and call the pushRestore function for each group of paths
Get-Content -Path $inputFilePath -ReadCount $pushRestorePathsAtATime  | ForEach-Object { pushRestore $_ $SourceComputerGUID $DestinationComputerGUID $RestorePath $ServerGUID}