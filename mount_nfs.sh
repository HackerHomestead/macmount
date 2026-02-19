#!/bin/bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

FSTAB="/etc/fstab"
FSTAB_CONTENT=""
LOGFILE="$HOME/nfs_mount.log"

usage() {
    echo "Usage: $0 [fstab_string]"
    echo ""
    echo "Arguments:"
    echo "  fstab_string    Optional: fstab-style string with NFS entries"
    echo "                  If not provided, reads from /etc/fstab"
    echo ""
    echo "Examples:"
    echo "  $0                              # Read from /etc/fstab"
    echo "  $0 'server:/share /mnt/nfs nfs rw,noauto 0 0'"
    echo "  $0 '192.168.1.100:/data /mnt/data nfs rw 0 0'"
    exit 1
}

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOGFILE"
}

print_status() {
    local status="$1"
    local msg="$2"
    case "$status" in
        OK)      echo -e "${GREEN}[OK]${NC} $msg" ;;
        WARN)    echo -e "${YELLOW}[WARN]${NC} $msg" ;;
        ERROR)   echo -e "${RED}[ERROR]${NC} $msg" ;;
        INFO)    echo -e "[INFO] $msg" ;;
    esac
}

is_mounted() {
    local mount_point="$1"
    mount | grep -q " on $mount_point "
}

get_fstab_nfs_entries() {
    if [[ -n "$FSTAB_CONTENT" ]]; then
        echo "$FSTAB_CONTENT"
    else
        grep -v '^#' "$FSTAB" | grep -v '^$' | grep 'nfs'
    fi
}

test_connectivity() {
    local server="$1"
    if ping -c 1 -t 5 "$server" >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

test_nfs_share() {
    local server="$1"
    local share="$2"
    showmount -e "$server" 2>/dev/null | grep -q "$share"
}

unmount_if_mounted() {
    local mount_point="$1"
    if is_mounted "$mount_point"; then
        print_status "INFO" "Unmounting $mount_point..."
        if umount "$mount_point" 2>/dev/null; then
            print_status "OK" "Unmounted $mount_point"
            return 0
        else
            print_status "WARN" "Force unmounting $mount_point..."
            if umount -f "$mount_point" 2>/dev/null; then
                print_status "OK" "Force unmounted $mount_point"
                return 0
            else
                print_status "ERROR" "Failed to unmount $mount_point"
                return 1
            fi
        fi
    else
        print_status "INFO" "$mount_point was not mounted"
        return 0
    fi
}

remount_nfs() {
    local mount_point="$1"
    local server="$2"
    local share="$3"
    local options="$4"

    print_status "INFO" "Mounting $server:$share -> $mount_point..."

    if mount -t nfs -o "$options" "$server:$share" "$mount_point" 2>/dev/null; then
        print_status "OK" "Mounted $mount_point"
        return 0
    fi

    print_status "ERROR" "Failed to mount $mount_point"
    return 1
}

print_separator() {
    echo "============================================"
}

main() {
    if [[ $# -gt 0 ]]; then
        if [[ "$1" == "-h" || "$1" == "--help" ]]; then
            usage
        fi
        FSTAB_CONTENT="$1"
    fi

    print_separator
    echo "NFS Mount Manager"
    print_separator

    if [[ $EUID -eq 0 ]]; then
        print_status "WARN" "Running as root - mount commands will work directly"
    else
        print_status "WARN" "Not running as root - mount commands may fail"
        echo "         Run with: sudo $0"
        echo ""
    fi

    local entries
    entries=$(get_fstab_nfs_entries)

    if [[ -z "$entries" ]]; then
        if [[ -n "$FSTAB_CONTENT" ]]; then
            print_status "WARN" "No NFS entries found in provided string"
        else
            print_status "WARN" "No NFS entries found in $FSTAB"
        fi
        exit 0
    fi

    local success_count=0
    local fail_count=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        local server share mount_point options
        server=$(echo "$line" | awk '{print $1}' | cut -d':' -f1)
        share=$(echo "$line" | awk '{print $1}' | cut -d':' -f2-)
        mount_point=$(echo "$line" | awk '{print $2}')
        options=$(echo "$line" | awk '{print $4}')

        options="${options:-rw}"

        print_separator
        print_status "INFO" "Processing: $server:$share"
        echo "  Mount point: $mount_point"
        echo "  Options: $options"

        if ! test_connectivity "$server"; then
            print_status "ERROR" "Cannot reach $server (ping failed)"
            print_status "INFO" "Suggestions:"
            echo "         - Check if server $server is online"
            echo "         - Check network connectivity"
            echo "         - Check VPN connection if remote"
            ((fail_count++))
            continue
        fi
        print_status "OK" "Server $server is reachable"

        if ! test_nfs_share "$server" "$share"; then
            print_status "WARN" "Share $share not exported by $server"
            print_status "INFO" "Suggestions:"
            echo "         - Check server's /etc/exports"
            echo "         - Run: showmount -e $server"
        fi

        unmount_if_mounted "$mount_point" || ((fail_count++))

        if remount_nfs "$mount_point" "$server" "$share" "$options"; then
            ((success_count++))
            if [[ -d "$mount_point" ]]; then
                local file_count
                file_count=$(find "$mount_point" -maxdepth 2 -type f 2>/dev/null | wc -l)
                if [[ "$file_count" -gt 0 ]]; then
                    print_status "OK" "Found $file_count files in $mount_point"
                else
                    print_status "WARN" "Mount appears empty (no files found)"
                    print_status "INFO" "Suggestions:"
                    echo "         - Check if data exists on the server"
                    echo "         - Verify the correct share path"
                fi
            fi
        else
            ((fail_count++))
            print_status "INFO" "Suggestions:"
            echo "         - Check server exports: showmount -e $server"
            echo "         - Try manual mount: mount -t nfs -o $options $server:$share $mount_point"
            echo "         - Check mount point exists: mkdir -p $mount_point"
        fi

    done <<< "$entries"

    print_separator
    echo "Summary:"
    echo "  Successful: $success_count"
    echo "  Failed:     $fail_count"
    print_separator

    if [[ "$fail_count" -gt 0 ]]; then
        print_status "INFO" "General suggestions:"
        echo "         - Check server logs: ssh $server 'tail -f /var/log/messages'"
        echo "         - Verify NFS service: rpcinfo -p $server"
        echo "         - Reload exports: ssh $server 'exportfs -ra'"
        exit 1
    fi

    print_status "OK" "All NFS mounts completed successfully"
    exit 0
}

main "$@"
