# FileFlotilla

## Functionality

A script that uses rsync and simple background processing to efficiently parallelize the copying of files and folders.

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

Run the script with **source item** and **destination folder** pairs. Follow these steps:

1. **Modify Ownership Variables**:
   - At the top of the script, find the variables `NEW_USER` and `NEW_GROUP`.
   - Set these variables to the desired username and group name to change file ownership accordingly.
   - If you wish to skip the ownership change, leave these variables as `""` (empty strings).

2. **Modify amount of parallel copies**:
   - At the top of the script, find the variable `MAX_PARALLEL_COPIES`.
   - Set the variable to the desired amount of copy processes to be run in parallel.

3. **Modify rsync parameters**:
   - At the top of the script, find the variable `RSYNC_PARAMETERS`.
   - Set the variable to the desired rsync parameters when executing a copy.

4. **Running the Script**:
   - Execute the script with pairs of source items and destination folders as arguments.
   - Example: `fflot <source_item1> <destination_folder1> [<source_item2> <destination_folder2> ...]`

5. **Ownership Change Conditions**:
   - The script changes ownership of the copied items only if *both* `NEW_USER` and `NEW_GROUP` are set to values other than `""`.

Remember to ensure that the script has the necessary permissions to execute and modify file ownership.

---

## Parallelization in the Script

The script manages parallel `rsync` operations to efficiently copy files and directories. Here's how it works:

1. **Iterating Through Inputs**: The script processes the command-line arguments in pairs of source and destination.
2. **Launching Background Jobs**: For each pair, it initiates an `rsync` command as a background process.
3. **Controlling Parallelism**: A `while` loop actively monitors the number of running `rsync` jobs. If the count reaches the `MAX_PARALLEL_COPIES` limit, the script pauses and waits for one of the jobs to finish before starting a new one. This is achieved using `jobs -r` to count running jobs and `wait -n` to pause.
4. **Final Synchronization**: After all copy tasks have been started, the script waits for all remaining background `rsync` processes to complete before finishing. This ensures that the script only exits after every file has been successfully copied.

---

## Post-Copy Cleanup

After all copying operations are complete, the script performs a cleanup step. It searches through the source and destination directories for any files named `_un` and deletes them. This is intended to remove temporary or unwanted files that may be left over from other processes.

---

### MIT License

Check out LICENSE.txt provided for more information.
