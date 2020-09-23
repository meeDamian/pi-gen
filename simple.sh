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
