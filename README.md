# PS_Secure_Wipe_Disk
This Power Shell Script uses the built in windows Wipe function to write 0's to all sectors of a drive.   Not for SSD's because most modern SSD's have a secure wipe function built in.

This script will do the following:
1. Check to see if it was run with admin privs, if not restart with admin privs.
2. Get a list of connected drives.
3. User then picks the drive from the list they wish to Wipe.
4. Script will make you confirm the wipe.
5. Based on the size of the disk, it will estimate how long the wipe will take.
6. Wipes disk and writes 0's to every sector.
7. Once done cleans up any temp files and exits.
