#!/bin/bash

# Default values - EDIT SO YOUR OWN USERNAME IS HERE
# First server values
SERVER1_USERNAME="mtarigha"
SERVER1_HOSTNAME="rubichest.ece.ucdavis.edu"
# Second server values
SERVER2_USERNAME="mtarigha"
SERVER2_HOSTNAME="hpc2.engr.ucdavis.edu"
# Base directiries of first server to sync
SERVER1_DIRECTORIES=()
# Base directiries of second server to sync
SERVER2_DIRECTORIES=()


# --- Don't Edit Beyond This ---
# parse input arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        # First username short and long flags, long flag supports both = and space seperated values
        --username1=*)
            # remove the "--username=" prefix from argument and assign to USERNAME
            SERVER1_USERNAME="${1#*=}"
            shift
            ;;
        --username1)
            # assign second argument to USERNAME (firs argument is --username) and shift by 2
            SERVER1_USERNAME="$2"
            shift 2
            ;;
        -u1)
            # assign second argument to USERNAME (firs argument is --username) and shift by 2
            SERVER1_USERNAME="$2"
            shift 2
            ;;
        
        # First hostname short and long flags
        --hostname1=*)
            SERVER1_HOSTNAME="${1#*=}"
            shift
            ;;
        --hostname1)
            SERVER1_HOSTNAME="$2"
            shift 2
            ;;
        -h1)
            SERVER1_HOSTNAME="$2"
            shift 2
            ;;

        # Second username short and long flags
        --username2=*)
            SERVER2_USERNAME="${1#*=}"
            shift
            ;;
        --username2)
            SERVER2_USERNAME="$2"
            shift 2
            ;;
        -u2)
            SERVER2_USERNAME="$2"
            shift 2
            ;;
        
        # Second hostname short and long flags
        --hostname2=*)
            SERVER2_HOSTNAME="${1#*=}"
            shift
            ;;
        --hostname2)
            SERVER2_HOSTNAME="$2"
            shift 2
            ;;
        -h2)
            SERVER2_HOSTNAME="$2"
            shift 2
            ;;

        # First directory list
        --directory1=*)
            DIR="${1#*=}"
            SERVER1_DIRECTORIES+=($DIR)
            shift
            ;;
        --directory1)
            SERVER1_DIRECTORIES+=($2)
            shift 2
            ;;
        -d1)
            SERVER1_DIRECTORIES+=($2)
            shift 2
            ;;

        # Second directory list
        --directory2=*)
            DIR="${1#*=}"
            SERVER2_DIRECTORIES+=($DIR)
            shift
            ;;
        --directory2)
            SERVER2_DIRECTORIES+=($2)
            shift 2
            ;;
        -d2)
            SERVER2_DIRECTORIES+=($2)
            shift 2
            ;;

        # help
        --help | -h)
    cat <<EOF
Usage: ./remote_sync.sh [OPTIONS]

This script sets up bidirectional sync using Unison between directory pairs on two remote servers.
It mounts the remote directories locally using sshfs, launches syncs in the background, and
cleans everything up when you type "stop".

OPTIONS:

  --username1, -u1       Username for first remote server (default: mtarigha)
  --hostname1, -h1       Hostname for first remote server (default: rubichest.ece.ucdavis.edu)

  --username2, -u2       Username for second remote server (default: mtarigha)
  --hostname2, -h2       Hostname for second remote server (default: hpc2.engr.ucdavis.edu)

  --directory1, -d1      Base directory on server 1 to sync. Can be repeated for multiple dirs.
                         Example: --directory1=/home/user/project1 --directory1=/home/user/project2

  --directory2, -d2      Base directory on server 2 to sync. Must match count of --directory1.
                         Example: --directory2=/home/user/project1 --directory2=/home/user/project2

  --help, -h             Show this help message and exit

NOTES:
  • If no --directory1/2 options are provided, both default to: /home/<username>/shared
  • Each pair of directories is mounted locally under ./remote_sync/tmp_files/
  • Unison syncs each pair in background every second
  • You can stop all syncs by typing: stop

REQUIREMENTS:
  • sshfs and unison must be installed on the local machine
  • SSH access to both servers must be set up with key-based authentication
  • Your SSH key must be loaded using: 
        eval "\$(ssh-agent -s)" && ssh-add ~/.ssh/id_rsa

  ⚠️  Do NOT include your password or private key in this script.
  ⚠️  Avoid running this script if directory pairs are mismatched or if remote paths are incorrect.
  ⚠️  Unison will detect empty roots as deletions and may remove files if 'confirmbigdel' is not enabled.
  ⚠️  You are responsible for verifying that mounted paths do not overlap or interfere with active programs.

LOGS:
  • Logs are saved in ~/.unison as timestamped .txt files
  • Check logs for detailed sync activity

EXAMPLE:
  ./remote_sync.sh -u1 user1 -h1 server1.com -u2 user2 -h2 server2.com \\
      -d1 /home/user1/shared1 -d1 /home/user1/shared2 \\
      -d2 /home/user2/shared1 -d2 /home/user2/shared2

EOF
    exit 0
        ;;

        # Unknown option
        *)
        echo "Unknown option: $1"
        exit 1
        ;;
    esac
done

