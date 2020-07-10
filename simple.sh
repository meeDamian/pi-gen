#!/bin/sh -e
# shellcheck disable=SC2120

. ./simple-common.sh

cd "$DIR"

cleanup() {
	preserve() { [ -f "$WORK/$1" ] && cp "$WORK/$1" "$OUTPUT/" ;}
	preserve debootstrap/debootstrap.log

	exec bash # TODO: temporary
}
trap cleanup EXIT


date +'%n%n[%T %F] Build started' >>"$LOGFILE"


section 'Checking environment'
if [ "$(id -u)" != "0" ]; then
	error 'Please run as root'
fi

# Make sure all dependencies in `./depends` are installed on the host OS
# src: scripts/dependencies_check
if ! missing="$(decomment < ./depends | has_deps)"; then
	error "Missing dependency: $missing"
fi
ok


section 'Loading config'
[ -f config ] && . ./config
# shellcheck disable=SC1090
[ -n "$1" ] && [ -f "$1" ] && . "$1"
ok


section 'Processing loaded config'
USER="${USER:-pi}"
if ! echo "$USER" | grep -qE '^[a-z][-a-z0-9_]*$'; then
	error "Invalid USER name: $USER"
fi
PASS="${PASS:-raspberry}"
HOSTNAME="${HOSTNAME:-raspberrypi}"

ARCH="${ARCH:-arm64}"
if ! echo "$ARCH" | grep -qE '^arm(hf|64)$'; then
	error "Specified ARCH='$ARCH' not supported. Must be one of: armhf, arm64"
fi
info "Target arch: $ARCH"

RELEASE="${RELEASE:-buster}"
info "Target debian: $RELEASE"

MIRROR='http://raspbian.raspberrypi.org/raspbian'
if is_arm64; then
	MIRROR='http://deb.debian.org/debian'
fi
info "Source mirror: $MIRROR"

LOCALE_DEFAULT="${LOCALE_DEFAULT:-en_GB.UTF-8}"
KEYBOARD_KEYMAP="${KEYBOARD_KEYMAP:-gb}"
KEYBOARD_LAYOUT="${KEYBOARD_LAYOUT:-English (UK)}"
TIMEZONE_DEFAULT="${TIMEZONE_DEFAULT:-Europe/London}"
info "Locale: $LOCALE_DEFAULT"

case "$SSH" in
enable|1|on|true|yes)
	info 'Enable SSH'
	SSH=enable
	;;
*) SSH= ;;
esac

IMG_NAME="${IMG_NAME:-$(date +%Y-%m-%d)-raspios}"
info "Goal: $IMG_NAME.img"

# Other recognized config variables that don't have defaults:
#	$WPA_COUNTRY
#	$WPA_ESSID
#	$WPA_PASSWORD
ok


# src: scripts/dependencies_check
section 'Verify QEMU setup'
if qemu="$(dpkg --print-architecture | grep -vE "^$ARCH$")"; then (
	if ! cd /proc/sys/fs/binfmt_misc/ 2>/dev/null; then
		error 'No binfmt_misc support in kernel. Try running:\n' \
		      '	/sbin/modprobe binfmt_misc\n'
	fi

	if [ ! -f register ] && ! mount binfmt_misc -t binfmt_misc "$(pwd)"; then
		error 'binfmt_misc support in kernel present, but not enabled\n' \
		      '	and enabling it failed.\n'
	fi

	info "Needed for '$ARCH' on '$qemu'"
) fi
ok


# src: stage0/prerun.sh
section "Bootstrapping minimal Debian to $WORK"
keyring="$FILES/raspberrypi.gpg"
if is_arm64; then
	keyring="$FILES/debian.gpg"
fi

flags="--arch=$ARCH \
--variant=minbase \
--include=gnupg \
--components='main,contrib,non-free' \
${keyring:+--keyring=$keyring}"

