#!/bin/bash

# This script manages the automatic weekly update and upgrade process for a Raspberry Pi
# system that utilizes a file overlay for its root filesystem. The script disables the
# overlay, performs system updates, and then re-enables the overlay, ensuring that all
# updates are applied correctly and persist after reboots.

# Define directories and files
LOG_DIR="/var/log/weekly_upgrade"       # Directory to store log files
LOG_FILE="$LOG_DIR/upgrade.log"         # Log file where script actions are recorded
STATE_FILE="/path/to/upgrade_state.txt" # File to track the current state and retry count
MAX_RETRIES=3                           # Maximum number of retries to prevent infinite looping

# Ensure the log directory exists
mkdir -p "$LOG_DIR"

# Function to log messages with timestamps
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Function to update the state file with the current state and retry count
update_state() {
    echo "$1:$2" > "$STATE_FILE"
}

# Function to read the current state and retry count from the state file
read_state() {
    if [ -f "$STATE_FILE" ]; then
        cat "$STATE_FILE"
    else
        echo "start:0"  # Default to "start" state with 0 retries if no state file exists
    fi
}

# Function to check if the retry count has exceeded the maximum allowed retries
check_retries() {
    local retries=$1
    if [ "$retries" -ge "$MAX_RETRIES" ]; then
        log_message "Maximum retries reached. Exiting to prevent infinite loop."
        exit 1
    fi
}

# Function to check for available upgrades using --dry-run
check_for_upgrades() {
    local upgradeable
    # Perform a dry-run of apt-get upgrade to see if there are any packages to be upgraded
    upgradeable=$(apt-get upgrade --dry-run | grep "upgraded,")
    # If no upgrades are available, log the message, reset the state, and exit the script
    if [[ "$upgradeable" == *"0 upgraded"* ]]; then
        log_message "No upgrades available. Skipping this run."
        update_state "start" "0"
        exit 0
    fi
}

# Read the current state and retry count from the state file
CURRENT_STATE=$(read_state)
STATE=$(echo "$CURRENT_STATE" | cut -d':' -f1)        # Extract the state (first part)
RETRY_COUNT=$(echo "$CURRENT_STATE" | cut -d':' -f2)  # Extract the retry count (second part)

# Check if the retry count has reached the maximum allowed to prevent infinite loops
check_retries "$RETRY_COUNT"

# Check for available upgrades before proceeding if the state is "start"
if [ "$STATE" == "start" ]; then
    check_for_upgrades
fi

# Increment the retry count for this run
RETRY_COUNT=$((RETRY_COUNT + 1))

# Main logic of the script based on the current state
case "$STATE" in
    "start")
        # Step 1: Disable file overlay
        log_message "Disabling file overlay..."
        sudo sed -i 's/overlayroot="tmpfs"/overlayroot="disabled"/' /etc/overlayroot.conf

        # Update the state to "overlay_disabled" and reboot the system
        update_state "overlay_disabled" "$RETRY_COUNT"
        log_message "Rebooting to disable overlay..."
        sudo reboot
        ;;
    
    "overlay_disabled")
        # Step 2: Perform system update and upgrade
        log_message "Running system update and upgrade..."
        sudo apt-get update | tee -a "$LOG_FILE"          # Update package lists
        sudo apt-get upgrade -y | tee -a "$LOG_FILE"      # Upgrade all upgradable packages
        sudo apt-get autoremove -y | tee -a "$LOG_FILE"   # Remove unnecessary packages

        # Update the state to "upgraded" and reboot the system
        update_state "upgraded" "$RETRY_COUNT"
        log_message "Rebooting to apply changes..."
        sudo reboot
        ;;

    "upgraded")
        # Step 3: Re-enable file overlay
        log_message "Re-enabling file overlay..."
        sudo sed -i 's/overlayroot="disabled"/overlayroot="tmpfs"/' /etc/overlayroot.conf

        # Update the state to "overlay_enabled" and reboot the system
        update_state "overlay_enabled" "$RETRY_COUNT"
        log_message "Rebooting to re-enable overlay..."
        sudo reboot
        ;;

    "overlay_enabled")
        # Step 4: Verify that upgrades persist after overlay is re-enabled
        log_message "Verifying that upgrades persist..."
        apt-mark showmanual > /tmp/manual_packages.txt   # Save manually installed packages to a file

        # Check if the upgrades have persisted by looking for package entries in the dpkg log
        if grep -q "^Package:" /var/log/dpkg.log; then
            log_message "Upgrades are present and persistent."
        else
            log_message "Warning: Upgrades may not have persisted!"
        fi

        # Reset the state to "start" and reset the retry count
        update_state "start" "0"
        log_message "Process completed successfully. Resetting state."
        ;;
    
    *)
        # Handle unexpected states by resetting the state to "start"
        log_message "Unknown state: $STATE. Resetting state to start."
        update_state "start" "0"
        ;;
esac
