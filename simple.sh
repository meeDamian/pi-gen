#!/bin/sh -e

# Import & init the common stuff
. ./simple-common.sh && common_init
cd "$DIR"


Step 'Check environment'
if [ "$(id -u)" != "0" ]; then
	Error 'Please run as root'
fi
