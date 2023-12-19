#!/bin/bash

set -e
set -o pipefail

# Hard-coded configurations
NEW_USER=""  # Leave empty if ownership change is not necessary.
NEW_GROUP="" # Both NEW_USER and NEW_GROUP must be set in order for chown to be executed!
MAX_PARALLEL_COPIES=5
RSYNC_PARAMETERS="-av --inplace"
COPY_QUEUE=()

# Check for even number of arguments
if [ $# -eq 0 ] || [ $(($# % 2)) -ne 0 ]; then
    echo "Usage: $0 <source_item1> <destination_folder1> [<source_item2> <destination_folder2> ...]"
    exit 1
fi

# Function to log messages
log_copy() {
    local message=$1
    local src=$2
    local dst=$3
    echo "[$(date)] $message - Source: $src, Destination: $dst"
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
        echo "Directory creation failed - $1"
        exit 1
    else
        echo "Directory created - $1"
    fi
    if [ -n "$NEW_USER" ] && [ -n "$NEW_GROUP" ]; then
        if ! chown "$NEW_USER:$NEW_GROUP" "$1"; then
            echo "Directory ownership change failed - $1"
        else
            echo "Directory ownership changed to ${NEW_USER}:${NEW_GROUP} - $1"
        fi
    fi
}

# Function to add files and directories to the queue
add_to_queue() {
    local src
    local dst
    src=$(process_path "$1")
    dst=$(process_path "$2")
    COPY_QUEUE+=("$src:$dst")
}

# Function to recursively parse directories and add to queue
parse_directory() {
    local dir="$1"
    local dst_dir="$2"

    for item in "$dir"/*; do
        if [ -d "$item" ]; then
            # If item is a directory, recurse into it
            parse_directory "$item" "$dst_dir/$(basename "$item")"
        elif [ -f "$item" ]; then
            # If item is a file, add to the queue
            local dst
            dst="$dst_dir/$(basename "$item")"
            add_to_queue "$item" "$dst"
        fi
    done
}

# Function to perform the copy operation
copy_file() {
    local src=$1
    local dst=$2
    # Ensure destination directory exists
    create_directory "$(dirname "$dst")"

    log_copy "Starting copy" "$src" "$dst"
    # shellcheck disable=SC2086
    if rsync $RSYNC_PARAMETERS "$src" "$dst"; then
        if [ -n "$NEW_USER" ] && [ -n "$NEW_GROUP" ]; then
            if ! chown "$NEW_USER:$NEW_GROUP" "$dst"; then
                log_copy "File ownership change failed" "$src" "$dst"
                return 1
            fi
            echo "File ownership changed to ${NEW_USER}:${NEW_GROUP} - $(basename "$dst")"
        fi
        log_copy "Copy successful" "$src" "$dst"
        return 0
    else
        log_copy "Copy failed" "$src" "$dst"
        return 1
    fi
}

# Populate the queue
while [ $# -gt 0 ]; do
    src_item=$(process_path "$1")
    dst_folder=$(process_path "$2")
    shift 2
    create_directory "$dst_folder"

    if [ -d "$src_item" ]; then
        parse_directory "$src_item" "${dst_folder}/$(basename "$src_item")"
    elif [ -f "$src_item" ]; then
        dst_path="${dst_folder}/$(basename "$src_item")"
        add_to_queue "$src_item" "$dst_path"
    fi
done

# Initialize error counter
error_count=0

# Function to manage parallel jobs
manage_jobs() {
    while [ "$(jobs -r | wc -l)" -ge $MAX_PARALLEL_COPIES ]; do
        wait -n
    done
}

# Process the queue
for item in "${COPY_QUEUE[@]}"; do
    IFS=':' read -r src dst <<<"$item"
    copy_file "$src" "$dst" &
    manage_jobs
done

# Wait for all background jobs to finish
wait

# Report the total number of errors
if [ $error_count -eq 0 ]; then
    echo "All files copied successfully."
else
    echo "$error_count file(s) failed to copy."
    exit 1
fi
