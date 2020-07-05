#!/bin/sh -e

export DOCKER_BUILDKIT=1

CONFIG_FILE="${1:-config}"

docker build -t pi-gen .

docker run -it \
	--privileged \
	--volume "$CONFIG_FILE:/config:ro" \
	pi-gen
