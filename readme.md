PushRestore.ps1
License: MIT
This script kicks off a push restore for CrashPlan using the `/api/PushRestoreJob` method. First it makes a call to set up a web restore session, and then performs the push restore. Before starting the restore it will prompt for comformation with information on both the source and target devices.

Paramaters:

User
    **Mandatory:** True
    A user that has permissions to perform a push restore.
Input file:
    **Mandatory:**  True
    First create a text file that contains all the paths you wish to restore. If you want to restore a single path (C:/ for example) create a text file with just that path.
    These can be files, directories, path seperators can be / or \. If you want to do a full restore provide the root path for the OS in the input file."

TargetDirectory
    **Mandatory:** : False
    Target location that exists on disk for the files to be restored. This will default to **C:/pushrestore**/** use / instead of \ in this path.

CloudLocation
    **Mandatory:**: True
    The Cloud you are restoring from. Options are: us1, us2, or eu1"
SourceComputerGUID
    **Mandatory:**: True
    The GUID of the CrashPlan device you are restoring data from.
TargetComputerGuid
    **Mandatory:**: True
    The GUID of the CrashPlan device you are pushing the restore to.

Example restore command:

pushrestore.ps1 -User restorePusher@example.com -inputFile .\pathsToRestore.txt -TargetDirectory "C:/RestoreTarget/" -CloudLocation us2 -SourceComputerGUID 424242424242424242 -TargetComputerGuid 3141592653589793238



