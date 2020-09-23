FROM debian:buster-slim

ENV DEBIAN_FRONTEND noninteractive

RUN apt-get -y update
RUN apt-get -y install --no-install-recommends \
    bc               \
    binfmt-support   \
    bsdtar           \
    ca-certificates  \
    coreutils        \
    curl             \
    debootstrap      \
    dosfstools       \
    file             \
    git              \
    grep             \
    kmod             \
    libcap2-bin      \
    parted           \
    qemu-user-static \
    quilt            \
    rsync            \
    udev             \
    vim              \
    xxd              \
    xz-utils         \
    zerofree         \
    zip

COPY . /pi-gen/

VOLUME /pi-gen/work/ /pi-gen/deploy/