# Add "./shared" directory to the first list if the directory list is empty
if [ ${#SERVER1_DIRECTORIES[@]} -eq 0 ]; then
    SERVER1_DIRECTORIES+=("/home/mtarigha/shared")
fi
# Add "./shared" directory to the second list if the directory list is empty
if [ ${#SERVER2_DIRECTORIES[@]} -eq 0 ]; then
    SERVER2_DIRECTORIES+=("/home/mtarigha/shared")
fi

# Test - print values - remove later
#echo
#echo "FIRST SERVER USERNAME: $SERVER1_USERNAME"
#echo "FIRST SERVER HOSTNAME: $SERVER1_HOSTNAME"
#echo "FIRST SERVER List of Base Directories:"
#for dir in "${SERVER1_DIRECTORIES[@]}"; do
#    echo "  - $dir"
#done
#echo
#echo "SECOND SERVER USERNAME: $SERVER2_USERNAME"
#echo "SECOND SERVER HOSTNAME: $SERVER2_HOSTNAME"
#echo "SECOND SERVER List of Base Directories:"
#for dir in "${SERVER2_DIRECTORIES[@]}"; do
#    echo "  - $dir"
#done
#echo

# check if number of directories are same in both lists
LEN_S1DIR=${#SERVER1_DIRECTORIES[@]}
LEN_S2DIR=${#SERVER2_DIRECTORIES[@]}

# Compare and exit with error if not equal
if [[ $LEN_S1DIR -ne $LEN_S2DIR ]]; then
    echo "Error: Directory list lengths do not match."
    echo "$SERVER1_HOSTNAME has $LEN_S1DIR items, $SERVER2_HOSTNAME has $LEN_S2DIR items."
    exit 1
fi

# Create ./remote_sync and ./remote_sync/tmp_files
mkdir -p ./remote_sync/tmp_files || { echo "Failed to create necessary tmp directories"; exit 1; }

# Clear contents of ./remote_sync/tmp_files
rm -rf ./remote_sync/tmp_files/*

# Unmount any stale directories (if script crashes and directories are not unmounted in the previous run)
MOUNT_LOG="./remote_sync/mounted_log.txt"
if [ -f "$MOUNT_LOG" ]; then
    while read -r mount_path; do
        if mountpoint -q "$mount_path"; then
            echo "Unmounting stale mount: $mount_path"
            fusermount -u "$mount_path" || echo "Failed to unmount $mount_path"
        fi
    done < "$MOUNT_LOG"
    > "$MOUNT_LOG"  # Clear the log
fi

# File to track running unison PIDs
SYNC_PIDS_FILE="./remote_sync/tmp_files/unison_pids.txt"

for ((i=0; i<LEN_S1DIR; i++)); do
    # create and mount dir for first server
    LOCAL1="./remote_sync/tmp_files/DIR_${i}_${SERVER1_HOSTNAME}"
    mkdir -p "$LOCAL1"
    REMOTE1="${SERVER1_USERNAME}@${SERVER1_HOSTNAME}:${SERVER1_DIRECTORIES[$i]}"
    echo "Mounting $REMOTE1 to $LOCAL1"
    sshfs -o reconnect,IdentityFile=~/.ssh/id_rsa "$REMOTE1" "$LOCAL1"  && echo "$LOCAL1" >> "$MOUNT_LOG" || { echo "Failed to mount $REMOTE1"; exit 1; }
    
    # create and mount dir for second server
    LOCAL2="./remote_sync/tmp_files/DIR_${i}_${SERVER2_HOSTNAME}"
    mkdir -p "$LOCAL2"
    REMOTE2="${SERVER2_USERNAME}@${SERVER2_HOSTNAME}:${SERVER2_DIRECTORIES[$i]}"
    echo "Mounting $REMOTE2 to $LOCAL2"
    sshfs -o reconnect,IdentityFile=~/.ssh/id_rsa "$REMOTE2" "$LOCAL2"  && echo "$LOCAL2" >> "$MOUNT_LOG" || { echo "Failed to mount $REMOTE2"; exit 1; }

    LOGFILE="unison_log_${i}_$(date +"%Y%m%d_%H%M%S").txt"

    unison "$LOCAL1" "$LOCAL2" -repeat 1 -auto -batch -prefer newer -log -silent -logfile "$LOGFILE" &

    # store sync PIDs to use to stop sync ops when commanded stop
    UNISON_PID=$!
    echo "$UNISON_PID" >> "$SYNC_PIDS_FILE"
done

echo "All syncs started."
echo "Type 'stop' and press Enter to stop all syncs and unmount directories."
while true; do
    read -rp "> " input
    if [[ "$input" == "stop" ]]; then
        echo "Stopping syncs and unmounting directories..."
        break
    else
        echo "Unrecognized input. Type 'stop' to proceed with cleanup."
    fi
done

# stop all sync
# Stop all unison sync processes
if [ -f "$SYNC_PIDS_FILE" ]; then
    while read -r pid; do
        if kill -0 "$pid" 2>/dev/null; then
            echo "Stopping Unison process $pid"
            kill "$pid"
        fi
    done < "$SYNC_PIDS_FILE"
    rm "$SYNC_PIDS_FILE"
fi

# Unmount all sshfs mount points
if [ -f "$MOUNT_LOG" ]; then
    while read -r mount_path; do
        echo "Unmounting $mount_path"
        fusermount -u "$mount_path" || echo "Failed to unmount $mount_path"
    done < "$MOUNT_LOG"
    rm "$MOUNT_LOG"
fi

# Clear contents of ./remote_sync/tmp_files
rm -rf ./remote_sync/tmp_files/*

exit 0