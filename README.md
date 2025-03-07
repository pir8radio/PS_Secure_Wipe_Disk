# PS_Secure_Wipe_Disk

## Overview

This PowerShell script leverages the built-in Windows Wipe function to write `0`s to all sectors of a drive. **Note:** This script is **not suitable for SSDs** because most modern SSDs have a secure wipe function built in.

## Features

This script will perform the following tasks:

1. Check if it was run with administrator privileges; if not, it restarts with admin privileges.
2. Retrieve a list of connected drives.
3. Allow the user to select the drive they wish to wipe.
4. Prompt the user to confirm the wipe operation.
5. Estimate the time required to wipe the disk based on its size.
6. Wipe the disk by writing `0`s to every sector.
7. Clean up any temporary files once the process is complete and exit.

## Usage Instructions

1. **Download** the PowerShell script.
2. Right-click the script file and select **Run with PowerShell**.
3. Confirm administrative privileges when prompted.
4. Follow the on-screen prompts to select and confirm the drive to wipe.
5. Monitor the process. The estimated completion time will vary based on the disk size.

**Warning:** This process is irreversible. Double-check the selected drive before proceeding.


![image](https://github.com/user-attachments/assets/93357ff3-7eac-49c6-9839-ac2004d7e9ec)
