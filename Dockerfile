# possible values: own, apt
ARG QEMU=own


FROM debian:buster-slim AS base

ENV DEBIAN_FRONTEND noninteractive
RUN apt-get -y update
RUN apt-get -y install --no-install-recommends \
    bc \
    binfmt-support \
    bsdtar \
    ca-certificates \
    coreutils \
    curl \
    debootstrap \
    dosfstools \
    file \
    git \
    grep \
    kmod \
    libcap2-bin \
    parted \
    quilt \
    rsync \
    udev \
    vim \
    xxd \
    xz-utils \
    zerofree \
    zip


FROM base AS apt-qemu
RUN apt-get -y install --no-install-recommends qemu-user-static


FROM base AS own-qemu
COPY  --from=meedamian/simple-qemu:v5.0.0  /usr/local/bin/qemu-arm-static /usr/local/bin/qemu-aarch64-static /usr/bin/


FROM ${QEMU}-qemu AS final

COPY dependencies simple-common.sh simple.sh  /pi-gen/
COPY files/  /pi-gen/files/

VOLUME /pi-gen/out/
VOLUME /pi-gen/cache/

WORKDIR /pi-gen/
ENTRYPOINT ["/pi-gen/simple.sh"]
