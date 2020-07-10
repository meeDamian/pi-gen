#!/bin/sh -e
# shellcheck disable=SC2120

. ./simple-common.sh

cd "$DIR"

cleanup() {
	exec bash # TODO: temporary
}
trap cleanup EXIT



unmount() { mount | grep -Eo "${WORK%/}/[^ ]*" | sort -r | xargs -i umount '{}' ;}

section "Creating img"
#IMG_NAME="${IMG_NAME:-$(date +%Y-%m-%d)-raspios}"
IMG="$OUTPUT/$IMG_NAME.img"

unmount || unmount || true

# All partition sizes and starts will be aligned to this size
ALIGN="$((1<<22))"         #   4 MiB  =      4 * 1024 * 1024  =  2^2 * 2^10 * 2^10  =  2^22
BOOT_SIZE_RAW="$((1<<28))" # 256 MiB  = 64 * 4 * 1024 * 1024  =  2^28
OS_SIZE_RAW="$(du --bytes -s --exclude=var/cache/apt/archives --exclude=boot "$WORK" | cut -f1)" # ~1.3GiB
OS_SIZE_EXTRA="$((OS_SIZE_RAW / 5 + 100 * (1<<20)))" # (20% of $OS_SIZE_RAW) + 100MiB


align() { N="$1"; echo "$(((N + ALIGN - 1) / ALIGN * ALIGN))" ;}

BOOT_SIZE="$(align "$BOOT_SIZE_RAW")"
OS_SIZE="$(align "$((OS_SIZE_RAW + OS_SIZE_EXTRA))")"

IMG_SIZE="$((ALIGN + BOOT_SIZE + OS_SIZE))"

truncate --size "$IMG_SIZE" "$IMG"


# shellcheck disable=SC2086,SC2048
image() { parted --script --machine "$IMG" $* ;}

image mklabel msdos

BOOT_START="$ALIGN"
OS_START="$((BOOT_START + BOOT_SIZE))"

image  unit B  mkpart primary fat32 "$BOOT_START" "$((BOOT_START + BOOT_SIZE - 1))"
image  unit B  mkpart primary ext4    "$OS_START" "$((  OS_START +   OS_SIZE - 1))"


PARTED_OUT="$(image unit b print)"
BOOT_OUT="$(echo "$PARTED_OUT" | awk  -F 'B?:'  '/^1/ {print $2 ":" $4}')"
OS_OUT="$(echo "$PARTED_OUT"   | awk  -F 'B?:'  '/^2/ {print $2 ":" $4}')"

BOOT_OFFSET="${BOOT_OUT%:*}"
BOOT_LENGTH="${BOOT_OUT#*:}"
BOOT_DEV="$(losetup --show --find --offset "$BOOT_OFFSET" --sizelimit "$BOOT_LENGTH" "$IMG")"

OS_OFFSET="${OS_OUT%:*}"
OS_LENGTH="${OS_OUT#*:}"
OS_DEV=$(losetup --show --find --offset "$OS_OFFSET" --sizelimit "$OS_LENGTH" "$IMG")

printf '/boot:  offset %10s,  length %s\n' "$BOOT_OFFSET" "$BOOT_LENGTH"
printf '/:      offset %10s,  length %s\n'   "$OS_OFFSET"   "$OS_LENGTH"


ROOT_FEATURES="^huge_file"
for FEATURE in metadata_csum 64bit; do
	if grep -q "$FEATURE" /etc/mke2fs.conf; then
		ROOT_FEATURES="^$FEATURE,$ROOT_FEATURES"
	fi
done

mkdosfs   -n boot -F 32 -v              "$BOOT_DEV"
mkfs.ext4 -L rootfs -O "$ROOT_FEATURES" "$OS_DEV"

mount -v -t ext4 "$OS_DEV"   "$MNT"
mkdir -p                     "$MNT/boot"
mount -v -t vfat "$BOOT_DEV" "$MNT/boot"

rsync -aHAXx --exclude /var/cache/apt/archives --exclude /boot "$WORK/" "$MNT/"
rsync -rtx "$WORK/boot/" "$MNT/boot/"
