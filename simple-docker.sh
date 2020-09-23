#!/bin/sh -e

DOCKER_TAG=pi-gen
DOCKER_NAME="$DOCKER_TAG-container"

export DOCKER_BUILDKIT=1
docker build -t "$DOCKER_TAG" .

stop_docker() {
	echo "Force-stopping build within 5s…"
	docker stop --time 5 "$DOCKER_NAME"
}
trap stop_docker INT TERM

exec docker run --rm -it --name="$DOCKER_NAME" "$DOCKER_TAG"
