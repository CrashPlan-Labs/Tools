param(
    [Parameter(Mandatory=$true, HelpMessage="Username with push restore permissions")]
    [string]$User,
    [Parameter(Mandatory=$true, HelpMessage="Base URL (e.g. https://console.us2.crashplan.com)")]
    [string]$BaseUrl,
    [Parameter(Mandatory=$true, HelpMessage="Source device GUID")]
    [string]$SourceComputerGuid,
    [Parameter(Mandatory=$true, HelpMessage="Target device GUID")]
    [string]$TargetComputerGuid,
    [Parameter(Mandatory=$false, HelpMessage="Input file containing a list of paths to restore. These can be files or directories. Path separators can be / or \. If you want to do a full restore for a system this will assume C:/ for Windows and / for macOS and Linux.")]
    [string]$InputFile,
    [Parameter(Mandatory=$false, HelpMessage="Target location that exists on disk for the files to be restored (C:/pushrestore/SourceComputerGuid is default if target is Windows, /pushrestore/SourceComputerGuid if macOS/Linux, and use / instead of \).")]
    [string]$TargetDirectory,
    [Parameter(Mandatory=$false, HelpMessage="Date to restore from. Format can be yyyy-MM-dd, yyyy-MM-dd hh:mm, or any other date format PowerShell recognizes. If none is provided the latest version will be restored.")]
    [string]$RestoreDate,
    [Parameter(Mandatory=$false, HelpMessage="Add paramater to restore deleted files. Disabled by default.")]
    [switch]$RestoreDeletedFiles
)

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if ($TargetDirectory -eq "") {
    $TargetDirectory = Read-Host -Prompt "What is the target location that exists on disk for the files to be restored? If not provided C:/pushrestore/$SourceComputerGuid/ or /pushrestore/$SourceComputerGuid/ will be used. (use / instead of \)."
}
Write-Host "RestoreDeletedFiles is set to $RestoreDeletedFiles"
$UserAgent = "PushRestoreScript"
$pushRestorePathsAtATime = 10000

$credentials = Get-Credential -Credential $User

$PrivatePassword = Read-Host -AsSecureString -Prompt "Archive key password. Press Enter to skip if not required."
$CustomKey = Read-Host -AsSecureString -Prompt "Custom key. Press Enter to skip if not required."

# Get an authorization token for the rest of the API calls, prompting for a two-factor code as needed. Works with PowerShell 5.1 and PowerShell Core
$pair = "$($credentials.username):$($credentials.GetNetworkCredential().Password)"
$encodedCreds = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($pair))
$basicAuthValue = "Basic $encodedCreds"

$totp = Read-Host "Enter your 2-factor code. Press Enter to skip if not required."
if ([string]::IsNullOrEmpty($totp)) {
    $basicAuthHeaders = @{
        Authorization = $basicAuthValue
    }
} else {
    $basicAuthHeaders = @{
        Authorization = $basicAuthValue
        'totp-auth' = $totp
    }
}

$login_url = $BaseUrl + '/api/v3/auth/jwt?useBody=true'
$token = (Invoke-RestMethod -Uri $login_url -Method Get  -Headers $basicAuthHeaders -ContentType 'application/json' -SessionVariable session -UserAgent $userAgent).data.v3_user_token
if($token){
    write-host "We are authorized - continuing"
}
else {
    Write-Host "Invalid username, password, 2-factor code, or base URL. Please rerun the script and try again."
    exit
}

$headers = @{
    Authorization = "Bearer $token"
}

$sourceGUIDUri = $BaseUrl + '/api/Computer/' + $SourceComputerGuid + '?idType=guid&active=true&incBackupUsage=true'
$targetGUIDUri = $BaseUrl + '/api/Computer/' + $TargetComputerGuid + '?idType=guid&active=true&incBackupUsage=true'

$SourceComputer = Invoke-RestMethod -Method GET -Uri $sourceGUIDUri -Headers $headers -WebSession $session -UserAgent $UserAgent
$targetComputer = Invoke-RestMethod -Method GET -Uri $targetGUIDUri -Headers $headers -WebSession $session -UserAgent $UserAgent
$targetUserUri = $BaseUrl + '/api/user/' + $targetComputer.data.userUid + '?idType=uid'

$sourceUserUri = $BaseUrl + '/api/user/' + $SourceComputer.data.userUid + '?idType=uid'
$SourceComputerOs = $SourceComputer.data.osName
$targetComputerOs = $targetComputer.data.osName
$TargetComputerName = $targetComputer.data.name
$SourceComputerName = $SourceComputer.data.name

if ($SourceComputerOs -like "*win*") {
    $defaultPath = "C:/"
} else {
    $defaultPath = "/"
}

if (!($TargetDirectory)) {
    if ($targetComputerOs -like "*win*") {
        $TargetDirectory = "C:/pushrestore/$SourceComputerGuid/"
    } else {
        $TargetDirectory = "/pushrestore/$SourceComputerGuid/"
    }
}

if (!($RestoreDate)) {
    $RestoreDate = (Get-Date).ToString("yyyy-MM-dd")
} else{
    if (!($RestoreDate -as [DateTime])) {
        Write-Host "The provided restore date '$RestoreDate' is not in the correct format (yyyy-MM-dd or yyyy-MM-dd hh:mm). Exiting."
        exit
    }
}
#convert the restore date to epoch time
$EpochRestoreDate=[int64](Get-Date $RestoreDate -UFormat "%s") * 1000

if ($RestoreDeletedFiles -eq $true) {
    Write-Host "Deleted files will be included in the restore."
} else {
    Write-Host "Deleted files will NOT be included in the restore."
}

