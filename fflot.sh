#!/bin/bash

# Default configurations
NEW_USER=""
NEW_GROUP=""
FILE_MODE=""
DIR_MODE=""
MAX_PARALLEL_COPIES=2
RSYNC_PARAMETERS="-avh"
COLOR=1

declare -a pids=()
declare -a cleanup_paths=()
declare -a pid_descriptions=()
declare -a failed_copies=()
error_count=0
current_running=0

usage() {
    echo "Usage: $0 [OPTIONS] <src1> <dst1> ..."
    exit 1
}



while [[ "$1" =~ ^- ]]; do
    case "$1" in
        -u|--user) NEW_USER="$2"; shift 2 ;;
        -g|--group) NEW_GROUP="$2"; shift 2 ;;
        -f|--file-mode) FILE_MODE="$2"; shift 2 ;;
        -d|--dir-mode) DIR_MODE="$2"; shift 2 ;;
        -p|--parallel) MAX_PARALLEL_COPIES="$2"; shift 2 ;;
        -r|--rsync-params) RSYNC_PARAMETERS="$2"; shift 2 ;;
        -c|--no-color) COLOR=0; shift ;;
        -h|--help) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

# Check for even number of arguments (after configuration arguments)
if [ $# -eq 0 ] || [ $(($# % 2)) -ne 0 ]; then usage; fi

log_copy() {
    local msg=$1 src=$2 dst=$3
    [ $COLOR -eq 1 ] && echo -e "[$(date)] \e[0;38;5;153m$msg\e[0m - Source: $src, Dst: $dst" || echo "[$(date)] $msg - Source: $src, Dst: $dst"
}

# Function to process and unescape paths
process_path() {
    local path=$1
    echo "${path//\\ / }" # Replace '\ ' with ' '
}

create_directory() {
    local path=$1
    [ ! -d "$path" ] && mkdir -p "$path"
    [ -n "$NEW_USER" ] && [ -n "$NEW_GROUP" ] && chown "$NEW_USER:$NEW_GROUP" "$path" 2>/dev/null
    [ -n "$DIR_MODE" ] && chmod "$DIR_MODE" "$path" 2>/dev/null
}

cleanup_un_files() {
    echo "Cleaning up '_un' files..."
    for path in "$@"; do
        if [ -d "$path" ]; then
            # Strictly maxdepth 1 to avoid CACHEDEV traversal
            find "$path" -maxdepth 1 -type f -name "_un" -exec rm -f {} \; 2>/dev/null
        fi
    done
}

# The actual workhorse function executed in the background
run_job() {
    local src=$(process_path "$1")
    local dst=$(process_path "$2")
    local opts=($RSYNC_PARAMETERS)
    # Permission handling (works in rsync 2.6.7+)
    local chmod_dir_arg=""
    local chmod_file_arg=""
    [ -n "$DIR_MODE" ] && chmod_dir_arg="$DIR_MODE"
    [ -n "$FILE_MODE" ] && chmod_file_arg="$FILE_MODE"

    # 1. Perform Rsync
    local src_clean="${src%/}"
    if rsync "${opts[@]}" -- "$src_clean" "$dst"; then
        # 2. Manual post-copy chown (since --chown is missing)
        local item_name
        item_name=$(basename "$src_clean")
        if [ -n "$NEW_USER" ] && [ -n "$NEW_GROUP" ]; then
            # Target the specific item inside the destination folder
            local item_name=$(basename "$src")
            chown -R "$NEW_USER:$NEW_GROUP" "$dst/$item_name" 2>/dev/null
        fi
        [[ -d "$dst/$item_name" ]] && [ -n "$chmod_dir_arg" ] && chmod "$chmod_dir_arg" "$dst/$item_name"
        if [[ -d "$dst/$item_name" ]]; then
            [ -n "$chmod_dir_arg" ]  && find "$dst/$item_name" -type d -exec chmod "$chmod_dir_arg" {} +
            [ -n "$chmod_file_arg" ] && find "$dst/$item_name" -type f -exec chmod "$chmod_file_arg" {} +
        fi
        [[ -f "$dst/$item_name" ]] && [ -n "$chmod_file_arg" ] && chmod "$chmod_file_arg" "$dst/$item_name"
        return 0
    else
        return 1
    fi
}

while [ $# -gt 0 ]; do
    src_item=$(process_path "$1")
    dst_folder=$(process_path "$2")
    shift 2

    create_directory "$dst_folder"

    # Resolve paths for cleanup
    src_parent=$(cd "$(dirname "$src_item")" && pwd 2>/dev/null || echo "$(dirname "$src_item")")
    dstbase="$dst_folder/$(basename "$src_item")"
    dst_resolved=$(cd "$dstbase" && pwd 2>/dev/null || echo "$dst_folder/$(basename "$src_item")")
    cleanup_paths+=( "$src_parent" "$dst_resolved" )

    log_copy "Starting job" "$src_item" "$dst_folder"
    
    # Run in subshell to bundle rsync + chown
    ( run_job "$src_item" "$dst_folder" ) &

    pid=$!
    pids+=( $pid )
    pid_descriptions[$pid]="$src_item -> $dst_folder"
    ((current_running++))

    # Process management loop
    while [ "$current_running" -ge "$MAX_PARALLEL_COPIES" ]; do
        sleep 1 # Avoid CPU pinning in 3.2
        current_running=0
        for p in "${pids[@]}"; do
            kill -0 "$p" 2>/dev/null && ((current_running++))
        done
    done
done

for pid in "${pids[@]}"; do
    if ! wait "$pid"; then
        ((error_count++))
        failed_copies+=( "${pid_descriptions[$pid]}" )
    fi
done

cleanup_un_files "${cleanup_paths[@]}"

[ "$error_count" -eq 0 ] && echo "Success." || { echo "Failures: $error_count"; exit 1; }
