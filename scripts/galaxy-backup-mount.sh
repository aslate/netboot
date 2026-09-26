#!/usr/bin/env bash
set -euo pipefail

DRIVE=/run/media/aslate/GalaxyBkUp
IMAGE="$DRIVE/netboot-ext4.img"
MOUNT=/mnt/netboot-backup

usage() {
    echo "Usage: $0 {mount|unmount|status}" >&2
    exit 2
}

action="${1:-}"
case "$action" in
    mount)
        mountpoint -q "$DRIVE" || {
            echo "Backup drive is not mounted at: $DRIVE" >&2
            exit 1
        }
        [[ -f "$IMAGE" ]] || {
            echo "Container image is missing: $IMAGE" >&2
            exit 1
        }
        if mountpoint -q "$MOUNT"; then
            echo "Already mounted at $MOUNT"
            exit 0
        fi
        sudo mkdir -p "$MOUNT"
        sudo mount -o loop "$IMAGE" "$MOUNT"
        echo "Mounted $IMAGE at $MOUNT"
        ;;
    unmount|umount)
        if ! mountpoint -q "$MOUNT"; then
            echo "Not mounted at $MOUNT"
            exit 0
        fi
        sync
        sudo umount "$MOUNT"
        echo "Unmounted $MOUNT"
        ;;
    status)
        if mountpoint -q "$MOUNT"; then
            findmnt "$MOUNT"
        else
            echo "Not mounted at $MOUNT"
            exit 1
        fi
        ;;
    *)
        usage
        ;;
esac
