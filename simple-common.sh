#!/bin/sh -e
# shellcheck disable=SC2120

DIR="$(cd "${0%/*}" && pwd)"

FILES="$DIR/files"
OUTPUT="$DIR/out"; mkdir -p "$OUTPUT" # location for results of the build
WORK="$DIR/work" ; mkdir -p "$WORK"   # location of the bootstrapped OS
MNT="$DIR/mnt"   ; mkdir -p "$MNT"

LOGFILE="$OUTPUT/$(basename "${0%.*}").log"

# shellcheck disable=SC2059
log()     { printf "$*\n" | tee /dev/stderr | xargs -d'\n' -I{} date +"[%T] {}" >>"$LOGFILE" ;}
tag()     { t="$1"; shift; log "\t$t${*:+: $*}" ;}
error()   { tag ERROR "$*"; exit 1 ;}
warn()    { tag WARN  "$*"  ;}
ok()      { tag OK    "$*"  ;}
info()    { log  "\t-> $*"  ;}
section() { log     "\n$*…" ;}

empty()     { test -z "$1" ;}
is_arm64()  { [ "$ARCH" = "arm64" ] ;}
has_dep()   { test -x "$(command -v "$1")" ;}
has_deps()  { for d in ${*:-$(cat)}; do has_dep "${d%:*}" || { echo "${d#*:}"; false; }; done ;}
decomment() { echo "${*:-$(cat)}" | sed -e 's/[[:blank:]]*#.*$//' -e '/^[[:blank:]]*$/d' ;}

mkpath()   { D="$(dirname "$WORK/$1")"; [ -d "$D" ] || { mkdir -p "$D"; info "dir: $D" ;} ;}
transfer() { install -Dm "${2:-644}" "$FILES/$1" "$WORK/$1" && info "add: $1${2:+/$2}" ;}
# shellcheck disable=SC2086
discard()    { rm -f                       "$WORK"/$1 && info "del: $1" ;}
write()      { mkpath "$2" && echo "$1" >  "$WORK/$2" && info "set: $2" ;}
append()     { mkpath "$2" && echo "$1" >> "$WORK/$2" && info "app: $2" ;}
substitute() { sed -i "s|$1|$2|g"          "$WORK/$3" && info "mod: $3" ;}

chroot_run() {
	mounted() { mount | grep -q "$(realpath "$WORK/$1")"; }
	mounted proc    || mount -t proc proc    "$WORK/proc"
	mounted dev     || mount --bind /dev     "$WORK/dev"
	mounted dev/pts || mount --bind /dev/pts "$WORK/dev/pts"
	mounted sys     || mount --bind /sys     "$WORK/sys"

	setarch linux32  capsh --drop=cap_setfcap --chroot="$WORK/" -- -e "$@"
}

chroot_run1() {
	chroot_run <<EOF
$*
EOF
}

# shellcheck disable=SC2086,SC2048
chroot_install() { chroot_run1 apt-get -o APT::Acquire::Retries=3 install -y $* ;}