cmd="${qemu:+qemu-}debootstrap $flags $RELEASE $WORK $MIRROR"
if ! capsh --drop=cap_setfcap -- -c "$cmd"; then
	error 'Unable to bootstrap'
fi
ok


# src: stage0/00-configure-apt/00-run.sh
section 'Configuring apt'
transfer etc/apt/sources.list
transfer etc/apt/sources.list.d/raspi.list

substitute MIRROR  "$MIRROR"  etc/apt/sources.list
substitute RELEASE "$RELEASE" etc/apt/sources.list
substitute RELEASE "$RELEASE" etc/apt/sources.list.d/raspi.list

discard etc/apt/apt.conf.d/51cache

if is_arm64; then
	info "Add support for 'armhf' packages (on 'arm64' target OS)"
	chroot_run1 dpkg --add-architecture armhf
fi

info 'Add raspberrypi.gpg.key'
chroot_run apt-key add - < "$FILES/raspberrypi.gpg.key"

info 'Update and install'
chroot_run1 apt-get update
chroot_run1 apt-get dist-upgrade -y
ok


section 'Setting up locale'
# src: stage0/01-locale/00-debconf
chroot_run <<EOF
LOCALE_DEFAULT="$LOCALE_DEFAULT"

debconf-set-selections <<SELEOF
$(cat "$FILES/locale-debconf")
SELEOF
EOF

info 'Install locales & firmware'
# src: stage0/01-locale/00-packages, stage0/02-firmware/01-packages
chroot_install locales raspberrypi-bootloader raspberrypi-kernel
ok


# src: stage1/00-boot-files/00-run.sh
section 'Setting up /boot/'
transfer boot/cmdline.txt
transfer boot/config.txt
ok


section "Setting up users: $USER & root"
# src: stage1/01-sys-tweaks/00-patches/01-bashrc.diff
patch_file etc/skel/.bashrc

# src: stage1/01-sys-tweaks/00-run.sh
transfer etc/systemd/system/getty@tty1.service.d/noclear.conf
transfer etc/fstab
chroot_run <<EOF
if ! id -u "$USER" >/dev/null 2>&1; then
	adduser --disabled-password --gecos "" "$USER"
fi
echo "$USER:$PASS" | chpasswd
echo 'root:root'   | chpasswd
EOF
ok


section 'Setting up basic networking'
# src: stage1/02-net-tweaks/00-packages
chroot_install netbase

# src: stage1/02-net-tweaks/00-run.sh
write "$HOSTNAME"              etc/hostname
append "127.0.1.1	$HOSTNAME" etc/hosts

# TODO: ????
ln -sf /dev/null "$WORK"/etc/systemd/network/99-default.link || warn 'failed creating symlink'
ok


section 'Installing raspberrypi-specific dependencies'
# src: stage1/03-install-packages/00-packages
chroot_install libraspberrypi-bin libraspberrypi0 raspi-config
ok


section 'Turning debian into Raspberry Pi OS'
# src: stage2/01-sys-tweaks/00-debconf
chroot_run <<EOF
KEYBOARD_KEYMAP="$KEYBOARD_KEYMAP"
KEYBOARD_LAYOUT="$KEYBOARD_LAYOUT"

debconf-set-selections <<SELEOF
$(cat "$FILES/input-debconf")
SELEOF
EOF
env
info 'Keyboard preset'

# src: stage2/01-sys-tweaks/00-packages-nr
chroot_install --no-install-recommends cifs-utils
info 'Installed deps (pre)'

# src: stage2/01-sys-tweaks/00-packages
chroot_install ssh less fbset sudo psmisc strace ed ncdu crda console-setup keyboard-configuration debconf-utils    \
	parted unzip build-essential manpages-dev python bash-completion gdb pkg-config python-rpi.gpio v4l-utils       \
	avahi-daemon lua5.1 luajit hardlink ca-certificates curl fake-hwclock nfs-common usbutils libraspberrypi-dev    \
	libraspberrypi-doc libfreetype6-dev dosfstools dphys-swapfile raspberrypi-sys-mods pi-bluetooth apt-listchanges \
	usb-modeswitch libpam-chksshpwd rpi-update libmtp-runtime rsync htop man-db policykit-1 ssh-import-id rng-tools \
	ethtool vl805fw ntfs-3g pciutils rpi-eeprom raspinfo
