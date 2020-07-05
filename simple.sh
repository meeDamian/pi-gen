#!/bin/sh -e
# shellcheck disable=SC2120

DIR="$(cd "${0%/*}" && pwd)"
DEST="$DIR/dest"  ; mkdir -p "$DEST"
BUILD="$DIR/build"; mkdir -p "$BUILD"
FILES="$DIR/files"

cd "$DIR"


logs="$(mktemp)"
cleanup() {
	mv "$logs" "$DIR/build/build.log"
	exec bash
}
trap cleanup EXIT


# shellcheck disable=SC2059
log()     { printf     "$*\n" | tee -a "$logs" >&2 ;}
tab()     { log      "\t$*"                  ;}
section() { log        "$*…"                 ;}
status()  { tab     "-> $*"                  ;}
success() { status    "${*:-ok}"             ;}
warn()    { log "WARN: ${*:-$(cat)}"         ;}
error()   { log  "ERR: ${*:-$(cat)}"; exit 1 ;}

pad() { while read -r l; do tab "$l"; done ;}
error_no_dir() { error "'$1' doesn't exist" ;}
decomment() { echo "${*:-$(cat)}" | sed -e 's/[[:blank:]]*#.*$//' -e '/^[[:blank:]]*$/d' ;}

exists()   { test -x "$(command -v "$1")" ;}
has_deps() { for d in ${*:-$(cat)}; do exists "${d%:*}" || { echo "${d#*:}"; false; }; done ;}

# shellcheck disable=SC2086
discard()    { rm -f                               "$DEST"/$1   && status "del $1"          ;}
mkpath()     { mkdir -p                 "$(dirname "$DEST/$1")" && status "dir ${1%/*}"     ;}
write()      { mkpath "$1" && echo "$2" >          "$DEST/$1"   && status "set $1"          ;}
append()     { mkpath "$1" && echo "$2" >>         "$DEST/$1"   && status "app $1"          ;}
transfer()   { install -Dm "${2:-644}" "$FILES/$1" "$DEST/$1"   && status "add $1${2:+/$2}" ;}
substitute() { sed -i "s|$1|$2|g"                  "$DEST/$3"   && status "mod $3"          ;}
chroot_run() {
	mounted() { mount | grep -q "$(realpath "$DEST/$1")"; }
	mounted proc    || mount -t proc proc    "$DEST/proc"
	mounted dev     || mount --bind /dev     "$DEST/dev"
	mounted dev/pts || mount --bind /dev/pts "$DEST/dev/pts"
	mounted sys     || mount --bind /sys     "$DEST/sys"

	setarch linux32  capsh --drop=cap_setfcap --chroot="$DEST/" -- -e "$@"
}
chroot_run1() {
	chroot_run <<EOF
$*
EOF
}
# shellcheck disable=SC2086,SC2048
chroot_install() { chroot_run1 apt-get -o APT::Acquire::Retries=3 install -y $*; }


section "Checking environment"
# Make sure all dependencies in `./depends` are installed on the host OS
if ! missing="$(decomment < ./depends | has_deps)"; then
	error "missing dependency: $missing"
fi

[ "$(id -u)" = "0" ] \
	|| error 'Please run as root'
success

section 'Processing config'
[ -f config ] && . ./config
# shellcheck disable=SC1090
[ -n "$1" ] && [ -f "$1" ] && . "$1"
success


section 'Verifying input'
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
status "target arch: $ARCH"

RELEASE="${RELEASE:-buster}"
status "target debian: $RELEASE"

LOCALE_DEFAULT="${LOCALE_DEFAULT:-en_GB.UTF-8}"
KEYBOARD_KEYMAP="${KEYBOARD_KEYMAP:-gb}"
KEYBOARD_LAYOUT="${KEYBOARD_LAYOUT:-English (UK)}"
TIMEZONE_DEFAULT="${TIMEZONE_DEFAULT:-Europe/London}"

case "$SSH" in
enable|1|on|true|yes)
	status 'enable SSH'
	SSH=enable
	;;
*) SSH= ;;
esac

# Other recognized config variables that don't have defaults:
#	$WPA_COUNTRY, $WPA_ESSID, $WPA_PASSWORD
success


# src: stage0/prerun.sh
section "Bootstrapping minimal debian to $DEST"
if qemu="$(dpkg --print-architecture | grep -vE "^$ARCH$")"; then (
	if ! cd /proc/sys/fs/binfmt_misc/ 2>/dev/null; then
		error 'No binfmt_misc support in kernel. Try running:\n' \
		      '	/sbin/modprobe binfmt_misc\n'
	fi

	if [ ! -f register ] && ! mount binfmt_misc -t binfmt_misc "$(pwd)"; then
		error 'binfmt_misc support in kernel present, but not enabled\n' \
		      '	and enabling it failed.\n'
	fi

	status "Use QEMU to generate '$ARCH' on '$qemu'"
) fi

flags="--arch $ARCH --variant=minbase --include gnupg --components 'main,contrib,non-free'"
cmd="${qemu:+qemu-}debootstrap $flags $RELEASE $DEST http://deb.debian.org/debian/"
if ! capsh --drop=cap_setfcap -- -c "$cmd" 2>&1 | pad; then
	error "Unable to bootstrap"
fi
success


# src: stage0/00-configure-apt/00-run.sh
section "Configuring apt"
transfer etc/apt/sources.list
transfer etc/apt/sources.list.d/raspi.list

substitute RELEASE "$RELEASE" etc/apt/sources.list
substitute RELEASE "$RELEASE" etc/apt/sources.list.d/raspi.list

discard etc/apt/apt.conf.d/51cache

if [ "$ARCH" = "arm64" ]; then
	status "Add support for 'armhf' packages (on 'arm64' target OS)"
	chroot_run1 dpkg --add-architecture armhf
fi

status "Add raspberrypi.gpg.key"
chroot_run apt-key add - < "$FILES/raspberrypi.gpg.key"

status "Update and install"
chroot_run <<EOF
apt-get update
apt-get dist-upgrade -y
EOF
success


section 'Setting up locale'
# src: stage0/01-locale/00-debconf
chroot_run <<EOF
LOCALE_DEFAULT="$LOCALE_DEFAULT"

debconf-set-selections <<SELEOF
$(cat "$FILES/locale-debconf")
SELEOF
EOF

status 'Install locales & firmware'
# src: stage0/01-locale/00-packages, stage0/02-firmware/01-packages
chroot_install locales raspberrypi-bootloader raspberrypi-kernel
success


# src: stage1/00-boot-files/00-run.sh
section 'Setting up /boot/'
transfer boot/cmdline.txt
transfer boot/config.txt
success


section "Setting up users: $USER & root"
# src: stage1/01-sys-tweaks/00-patches/01-bashrc.diff
patch -d "$DEST" -p1 < "$FILES/bashrc.diff" \
	|| warn "Unable to patch 'etc/skel/.bashrc'. Not very critical, so continuing…"

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
success


section 'Setting up basic networking'
# src: stage1/02-net-tweaks/00-packages
chroot_install netbase

# src: stage1/02-net-tweaks/00-run.sh
write  etc/hostname  "$HOSTNAME"
append etc/hostnname "127.0.1.1	$HOSTNAME"

# TODO: ????
ln -sf /dev/null "$DEST"/etc/systemd/network/99-default.link || warn 'failed creating symlink'
success


section 'Installing raspberrypi-specific dependencies'
# src: stage1/03-install-packages/00-packages
chroot_install libraspberrypi-bin libraspberrypi0 raspi-config
success


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

# src: stage2/01-sys-tweaks/00-packages-nr
chroot_install --no-install-recommends cifs-utils

# src: stage2/01-sys-tweaks/00-packages
chroot_install ssh less fbset sudo psmisc strace ed ncdu crda console-setup keyboard-configuration debconf-utils    \
	parted unzip build-essential manpages-dev python bash-completion gdb pkg-config python-rpi.gpio v4l-utils       \
	avahi-daemon lua5.1 luajit hardlink ca-certificates curl fake-hwclock nfs-common usbutils libraspberrypi-dev    \
	libraspberrypi-doc libfreetype6-dev dosfstools dphys-swapfile raspberrypi-sys-mods pi-bluetooth apt-listchanges \
	usb-modeswitch libpam-chksshpwd rpi-update libmtp-runtime rsync htop man-db policykit-1 ssh-import-id rng-tools \
	ethtool vl805fw ntfs-3g pciutils rpi-eeprom raspinfo

# src: stage2/01-sys-tweaks/00-patches/*.patch
patch -d "$DEST" -p1 < "$FILES/various.diff"

# src: stage2/01-sys-tweaks/01-run.sh
transfer etc/init.d/resize2fs_once 755
transfer etc/systemd/system/rc-local.service.d/ttyoutput.conf
transfer etc/apt/apt.conf.d/50raspi
transfer etc/default/console-setup
transfer etc/rc.local 755

if [ -n "$qemu" ]; then
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
success


section 'Teaching Raspberry Pi OS about radios'
# src: stage2/02-net-tweaks/00-packages
chroot_install wpasupplicant wireless-tools firmware-atheros firmware-brcm80211 firmware-libertas firmware-misc-nonfree \
	firmware-realtek raspberrypi-net-mods dhcpcd5 net-tools

# src: stage2/02-net-tweaks/01-run.sh
transfer etc/systemd/system/dhcpcd.service.d/wait.conf
transfer etc/wpa_supplicant/wpa_supplicant.conf 600

(
	if [ -n "$WPA_COUNTRY" ]; then
		echo "country=$WPA_COUNTRY"
	fi

	if [ -n "$WPA_ESSID" ]; then
		if [ -n "$WPA_PASSWORD" ]; then
			network="$(chroot_run1 wpa_passphrase "$WPA_ESSID" "$WPA_PASSWORD")" \
				&&     echo "$network" \
				|| >&2 echo "$network"
			return
		fi

		cat <<EOL

network={
	ssid="$WPA_ESSID"
	key_mgmt=NONE
}
EOL
	fi
) >> "$DEST"/etc/wpa_supplicant/wpa_supplicant.conf

# src: https://github.com/RPi-Distro/pi-gen/pull/416
# If WPA_COUNTRY is not set, disable wifi on 5GHz models
SIGNAL="$([ -n "$WPA_COUNTRY" ]; echo "$?")"
write var/lib/systemd/rfkill/platform-3f300000.mmcnr:wlan "$SIGNAL"
write var/lib/systemd/rfkill/platform-fe300000.mmcnr:wlan "$SIGNAL"
success


section "Time zones are hard, m'kay"
# src: stage2/03-set-timezone/02-run.sh
write   etc/timezone "$TIMEZONE_DEFAULT"
discard etc/localtime

chroot_run1 dpkg-reconfigure -f noninteractive tzdata
success


section "Damian's final touches"
chroot_install git nano tree htop jq
success