Write-Host "Restoring from date:" $RestoreDate

$SourceUser = Invoke-RestMethod -Method GET -Uri $sourceUserUri -Headers $headers -WebSession $session -UserAgent $UserAgent
$targetUser = Invoke-RestMethod -Method GET -Uri $targetUserUri -Headers $headers -WebSession $session -UserAgent $UserAgent

Write-Host "Source Computer information: Username:" $SourceUser.data.username "Org Name:" $SourceUser.data.orgName "Device Name:" $SourceComputerName "Device last connected:" $SourceComputer.data.lastConnected
Write-Host "Target Computer information: Username:" $targetUser.data.username "Org Name:" $targetUser.data.orgName "Device Name:" $TargetComputerName "Device last connected:" $targetComputer.data.lastConnected

if ($InputFile) {
    Write-Host "Restoring files or paths listed in $InputFile."
} else {
    Write-Host "Restoring $defaultPath."
}

Write-Host "Target device restore directory: $TargetDirectory"

$confirmation = Read-Host "If the above information is correct, enter Y/y to continue. Press any other key to exit."

if (!($confirmation -ilike 'y')) {
    exit
}

Write-Host "Starting restore of" $SourceComputer.data.name "to" $targetComputer.data.name

$ServerGUID = $SourceComputer.data.backupUsage.serverGuid

$DataKeyTokenPostValues = @{
    computerGuid = $SourceComputerGuid
}

# Function to convert SecureStrings back to Strings
# Checks if empty first, and if so, returns a blank string
# PowerShell Core and Desktop have two mutually exclusive ways of converting SecureStrings to Strings
function convertString($SecureString) {
    if ($SecureString.Length -eq 0) {
        $OutString = ""
    } else {
        if ($PSVersionTable.PSEdition -eq "Desktop") {
            $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
            $OutString = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
        } else {
            $OutString = $SecureString | ConvertFrom-SecureString -AsPlainText
        }
    } 
    return $OutString
}

$PrivatePassString = convertString $PrivatePassword
$CustomKeyString = convertString $CustomKey
# Define the push restore function
function pushRestore($inputPaths, $SourceComputerGuid, $TargetComputerGuid, $TargetDirectory, $ServerGUID, $PrivatePassString, $CustomKeyString) {
    Write-Host "$(Get-Date): Kicking off restore of provided paths."
    # Initialize an array to hold the JSON objects
    $jsonArray = @()

    foreach ($line in $inputPaths) {
        # Create a hashtable for each file
        $line = $line.Replace("\", "/")
        if ($line -match ".*/$") {
            $type = "directory"
        } else {
            $type = "file"
        }
        $pathObject = @{
            type = $type
            path = "$line"
            selected = $true
        }

        # Add the hashtable to the array
        $jsonArray += $pathObject
    }

    $DataKeyToken = (Invoke-RestMethod -Headers $headers -Uri "$BaseUrl/api/DataKeyToken" -Method Post -Body (ConvertTo-Json $DataKeyTokenPostValues) -ContentType application/json -WebSession $session -UserAgent $UserAgent).data.dataKeyToken

    $WebRestorePostValues = @{
        computerGuid = $SourceComputerGUID
        dataKeyToken = $DataKeyToken
        privatePassword = $PrivatePassString
        encryptionKey = $CustomKeyString
    }
    $body = ConvertTo-Json $WebRestorePostValues

    $WebRestoreSessionID = (Invoke-RestMethod -Headers $headers -Uri "$BaseUrl/api/WebRestoreSession" -Method Post -Body $body -ContentType application/json -WebSession $session -UserAgent $UserAgent).data.webRestoreSessionId
    Write-Host "Retrieved web restore session"

    $PrePushRestoreJobBody = @{
        pushRestoreStrategy = "TARGET_DIRECTORY"
        existingFiles = "RENAME_ORIGINAL"
        filePermissions = "CURRENT"
        numFiles = 1
        numBytes = 1
        webRestoreSessionId = $WebRestoreSessionID
        sourceGuid = $SourceComputerGuid
        targetNodeGuid = $ServerGUID
        acceptingGuid = $TargetComputerGuid
        restorePath = $TargetDirectory
        pathSet = $jsonArray
        restoreFullPath = $true
        timestamp = $EpochRestoreDate
        showDeletedFiles = $RestoreDeletedFiles
    }

    $PushRestoreJobBody = ConvertTo-Json $PrePushRestoreJobBody
    Invoke-RestMethod -Headers $headers -Uri "$BaseUrl/api/PushRestoreJob" -Method Post -Body $PushRestoreJobBody -ContentType "application/json" -WebSession $session -UserAgent $UserAgent
    Start-Sleep -Seconds 1
}

# Read all lines from the input file into the pushRestore array, and call the pushRestore function for each group of paths. If the input file does not exist, dynamically choose the path based on whether it's a Windows or macOS system. Assuming Windows by default.

if ($InputFile -and (Test-Path -Path $InputFile)) {
    Get-Content -Path $InputFile -ReadCount $pushRestorePathsAtATime | ForEach-Object { pushRestore $_ $SourceComputerGuid $TargetComputerGuid $TargetDirectory $ServerGUID $PrivatePassString $CustomKeyString }
} else {
    Write-Host "Input file $InputFile does not exist. Restoring the full drive for $SourceComputerGuid."
    pushRestore $defaultPath $SourceComputerGuid $TargetComputerGuid $TargetDirectory $ServerGUID $PrivatePassString $CustomKeyString
    exit
}
