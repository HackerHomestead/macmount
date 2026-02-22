# NFS Mount Manager

I wrote this because I could not figure out how to use the OS X nfs mounting, or at least I could not be bothered.

A bash script to mount NFS shares from `/etc/fstab` or a runtime argument.

## Usage

```bash
# Read NFS entries from /etc/fstab
sudo ./mount_nfs.sh

# Provide fstab-style string at runtime
sudo ./mount_nfs.sh 'server:/share /mnt/nfs nfs rw,noauto 0 0'
sudo ./mount_nfs.sh '192.168.1.100:/data /mnt/data nfs rw 0 0'

# View help
./mount_nfs.sh --help
```

## Features

- Reads NFS entries from `/etc/fstab` or command-line argument
- Tests server connectivity before mounting
- Verifies NFS share is exported
- Handles remounting (unmounts existing mounts first)
- Color-coded status output
- Logs all operations to `~/nfs_mount.log`

## Requirements

- `mount` (nfs support)
- `showmount`
- `ping`

## Install

```bash
chmod +x mount_nfs.sh
sudo cp mount_nfs.sh /usr/local/bin/nfs-mount
```

## Example /etc/fstab Entry

```
server:/share /mnt/nfs nfs rw,noauto,x-systemd.automount 0 0
```
