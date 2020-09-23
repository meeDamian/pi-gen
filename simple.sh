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


LOCALE_DEFAULT="${LOCALE_DEFAULT:-en_GB.UTF-8}"
Configuration 'Locale' "$LOCALE_DEFAULT"

TIMEZONE_DEFAULT="${TIMEZONE_DEFAULT:-Europe/London}"
Configuration 'Timezone' "$TIMEZONE_DEFAULT"

KEYBOARD_KEYMAP="${KEYBOARD_KEYMAP:-gb}"
Configuration 'Keymap' "$KEYBOARD_KEYMAP"

KEYBOARD_LAYOUT="${KEYBOARD_LAYOUT:-English (UK)}"
Configuration 'Keyboard' "$KEYBOARD_LAYOUT"
