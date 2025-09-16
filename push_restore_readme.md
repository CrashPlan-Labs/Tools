PushRestore.ps1  
License: MIT  
This script kicks off a push restore for CrashPlan using the `/api/PushRestoreJob` method. First it makes a call to set up a web restore session, and then performs the push restore. Before starting the restore it will prompt for comformation with information on both the source and target devices.  
  
Paramaters:  
  
User  
- **Mandatory:** True.  
- A user that has permissions to perform a push restore.  

BaseUrl  
- **Mandatory:**: True.  
- The Cloud you are restoring from, Use the full server address.

SourceComputerGuid  
- **Mandatory:**: True.  
- The GUID of the CrashPlan device you are restoring data from.  

TargetComputerGuid  
- **Mandatory:**: True.  
- The GUID of the CrashPlan device you are pushing the restore to.  

InputFile:  
- **Mandatory:**  False.  
- First create a text file that contains all the paths you wish to restore. If you want to restore a single path (C:/ for example) create a text file with just that path.  
- These can be files, directories, path seperators can be / or \. If you want to do a full restore provide the root path for the OS in the input file."  
- If not provided the full main system drive will be selected based on the OS of the soureComputerGuid. `C:/` for windows `/` for macOS and Linux.

TargetDirectory  
- **Mandatory:** : False  
- Target location that exists on disk for the files to be restored. This will default to **C:/pushrestore/SourceComputerGuid**, or **/pushrestore/SourceComputerGuid/** depending on the Operating system of the target endpoint.  Use / instead of \ in this path.  

RestoreDate
- **Mandatory:** False
- Date to restore files from. If not provided today's date will be used. In a yyyy-MM-dd format forexample: 2025-12-31

RestoreDeletedFiles
- **Mandatory:** False
- Restore deleted files or not. Add paramater to restore deleted files, false by default.

Example restore commands:  
  
./push_restore.ps1 -User restorePusher@example.com -Baseurl https://console.us2.crashplan.com -SourceComputerGuid 424242424242424242 -TargetComputerGuid 3141592653589793238 -inputFile .\pathsToRestore.txt -TargetDirectory "C:/RestoreTarget/" -RestoreDate 2025-12-31 -RestoreDeletedFiles

./push_restore.ps1 -User restorePusher@example.com -Baseurl https://console.us2.crashplan.com -SourceComputerGuid 424242424242424242 -TargetComputerGuid 3141592653589793238  
