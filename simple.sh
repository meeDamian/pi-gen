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



# Import & init the common stuff
. ./simple-common.sh && common_init
cd "$DIR"


Step 'Check environment'
if [ "$(id -u)" != "0" ]; then
	Error 'Please run as root'
fi

# Make sure all `./dependencies` are installed on the host OS
if ! missing="$(decomment < ./dependencies | has_deps)"; then
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
		armhf) _arch=arm     ;;
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
