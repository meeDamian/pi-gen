copy_previous(){
	if [ ! -d "${PREV_ROOTFS_DIR}" ]; then
		echo "Previous stage rootfs not found"
		false
	fi
	mkdir -p "${ROOTFS_DIR}"
	rsync -aHAXx --exclude var/cache/apt/archives "${PREV_ROOTFS_DIR}/" "${ROOTFS_DIR}/"
}
export -f copy_previous

unmount(){
	if [ -z "$1" ]; then
		DIR=$PWD
	else
		DIR=$1
	fi

	while mount | grep -q "$DIR"; do
		local LOCS
		LOCS=$(mount | grep "$DIR" | cut -f 3 -d ' ' | sort -r)
		for loc in $LOCS; do
			umount "$loc"
		done
	done
}
export -f unmount

unmount_image(){
	sync
	sleep 1
	local LOOP_DEVICES
	LOOP_DEVICES=$(losetup --list | grep "$(basename "${1}")" | cut -f1 -d' ')
	for LOOP_DEV in ${LOOP_DEVICES}; do
		if [ -n "${LOOP_DEV}" ]; then
			local MOUNTED_DIR
			MOUNTED_DIR=$(mount | grep "$(basename "${LOOP_DEV}")" | head -n 1 | cut -f 3 -d ' ')
			if [ -n "${MOUNTED_DIR}" ] && [ "${MOUNTED_DIR}" != "/" ]; then
				unmount "$(dirname "${MOUNTED_DIR}")"
			fi
			sleep 1
			losetup -d "${LOOP_DEV}"
		fi
	done
}
export -f unmount_image

update_issue() {
	echo -e "Raspberry Pi reference ${IMG_DATE}\nGenerated using ${PI_GEN}, ${PI_GEN_REPO}, ${GIT_HASH}, ${1}" > "${ROOTFS_DIR}/etc/rpi-issue"
}
export -f update_issue
