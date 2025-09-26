#!/bin/bash

set -e
set -o pipefail

# Default configurations - can be overridden in command line
NEW_USER=""  # Leave empty if ownership change is not necessary.
NEW_GROUP="" # Both NEW_USER and NEW_GROUP must be set in order for chown to be executed!
MAX_PARALLEL_COPIES=5
RSYNC_PARAMETERS="-av"
COLOR=1
declare -a pids=()
declare -a cleanup_paths=()
declare -A pid_to_src_dst=()
declare -a failed_copies=()
error_count=0

# Function to display usage information
usage() {
    echo "Usage: $0 [OPTIONS] <source_item1> <destination_folder1> [<source_item2> <destination_folder2> ...]"
    echo "Options:"
    echo "  -u, --user <user>        Set the new user for copied files."
    echo "  -g, --group <group>      Set the new group for copied files."
    echo "  -p, --parallel <num>     Set the maximum number of parallel rsync jobs (default: 5)."
    echo "  -r, --rsync-params <params> Set the parameters for rsync (default: '-av')."
    echo "  -c, --no-color           Disable color output."
    echo "  -h, --help               Display this help message."
    echo "Note: Paths with spaces or special characters should be properly quoted."
    exit 1
}

# Parse command-line options
while [[ "$1" =~ ^- ]]; do
    case "$1" in
        -u|--user)
            NEW_USER="$2"
            shift 2
            ;;
        -g|--group)
            NEW_GROUP="$2"
            shift 2
            ;;
        -p|--parallel)
            MAX_PARALLEL_COPIES="$2"
            shift 2
            ;;
        -r|--rsync-params)
            RSYNC_PARAMETERS="$2"
            shift 2
            ;;
        -c|--no-color)
            COLOR=0
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Check for even number of arguments
if [ $# -eq 0 ] || [ $(($# % 2)) -ne 0 ]; then
    usage
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
    echo -e "\nSignal caught. Terminating running rsync processes..."
    # Kill all child processes (rsync jobs) spawned by this script to prevent orphans.
    local pids_to_kill
    pids_to_kill=$(jobs -p)
    if [ -n "$pids_to_kill" ]; then
        # The space-separated list of PIDs is fed to kill.
        # Errors are redirected to /dev/null to avoid messages about processes
        # that have already finished.
        kill $pids_to_kill >/dev/null 2>&1
    fi
    echo "All rsync jobs terminated. Exiting."
    exit 1
}

# Setup signal handling
trap handle_signal SIGINT SIGTERM

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

    if [ -d "$src" ]; then
        # If the source is a directory, ensure it doesn't have a trailing slash
        # to make rsync copy the directory itself.
        # The `${src%/}` syntax removes the trailing slash.
        src=${src%/}
    fi

    if [ -n "$NEW_USER" ] && [ -n "$NEW_GROUP" ]; then
        rsync_opts+=(--chown="$NEW_USER:$NEW_GROUP")
    fi

    log_copy "Starting rsync" "$src" "$dst"
    # shellcheck disable=SC2086
    if rsync "${rsync_opts[@]}" -- "$src" "$dst"; then
        log_copy "Rsync successful" "$src" "$dst"
        return 0
    else
        log_copy "Rsync failed" "$src" "$dst"
        return 1
    fi
}

# Function to clean up leftover '_un' files
cleanup_un_files() {
    local paths=("$@")
    echo "Checking for and removing leftover '_un' files..."
    for path in "${paths[@]}"; do
        if [ -d "$path" ]; then
            # Find and delete "_un" files in the affected directories. These seem to be temporary rsync files that are sometimes left around.
            find "$path" -type f -name "_un" -delete
        fi
    done
    echo "Cleanup complete."
}

# Populate the queue
while [ $# -gt 0 ]; do
    src_item="$1"
    dst_folder="$2"
    shift 2
    create_directory "$dst_folder"
    cleanup_paths+=("$src_item" "$dst_folder")

    perform_rsync "$src_item" "$dst_folder" &
    pid=$!
    pids+=($pid)
    pid_to_src_dst[$pid]="$src_item -> $dst_folder"

    while [ "$(jobs -r | wc -l)" -ge $MAX_PARALLEL_COPIES ]; do
        wait -n
    done
done

# Wait for all background jobs to finish
for pid in "${pids[@]}"; do
    if ! wait "$pid"; then
        error_count=$((error_count + 1))
        failed_copies+=("${pid_to_src_dst[$pid]}")
    fi
done

# Clean up any leftover files from the source directories
cleanup_un_files "${cleanup_paths[@]}"

# Report the total number of errors
if [ $error_count -eq 0 ]; then
    echo "All files copied successfully."
else
    echo "$error_count file(s) failed to copy."
    if [ ${#failed_copies[@]} -gt 0 ]; then
        echo "The following copy operations failed:"
        for copy in "${failed_copies[@]}"; do
            echo "  - $copy"
        done
    fi
    exit 1
fi
