#!/bin/sh -e

# Optional config
if [ -s "$1" ]; then
	conf2_name="$(basename "$1")"
	conf2="$(cd "$(dirname "$1")" && pwd)/$conf2_name"
fi

DOCKER_TAG=pi-gen
DOCKER_NAME="$DOCKER_TAG-container"

export DOCKER_BUILDKIT=1
docker build -t "$DOCKER_TAG" .

stop_docker() {
	echo "Force-stopping build within 5s…"
	docker stop --time 5 "$DOCKER_NAME"
}
trap stop_docker INT TERM

exec docker run --rm -it \
	--privileged \
	--name="$DOCKER_NAME" \
	--volume="$(pwd)/out/:/pi-gen/out/" \
	--volume="$(pwd)/config:/pi-gen/config:ro" \
	${conf2:+--volume="$conf2:/pi-gen/$conf2_name:ro"} \
	"$DOCKER_TAG" \
	"${conf2:+/pi-gen/$conf2_name}"
