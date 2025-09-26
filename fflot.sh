#!/bin/bash

set -e
set -o pipefail

# Hard-coded configurations
NEW_USER=""  # Leave empty if ownership change is not necessary.
NEW_GROUP="" # Both NEW_USER and NEW_GROUP must be set in order for chown to be executed!
MAX_PARALLEL_COPIES=5
RSYNC_PARAMETERS="-av"
COLOR=1
declare -a pids=()
error_count=0

# Check for even number of arguments
if [ $# -eq 0 ] || [ $(($# % 2)) -ne 0 ]; then
  if [ $COLOR -eq 1 ]; then
    echo -e "\e[0;38;5;39mUsage: $0 <source_item1> <destination_folder1> [<source_item2> <destination_folder2> ...]\e[0m"
  else
    echo "Usage: $0 <source_item1> <destination_folder1> [<source_item2> <destination_folder2> ...]"
  fi
    exit 1
fi

# Function to log messages
log_copy() {
    local message=$1
    local src=$2
    local dst=$3
    if [ $COLOR -eq 1 ]; then
      echo -e "[$(date)] \e[0;38;5;153m$message\e[0m - \e[2;38;5;228mSource:\e[0m $src, \e[2;38;5;159mDestination:\e[0m $dst"
    else
      echo "[$(date)] $message - Source: $src, Destination: $dst"
    fi
    
}

# Function to handle SIGINT and SIGTERM
handle_signal() {
    echo "Signal caught, exiting..."
    exit 1
}

# Setup signal handling
trap handle_signal SIGINT SIGTERM

# Function to process and unescape paths
process_path() {
    local path=$1
    echo "${path//\\ / }" # Replace '\ ' with ' '
}

# Make sure the given path exists, and change its ownership if NEW_USER and NEW_GROUP have been
# configured.
create_directory() {
    local path=$1
    if ! mkdir -p "$1"; then
      if [ $COLOR -eq 1 ]; then
        echo -e "\e[2;38;5;160mDirectory creation failed - $1\e[0m"
      else
        echo "Directory creation failed - $1"
      fi
      exit 1
    else
        echo "Directory created - $1"
    fi
    if [ -n "$NEW_USER" ] && [ -n "$NEW_GROUP" ]; then
      if ! chown "$NEW_USER:$NEW_GROUP" "$1"; then
        if [ $COLOR -eq 1 ]; then
          echo -e "\e[2;38;5;160mDirectory ownership change failed - $1\e[0m"
        else
          echo "Directory ownership change failed - $1"
        fi
      else
        if [ $COLOR -eq 1 ]; then
          echo -e "\e[0;38;5;27mDirectory ownership changed to ${NEW_USER}:${NEW_GROUP} - $1\e[0m"
        else
          echo "Directory ownership changed to ${NEW_USER}:${NEW_GROUP} - $1"
        fi
      fi
    fi
}

# Function to perform the copy operation
perform_rsync() {
    local src=$1
    local dst=$2
    local rsync_opts=($RSYNC_PARAMETERS)

    if [ -n "$NEW_USER" ] && [ -n "$NEW_GROUP" ]; then
        rsync_opts+=(--chown="$NEW_USER:$NEW_GROUP")
    fi

    log_copy "Starting rsync" "$src" "$dst"
    # shellcheck disable=SC2086
    if rsync "${rsync_opts[@]}" "$src" "$dst"; then
        log_copy "Rsync successful" "$src" "$dst"
        return 0
    else
        log_copy "Rsync failed" "$src" "$dst"
        return 1
    fi
}

# Populate the queue
while [ $# -gt 0 ]; do
    src_item=$(process_path "$1")
    dst_folder=$(process_path "$2")
    shift 2
    create_directory "$dst_folder"

    perform_rsync "$src_item" "$dst_folder" &
    pids+=($!)

    while [ "$(jobs -r | wc -l)" -ge $MAX_PARALLEL_COPIES ]; do
        wait -n
    done
done

# Wait for all background jobs to finish
for pid in "${pids[@]}"; do
    if ! wait "$pid"; then
        error_count=$((error_count + 1))
    fi
done

# Report the total number of errors
if [ $error_count -eq 0 ]; then
    echo "All files copied successfully."
else
    echo "$error_count file(s) failed to copy."
    exit 1
fi
