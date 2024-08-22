# Raspberry Pi Weekly System Upgrade Script

## Introduction

This script is intended to be used for handling the process of automatic weekly update and upgrade of a Raspberry Pi system using a file overlay over its root filesystem. The file overlay mechanism may add more complexities during an update. This script will ensure updates are applied properly and persist across reboots.

## Create a Second Permenant Partition **(REQUIRED)**

This overlay is wonderful, except for application configurations or parts of the system you might want to keep around between boots, like logs and client configurations. This can be done by creating a small partition at the end and manually enlarging the rootfs partition using something like `parted` or other partitioning tools.

To successfully run this script a secondary parition that allows bot read/write permissions is *REQUIRED*.

Creating the read/write (r/w) partiton can be found in another section in this repo (LINK)

## Usage of Permanent Partitions (OPTIONAL)

-Example of how to move `\var\logs` to a small r/w partition called `/perm`

1. Logging Services:

   ```bash
   sudo systemctl stop rsyslog
   sudo systemctl stop systemd-journald
   ```

2. Make the New Log Directory:

   ```bash
   sudo mkdir -p /perm/logs/syslogs
   ```

3. Relocate the Logs:

   ```bash
   sudo rsync -a /var/log/ /perm/logs/syslogs/
   ```

4. Rename Old Log Directory:

   ```bash
   sudo mv /var/log /var/log.old
   ```

5. Create a Symbolic Link:

   ```bash
   sudo ln -s /perm/logs/syslogs /var/log
   ```

6. Restart Logging Services:

   ```bash
   sudo systemctl start rsyslog
   sudo systemctl start systemd-journald
   ```

7. Cleaning (Optional):

   ```bash
   sudo rm -rf /var/log.old
   ```

## Purpose

It is common to use an overlay filesystem on the root partition in order to protect system files within a Raspberry Pi. This makes things a bit more complicated when applying system updates because if not managed well, changes made during the upgrade will not persist. The script automates the process of disabling the overlay, applying updates, and re-enabling the overlay so that all updates are properly applied and persistent over reboots.

## Elaborate Process

The script comes in a few stages:

1. Search for Upgrades
   - First of all, the script runs a dry-run of the upgrade process to check for updates. If it finds none, it will log the occurrence and skip through the rest of the process for that week.

2. Turn Off the Overlay on Files:
   - If updates are available, the script disables the file overlay by changing the configuration file and then reboots the system.

3. Apply Patches
   - Full system update and upgrade followed by `autoremove` to clean up extra packages after reboot with the overlay disabled.

4. Re-enable File Overlay:
   - The script re-enables the file overlay and then reboots the system to have the change take effect.

5. Verify That Updates Persist:
   - The script finally verifies whether the updates have persisted by checking the logs on the system. If everything is correct, it sets the state of the script to get ready for the next run.

## Choosing Location and Configuring weekly_upgrade.sh

To configure the permissions for the `weekly_upgrade.sh` script, you should ensure that it is executable by the user who will be running the script (typically root, since it requires elevated privileges for tasks like system updates, disabling/enabling overlays, and rebooting the system).

Here’s how you should set the permissions:

### Setting Permissions

1. **Choose location of weekly_upgrade.sh**:
   - Create a location for the bash script in a location not easily accessible such as `/root` or similiar.  This path needs to replace wherever you see /path/to/weekly_upgrade in the below instructions.

   ```bash
   sudo chmod +x /path/to/weekly_upgrade.sh
   ```

2. **Make the Script Executable**:
   - You need to make the script executable so that it can be run as a command.

   ```bash
   sudo chmod +x /path/to/weekly_upgrade.sh
   ```

3. **Restrict Write Permissions**:
   - Since this script performs critical system operations, you should restrict write permissions to prevent unauthorized users from modifying it.

   ```bash
   sudo chmod 744 /path/to/weekly_upgrade.sh
   ```

### Verifying Permissions

After setting the permissions, you can verify them using the `ls -l` command:

```bash
ls -l /path/to/weekly_upgrade.sh
```

You should see output similar to:

```plaintext
-rwxr--r-- 1 root root 4096 Aug 21 03:00 /path/to/weekly_upgrade.sh
```

This output indicates that the script is owned by `root`, and it has the correct permissions (`rwxr--r--`).

### Why These Permissions?

- **Executable by Root**: The script must be executable because it performs tasks such as system updates and reboots, which require the script to be run as a command.
- **Writable Only by Root**: Restricting write permissions ensures that only the root user can modify the script, preventing accidental or malicious changes by other users.
- **Readable by Others**: The script is readable by other users (if needed), but they cannot execute or modify it. This may be useful for auditing purposes or for allowing users to view the script’s contents.

### Update weekly_upgrade.sh Variables

-Open the weekly_upgrade.sh in your text editor of choice and change the script variables at top to suit your current enviroment.  

```bash
#!/bin/bash

# Define directories and files
LOG_DIR="/var/log/weekly_upgrade"       # Directory to store log files.
LOG_FILE="$LOG_DIR/upgrade.log"         # Log file where script actions are recorded
STATE_FILE="/path/to/upgrade_state.txt" # File to track the current state and retry count
MAX_RETRIES=3                           # Maximum number of retries to prevent infinite looping

# Ensure the log directory exists
mkdir -p "$LOG_DIR"

```

-Update `LOG_DIR` to match where you current logging is being stored.  You can leave this in the original file-overlay system or following the instructions of how to move the log files to a secondary partition with r/w
-Update STATE_FILE where you can it to be stored.  **THIS FILE NEEDS TO BE ON THE SECONDARY PARTITION.**  The update script will reboot the pi two times and if the upgrade_state.txt file is not stored, then it will forever be in the first state and never actually apply upgrades.  Look up the other guide in this repo HERE to find out how to create the partition when making a new Pi image.

### Additional Security Considerations

- **Script Ownership**: Ensure the script is owned by the `root` user. If it's not, you can change the ownership with:

  ```bash
  sudo chown root:root /path/to/weekly_upgrade.sh
  ```

- **Use of Sudo**: Since the script requires root privileges to execute, it should be run with `sudo` if executed manually. When scheduled with `cron` for root, this happens automatically.
- **Script Location**: Store the script in a secure directory, such as `/usr/local/sbin` or another directory where administrative scripts are typically stored. This further restricts unauthorized access.

By following these steps, you can ensure that the `weekly_upgrade.sh` script is both secure and functional, minimizing the risk of unauthorized modifications while allowing it to perform its intended system maintenance tasks.

## Configuring the Cron Job

Now, to get this script executed automatically each week, you would put it into a cron job on your Raspberry Pi.

1. Crontab Edit:

   ```bash
   sudo crontab -e
   ```

2. Add Cron Job:
   - Add the below line to crontab scheduling the above script for every Sunday at 3 A.M:

   ```bash
   0 3 * * 0 /path/to/weekly_upgrade.sh
   ```

3. Save and Exit:
   - Once that's done, save the changes to crontab and exit out of the editor. The script will automatically execute at the set time.

## Conclusion

The purpose of this script is to automatically manage the updating process for your Raspberry Pi system while, at the same time, managing the complexities introduced by the file overlay on the root file system. This allows for the updates to be carried out and maintained correctly, in order to make sure it all lasts over reboots—it basically helps maintain stability and secure the system with less human intervention.
