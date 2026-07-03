# DebianInstaller

Scripts to setup a minimal Debian Linux system.

## Usage

First, create 4 partitions:
  * 1GB EFI partition
  * 1GB boot partition
  * 20GB root partition # (Atleast) Can make however large you need
  * home partition with the remaining disk space

```bash
sudo -i # become root now for running later commands
cfdisk /dev/disk
```

Second, create a partition on your USB stick (should be atleast 10MB)

Third, ensure you are connected to Ethernet or WiFi. Then clone the repository 
and run `start_install.sh`:

```bash
apt update
apt install -y git nano
git clone https://www.github.com/JustScott/DebianInstaller
nano ./DebianInstaller/install_constants # Populate the relevant variables
bash ./DebianInstaller/start_install.sh # run as root
```

### Script Completion Handling
A `start_install_completion.txt` file is created as the script is
ran so that if any command in the script fails, you can resolve
the issue and run `bash ./DebianInstaller/start_install.sh` again for it
to start after the last successfully ran command.
  * If you want to restart the script, just delete the completion
    file
  * If you want to start from a specific command/position in the 
    script, you can just delete up to and including that command
  * Or you can even just delete a specific command to just rerun
    that command

There is also a `finish_install_completion.txt` file located at /mnt/
that tracks the completion of `finish_install.sh`. All the rules above
regarding `start_install` apply the same.

### Post Installation
You can run `bash ./DebianInstaller/safely_shutdown_system.sh` after the
installation scripts are done running to automatically remove sensitive
files and safely unmount all the partitions.