info 'Installed deps'

# src: stage2/01-sys-tweaks/00-patches/*.diff
patch_file etc/default/useradd
patch_file etc/dphys-swapfile
patch_file etc/inputrc
patch_file etc/login.defs
patch_file etc/profile

patch_file boot/cmdline.txt   # TODO: stupid to patch own file…
ok 'Files patched'

# src: stage2/01-sys-tweaks/01-run.sh
transfer etc/init.d/resize2fs_once 755
transfer etc/systemd/system/rc-local.service.d/ttyoutput.conf
transfer etc/apt/apt.conf.d/50raspi
transfer etc/default/console-setup
transfer etc/rc.local 755
ok 'Files copied'

if ! empty "$qemu"; then
	transfer etc/udev/rules.d/90-qemu.rules
	RESIZE2FS=disable
fi

chroot_run <<EOF
systemctl disable                hwclock.sh
systemctl disable                nfs-common
systemctl disable                rpcbind
systemctl "${SSH:-disable}"      ssh
systemctl enable                 regenerate_ssh_host_keys
systemctl "${RESIZE2FS:-enable}" resize2fs_once
EOF
info 'Init state of systemctl services set'

discard 'etc/ssh/ssh_host_*_key*'

chroot_run <<EOF
for GRP in input spi i2c gpio; do
	groupadd -f -r "\$GRP"
done

for GRP in adm dialout cdrom audio users sudo video games plugdev input gpio spi i2c netdev; do
	adduser "$USER" "\$GRP"
done

setupcon --force --save-only -v

usermod --pass='*' root
EOF
ok


section 'Teaching Raspberry Pi OS about radios'
# src: stage2/02-net-tweaks/00-packages
chroot_install wpasupplicant wireless-tools firmware-atheros firmware-brcm80211 firmware-libertas firmware-misc-nonfree \
	firmware-realtek raspberrypi-net-mods dhcpcd5 net-tools

# src: stage2/02-net-tweaks/01-run.sh
transfer etc/systemd/system/dhcpcd.service.d/wait.conf
transfer etc/wpa_supplicant/wpa_supplicant.conf 600

(
	if ! empty "$WPA_COUNTRY"; then
		append etc/wpa_supplicant/wpa_supplicant.conf "country=$WPA_COUNTRY"
	fi

	if empty "$WPA_ESSID"; then
		return
	fi

	if ! empty "$WPA_PASSWORD"; then
		if network="$(chroot_run1 wpa_passphrase "$WPA_ESSID" "$WPA_PASSWORD")"; then
			append etc/wpa_supplicant/wpa_supplicant.conf "$network"
			return
		fi

		warn "$network"
		return
	fi

	cd "$WORK"
	cat <<EOL >>etc/wpa_supplicant/wpa_supplicant.conf

network={
	ssid="$WPA_ESSID"
	key_mgmt=NONE
}
EOL
)

# src: https://github.com/RPi-Distro/pi-gen/pull/416
# If WPA_COUNTRY is not set, disable wifi on 5GHz models
SIGNAL="$(! empty "$WPA_COUNTRY"; echo "$?")"
write "$SIGNAL" var/lib/systemd/rfkill/platform-3f300000.mmcnr:wlan
write "$SIGNAL" var/lib/systemd/rfkill/platform-fe300000.mmcnr:wlan
ok


section "Time zoning"
# src: stage2/03-set-timezone/02-run.sh
write "$TIMEZONE_DEFAULT" etc/timezone
discard etc/localtime
chroot_run1 dpkg-reconfigure -f noninteractive tzdata
ok


section "Damian's opinionated final touches"
chroot_install git nano tree jq
ok
