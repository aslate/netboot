#!/usr/bin/env bash
set -euo pipefail

SOURCE=/srv/netboot/
DRIVE=/run/media/aslate/big-backup/
IMAGE="$DRIVE/netboot-ext4.img"
MOUNT=/mnt/netboot-backup
SIZE_MIB=65536
mounted_here=0

cleanup() {
    if (( mounted_here )); then
        sync
        sudo umount "$MOUNT"
    fi
}
trap cleanup EXIT

[[ -d "$SOURCE" ]] || {
    echo "Source directory is missing: $SOURCE" >&2
    exit 1
}

mountpoint -q "$DRIVE" || {
    echo "Backup drive is not mounted at: $DRIVE" >&2
    exit 1
}

recreate=y
if [[ -e "$IMAGE" ]]; then
    read -r -p "Recreate $IMAGE? This erases its contents. [Y/n] " answer
    case "$answer" in
        ""|y|Y|yes|YES|Yes) recreate=y ;;
        n|N|no|NO|No) recreate=n ;;
        *) echo "Please answer y or n." >&2; exit 2 ;;
    esac
fi

if [[ "$recreate" == y ]]; then
    if mountpoint -q "$MOUNT"; then
        echo "Refusing to recreate the image while $MOUNT is mounted." >&2
        exit 1
    fi

    rm -f -- "$IMAGE"
    echo "Creating a 64 GiB container at $IMAGE..."
    dd if=/dev/zero of="$IMAGE" bs=1M count="$SIZE_MIB" status=progress
    sudo mkfs.ext4 -m 0 -L netboot-backup "$IMAGE"
fi

[[ -f "$IMAGE" ]] || {
    echo "Container image is missing: $IMAGE" >&2
    exit 1
}

sudo mkdir -p "$MOUNT"
if mountpoint -q "$MOUNT"; then
    echo "Refusing to use an already-mounted path: $MOUNT" >&2
    exit 1
fi

sudo mount -o loop "$IMAGE" "$MOUNT"
mounted_here=1

sudo rsync -aHAX --delete --info=progress2 \
    --exclude='.codex-keys/' \
    "$SOURCE" "$MOUNT/"

echo "Backup completed successfully."
