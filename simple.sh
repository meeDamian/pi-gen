#!/bin/sh -e

## DO READ
#
#   1. Run with either:
#        $ ./simple.sh         [PATH-TO-CONFIG]
#        $ ./simple-docker.sh  [PATH-TO-CONFIG]
#
#
#   2. Place config into `./config` file (or pass path to another config as first argument)
#
#
#   3. All Capitalized Function Calls Are For Logging
#
#
#   4. All code and function definitions are either here, or in `./simple-common.sh`
#
#
#   5. Code below this comment is meant to be read top to bottom
#
#
#   6. All 'FILE manipulation functions' operate on files in the OS being bootstrapped (target OS)
#
#
#   7. Files within `files/` directory map directly onto the target OS
#        Note: `.patch` files apply patch onto a corresponding original file
#
#



# Import & init the common stuff
. ./simple-common.sh && common_init
cd "$DIR"


Step 'Check environment'
if [ "$(id -u)" != "0" ]; then
	Error 'Please run as root'
fi

# Make sure all `./dependencies` are installed on the host OS
if ! missing="$(decomment <./dependencies | has_deps)"; then
	Error "Missing dependency: $missing"
fi
OK


Step 'Load config'
[ -s ./config ] && . ./config && Info 'Imported: ./config'
# shellcheck disable=SC1090
[ -s "$1" ] && . "$1" && Info "Imported: $1"
OK


Step 'Process loaded config(s)'
IMG_DATE="$(date +%F)"
IMG_NAME="${IMG_NAME:-$IMG_DATE-raspios}.img"
IMG="$OUTPUT/$IMG_NAME"
Configuration 'Output image' "$IMG"
if [ -f "$IMG" ]; then
	Error "$IMG already exists."
fi

GH="https://github.com/meeDamian/pi-gen"

HOST="${HOST:-raspberrypi}"
Configuration 'Hostname' "$HOST"

USER="${USER:-pi}"
if ! echo "$USER" | grep -qE '^[a-z][-a-z0-9_]*$'; then
	Error "Invalid USER name: $USER"
fi
Configuration 'Username' "$USER"

PASS="${PASS:-raspberry}"
Configuration 'Password' "$(echo "$PASS" | sed 's|.|*|g')"

HOST_ARCH="$(dpkg --print-architecture)"
Configuration 'Host arch' "$HOST_ARCH"

case "$ARCH" in
	arm64|arm64v?|aarch64|rbp3|rbp4|'')     ARCH=arm64 ;; # <- default
	armhf|arm32v?|arm|arm32|rbp0|rbp1|rbp2) ARCH=armhf ;;
	*) Error "Specified ARCH='$ARCH' not supported. Must be one of: armhf, arm64" ;;
esac
Configuration 'Target arch' "$ARCH"

RELEASE="${RELEASE:-buster}"
Configuration 'Debian release' "$RELEASE"

if empty "$MIRROR"; then
	MIRROR='http://deb.debian.org/debian'
	if ! is_arm64 "$ARCH"; then
		MIRROR='http://raspbian.raspberrypi.org/raspbian'
	fi
fi
Configuration 'Source mirror' "${MIRROR:-"Debian's default"}"

Configuration 'Variant' "${VARIANT:-"Deboostrap's default"}"

LOCALE_DEFAULT="${LOCALE_DEFAULT:-en_GB.UTF-8}"
Configuration 'Locale' "$LOCALE_DEFAULT"

TIMEZONE_DEFAULT="${TIMEZONE_DEFAULT:-Europe/London}"
Configuration 'Timezone' "$TIMEZONE_DEFAULT"

KEYBOARD_KEYMAP="${KEYBOARD_KEYMAP:-gb}"
Configuration 'Keymap' "$KEYBOARD_KEYMAP"

KEYBOARD_LAYOUT="${KEYBOARD_LAYOUT:-English (UK)}"
Configuration 'Keyboard' "$KEYBOARD_LAYOUT"

