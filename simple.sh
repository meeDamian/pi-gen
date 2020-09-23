#!/bin/sh -e

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
