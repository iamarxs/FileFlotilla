# FileFlotilla

### *Note: This is a modified version that was purpose-built for QNAP-TS233 (with Entware-installed newer rsync version, but this should work with the built-in one as well). This probably works just as well for other QNAP NAS devices of the same era and capability.*

## Functionality

FileFlotilla is a shell script designed to efficiently copy multiple files and folders in parallel. It leverages `rsync` for robust data transfer and enhances it with the following features:

-   **Parallel Processing**: Copies multiple items simultaneously to speed up bulk transfers.
-   **Configurable via Command-Line**: All settings, including user/group ownership, the number of parallel jobs, and `rsync` parameters, can be configured with command-line flags.
-   **Error Handling**: The script tracks the exit status of each `rsync` job and reports any failures at the end.
-   **Color-Coded Logging**: Provides clear, color-coded output for better readability.
-   **Signal Handling**: Gracefully terminates all running `rsync` jobs if the script is interrupted.

---

## Reasoning for creating the script

I needed an efficient method to copy multiple folders and files from one location to another and then change ownership of said copies within my WD MyCloudEX2Ultra NAS, so I created one that uses rsync and simple parallelization without many advanced software needed, beyond rsync. The script parallelizes the rsync operations themselves, allowing for multiple files and folders to be copied at the same time.

---

## Installation

To install the script system-wide, follow these instructions:

1. **Ensure you are in the folder that contains the script**:
    - After copying or cloning the repository from github, cd into the FileFlotilla directory.
2. **Copy the script to a directory that is within the PATH variable of your environment**:
    - A good location is /usr/local/bin.
    - Execute `cp fflot.sh /usr/local/bin/fflot` (I like to drop the .sh for easier execution, but you can leave it.)
    - Give the script proper permissions. Execute `chmod 755 /usr/local/bin/fflot`
    - You probably need to use sudo when executing the above commands. They were purposefully left out of the commands so that no one copy-pastes sudo commands without understanding their purpose. In general, it's a good idea to review any script you're copying into your system before executing them.
3. **Enjoy! The script should now be globally executable anywhere in your system**:
    - You can test this out by executing ``fflot`` in any random directory.

---

## Usage

The script is executed by providing pairs of source items and destination folders. You can customize its behavior using the command-line options below.

### Command-Line Execution

`fflot [OPTIONS] <source_item1> <destination_folder1> [<source_item2> <destination_folder2> ...]`

-   Paths with spaces or special characters should be properly quoted.

### Options

| Flag | Option | Description | Default |
| :--- | :--- | :--- | :--- |
| `-u` | `--user` | Sets the new user for the copied files. | `""` |
| `-g` | `--group` | Sets the new group for the copied files. | `""` |
| `-f` | `--file-mode` | Sets the new chmod attributes for copied files. | `""` |
| `-u` | `--dir-mode` | Sets the new chmod attributes for copied directories. | `""` |
| `-p` | `--parallel` | Sets the maximum number of parallel rsync jobs. | `2` |
| `-r` | `--rsync-params` | Sets the parameters for rsync. | `"-av"` |
| `-c` | `--no-color` | Disables color output. | N/A |
| `-h` | `--help` | Displays the help message. | N/A |

> **Note**: While command-line flags are recommended for per-run customization, you can still modify the default behaviors by editing the configuration variables at the top of the `fflot.sh` script.

### Ownership Change

-   File ownership is changed only when both `--user` and `--group` are specified with non-empty values.

### Examples

-   **Basic copy of two files to a backup folder**:

    `fflot "file1.txt" "/mnt/backups/" "file2.txt" "/mnt/backups/"`

-   **Copy a directory and change ownership**:

    `fflot --user "www-data" --group "www-data" "/var/www/html" "/mnt/backups/"`

-   **Copy with custom rsync parameters and more parallel jobs**:

    `fflot --parallel 10 --rsync-params "-a --info=progress2" "large-dataset/" "/mnt/nas/datasets/"`

---

## Parallelization in the Script

The script manages parallel `rsync` operations to efficiently copy files and directories. Here's how it works:

1. **Iterating Through Inputs**: The script processes the command-line arguments in pairs of source and destination.
2. **Launching Background Jobs**: For each pair, it initiates an `rsync` command as a background process.
3. **Controlling Parallelism**: A `while` loop actively monitors the number of running `rsync` jobs. If the count reaches the `MAX_PARALLEL_COPIES` limit (configurable with the `--parallel` flag), the script pauses and waits for one of the jobs to finish before starting a new one. This is achieved using `jobs -r` to count running jobs and `wait -n` to pause.
4. **Final Synchronization**: After all copy tasks have been started, the script waits for all remaining background `rsync` processes to complete before finishing.

---

## Error Handling and Reporting

The script monitors each `rsync` process to check if it completes successfully.

-   If an `rsync` job fails, the script records the failure and continues with other copy operations.
-   After all jobs are complete, the script reports the total number of failed copies and lists the specific source-to-destination pairs that failed.
-   If any copy operation fails, the script will exit with a non-zero status code.

---

## Post-Copy Cleanup

After all copying operations are complete, the script performs a cleanup step. It searches through the source and destination directories for any files named `_un` and deletes them. This is intended to remove temporary or unwanted files that may be left over from other processes.

---

### MIT License

Check out LICENSE.txt provided for more information.