Configuration 'WiFi Country'  "$WPA_COUNTRY"
Configuration 'WiFi SSID'     "$WPA_ESSID"
Configuration 'WiFi password' "$(echo "$WPA_PASSWORD" | sed 's|.|*|g')"
OK


Step 'Verify QEMU setup'
if is_arm64 "$ARCH" && is_armhf "$HOST_ARCH"; then
	Error 'Bootstrapping 64-bit OS on a 32-bit armhf CPU currently not supported'
fi

if [ "$ARCH" != "$HOST_ARCH" ] && ! is_arm "$HOST_ARCH"; then
	Info "Using qemu to bootstrap '$ARCH' on '$HOST_ARCH'"

	if ! QEMU="$(
		case "$ARCH" in
		armhf) _arch=arm ;;
		arm64) _arch=aarch64 ;;
		esac

		command -v "qemu-$_arch-static"
	)"; then
		Error 'Binary not found'
	fi
	Info "Binary found: $QEMU"

	binfmt=/proc/sys/fs/binfmt_misc
	if ! grep -q "$binfmt" /proc/mounts; then
		if [ ! -d "$binfmt" ]; then
			Error 'No binfmt_misc support in kernel.\n' \
				'Try running:\n' \
				'	/sbin/modprobe binfmt_misc\n'
		fi

		if [ ! -f register ] && ! mount binfmt_misc -t binfmt_misc "$binfmt"; then
			Error 'binfmt_misc support in kernel present, but not enabled\n' \
				'	and enabling it failed.\n'
		fi
	fi
	unset binfmt
	Info 'Kernel support: available'

	OK "qemu v$("$QEMU" -version | grep -Eo '[0-9.]{5,}' | head -n1)"
else
	OK 'qemu not needed'
fi


Step "Bootstrap minimal Debian to $WORK"
if is_armhf "$ARCH"; then
	keyring="$FILES/raspberrypi.gpg"
fi

if [ "$VARIANT" = "minbase" ]; then
	include="gnupg"
fi

flags="--arch=$ARCH ${QEMU:+--foreign} \
	--components='main,contrib,non-free' \
	--log-extra-deps \
	--force-check-gpg \
	--cache-dir='$CACHE' \
	--keep-debootstrap-dir \
	${VARIANT:+--variant="$VARIANT"} \
	${include:+--include="$include"} \
	${keyring:+--keyring="$keyring"}"
if ! run1 debootstrap "$flags" "$RELEASE" "$WORK" "$MIRROR"; then
	Error 'Unable to bootstrap'
fi
unset flags keyring include

# When QEMU-emulated 2nd stage is required
if ! empty "$QEMU"; then
	OK 'First stage complete'

	Step 'Bootstrap second-stage'
	guard usr/bin/ 755
	cp "$QEMU" "$WORK/usr/bin/"

	Info "Warning(s) below about mount failures can be ignored safely (if run in Docker)"
	chroot_run1 /debootstrap/debootstrap --second-stage --keep-debootstrap-dir
fi

preserve debootstrap/debootstrap.log
discard debootstrap/
OK


Step 'Configure apt'
transfer etc/apt/sources.list
transfer etc/apt/sources.list.d/raspi.list

substitute MIRROR  "$MIRROR"  etc/apt/sources.list
substitute RELEASE "$RELEASE" etc/apt/sources.list
substitute RELEASE "$RELEASE" etc/apt/sources.list.d/raspi.list

discard etc/apt/apt.conf.d/51cache

Info 'Import raspberrypi.gpg.key'
chroot_run1 apt-key add - < "$FILES/raspberrypi.gpg.key"

if is_arm64 "$ARCH"; then
	Info "Add support for 'armhf' packages (on 'arm64' target OS)"
	chroot_run1 dpkg --add-architecture armhf
fi

Info 'Update and install'
chroot_run1 apt-get update
chroot_run1 apt-get dist-upgrade -y
OK


Step 'Setup locale'
Info "Select $LOCALE_DEFAULT"
(
	export LOCALE_DEFAULT="$LOCALE_DEFAULT"
	inflated debconf-locale | chroot_run1 debconf-set-selections
)

Info 'Install locales'
chroot_install locales
OK


Step 'Install firmware'
chroot_install raspberrypi-bootloader raspberrypi-kernel
OK


Step 'Setup /boot/'
transfer boot/cmdline.txt
transfer boot/config.txt
OK


Step "Setup users: $USER & root"
patch_file etc/skel/.bashrc

transfer etc/systemd/system/getty@tty1.service.d/noclear.conf
transfer etc/fstab # TODO: Why now, while placeholders still unknown?
chroot_run <<EOF
if ! id -u "$USER" >/dev/null 2>&1; then
	adduser --disabled-password --gecos "" "$USER"
fi
echo "$USER:$PASS" | chpasswd
echo 'root:root'   | chpasswd
EOF
OK


Step 'Setup basic networking'
chroot_install netbase

write "$HOST"              etc/hostname
append "127.0.1.1	$HOST" etc/hosts

symlink /dev/null etc/systemd/network/99-default.link
OK


Step 'Install raspberrypi-specific dependencies'
chroot_install libraspberrypi-bin libraspberrypi0 raspi-config
OK


Step 'Turn Debian into Raspberry Pi OS'
(
	export KEYBOARD_KEYMAP="$KEYBOARD_KEYMAP"
	export KEYBOARD_LAYOUT="$KEYBOARD_LAYOUT"
	inflated debconf-input | chroot_run1 debconf-set-selections
)
Info 'Keyboard preset'

chroot_install --no-install-recommends cifs-utils
Info 'Installed deps (pre)'

chroot_install ssh less fbset sudo psmisc strace ed ncdu crda console-setup keyboard-configuration debconf-utils \
	parted unzip build-essential manpages-dev python bash-completion gdb pkg-config python-rpi.gpio v4l-utils \
	avahi-daemon lua5.1 luajit hardlink ca-certificates curl fake-hwclock nfs-common usbutils libraspberrypi-dev \
	libraspberrypi-doc libfreetype6-dev dosfstools dphys-swapfile raspberrypi-sys-mods pi-bluetooth apt-listchanges \
	usb-modeswitch libpam-chksshpwd rpi-update libmtp-runtime rsync htop man-db policykit-1 ssh-import-id rng-tools \
	ethtool vl805fw ntfs-3g pciutils rpi-eeprom raspinfo
Info 'Installed deps'

patch_file etc/default/useradd
patch_file etc/dphys-swapfile
patch_file etc/inputrc
patch_file etc/login.defs
patch_file etc/profile

transfer etc/init.d/resize2fs_once 755
transfer etc/systemd/system/rc-local.service.d/ttyoutput.conf
transfer etc/apt/apt.conf.d/50raspi
transfer etc/default/console-setup
transfer etc/rc.local 755

if ! empty "$QEMU"; then
	transfer etc/udev/rules.d/90-qemu.rules
	RESIZE2FS=disable
fi

chroot_run1 systemctl disable hwclock.sh
chroot_run1 systemctl disable nfs-common
chroot_run1 systemctl disable rpcbind
chroot_run1 systemctl "${SSH:-disable}" ssh
chroot_run1 systemctl enable regenerate_ssh_host_keys
chroot_run1 systemctl "${RESIZE2FS:-enable}" resize2fs_once
OK 'Init state for systemctl services'

# Get rid of keys so they can be re-generated on first boot
discard 'etc/ssh/ssh_host_*_key*'

chroot_run <<EOF
for GRP in input spi i2c gpio; do
	groupadd -f -r "\$GRP"
done

for GRP in adm dialout cdrom audio users sudo video games plugdev input gpio spi i2c netdev; do
	adduser "$USER" "\$GRP"
done
EOF

chroot_run1 setupcon --force --save-only -v
chroot_run1 usermod --pass='*' root
OK
