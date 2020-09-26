DIR="$(cd "${0%/*}" && pwd)"
_basename="$(basename "${0%.*}")"

FILES="$DIR/files" # 1. Files used to bootstrap built OS
WORK="$DIR/work"   # 2. Directory where bootstrapping happens
CACHE="$DIR/cache" # 3. Debootstrap's packages caches
OUTPUT="$DIR/out"  # 4. Location for the final image produced, logs, etc

DEST="$WORK"


LOGFILE="$OUTPUT/$_basename.log"
WARNFILE="$OUTPUT/$_basename-warn.log"
log_start() {
	if [ -s "$1" ]; then
		tee -a "${1%.log}.old.log" < "$1"
	fi

	date +'%n%n[%T %F] Build started' > "$1"
}

# IMPORTANT: run after importing this script
common_init() {
	mkdir -p "$OUTPUT" "$WORK" "$CACHE"

	log_start "$LOGFILE"
	log_start "$WARNFILE"
}



#
## LOGGING functions
#
_log() { sed "s|^|[$(date +%T)] |g" | tee -a "${1:-$LOGFILE}" >&2 ;}
log() { printf '%b\n' "$*" | _log ;}
# shellcheck disable=SC2059
logf() {(
	fmt="$1" && shift
	printf "$fmt\n" "$@" | _log
)}

Step()  { log "\n$*" ;}

Info()  { log "\t->" "$*" ;}

Tag()   {( tag="$1"; shift; logf '\t%s%b' "$tag" "${1:+: $*}" )}

OK()    { Tag OK    "$*" ;}
Warn()  { Tag WARN  "$*" | _log "$WARNFILE" ;}
Error() { Tag ERROR "$*"; exit 1 ;}

Configuration() { logf '\t-> %-16s %b' "$1:" "${2:--}" ;}
File()          { logf '\t-> %-7s %b%b' "$1:" "$2" "${3:+ $3}" ;}
Command()       { logf '\t   $ %b' "$*" ;}



#
## FILE manipulation functions
#
mk_dir() { install -Dm "${2:-644}" ${3:+-o "$3" -g "$3"} -d "$DEST/$1" && File 'dir' "$1" ;}
guard() { [ -d "$DEST/${1%/*}" ] || mk_dir "${1%/*}" "$2" "$3" ;}

transfer()   { install -Dm "${2:-644}" "$FILES/$1" "$DEST/$1" && File 'add'    "$1" "${2:+(mod: $2)}" ;}
substitute() {
	sed -i "s|$1|$2|g" "$DEST/$3"
	File 'subst' "$3" "($1 -> $(echo "$2" | sed -E '/^.{39}/s/(^.{21}).+(.{16})/\1…\2/g'))"
}

# Return contents of $1 with all env vars within expanded
inflated() { envsubst < "$FILES/$1" && File 'inflate' "$1" ;}
preserve() { [ -s "$DEST/$1" ] && cp "$DEST/$1" "$OUTPUT/" && File 'keep' "$1" ;}
discard() {(
	cd "$DEST" || exit

	highlight() { echo "$1" | grep -E --color=always "^${const:+|$const}" ;}

	# `sed` trims all leading/trailing '*'s
	#   and converts any '*' sequence left into '|' (grep's OR)
	const="$(echo "$1" | sed -nE 's ^\**|\**$  g; s \*+ | gp' || true)"

	File 'del' "$(highlight "$1")"
	for match in $1; do
		if [ "$match" != "$1" ]; then
			i="$((i + 1))"
			logf '\t   del+%-3s %s' "$i:" "$(highlight "$match")"
		fi
		rm -rf "$match" || Error "Unable to remove" "$match"
	done
	[ -z "$i" ] || log # `$i` is only set if passed argument contained wildcards, and was matched more than once
)}
patch_file() {
	if ! patch --quiet "$DEST/$1" "$FILES/$1.patch"; then
		Warn "Patching '$1' failed"
		return 1
	fi
	File 'patch' "$1"
}


#
## CHROOT functions
#
compact() { echo "$*" | sed -E 's|^.?-c ||' | tr '\t' ' ' | tr -d '\n' | tr -s '[:blank:]' ;}

run() {
	chroot="$1"
	shift || true

	if ! empty "$chroot"; then
		mounted() { mount | grep -q "$(realpath  "$chroot/$1")"; }
		mounted proc    || mount -t proc proc    "$chroot/proc"
		mounted dev     || mount --bind /dev     "$chroot/dev"
		mounted dev/pts || mount --bind /dev/pts "$chroot/dev/pts"
		mounted sys     || mount --bind /sys     "$chroot/sys"

		case "$ARCH" in
			arm64) as=linux64 ;;
			armhf) as=linux32 ;;
		esac
	fi

	if ! empty "$*"; then
		Command "${chroot:+chroot${as:+($as)} $}" "$(compact "$*")"
	fi

	${as:+setarch $as} capsh --drop=cap_setfcap ${chroot:+--chroot="$chroot"} -- -e "$@"
}

run1() { run '' -c "$*" ;}

chroot_run()  { run "$DEST/"    "$@" ;}
chroot_run1() { run "$DEST/" -c "$*" ;}
chroot_install() { chroot_run1 apt-get -o APT::Acquire::Retries=3 install -y "$@" ;}



#
## Various UTILITY functions
#
decomment() { sed -e 's/[[:blank:]]*#.*$//' -e '/^[[:blank:]]*$/d' ;}
has_deps() {
	while IFS=: read -r binary package; do
		if [ ! -x "$(command -v "$binary")" ]; then
			echo "${package:-$binary}"
			return 1
		fi
	done
}

is_arm64() { [ "$1" = "arm64" ] ;}
is_armhf() { [ "$1" = "armhf" ] ;}
is_arm()   { [ "$1" != "${1#arm}" ] ;}

empty() { [ -z "$1" ] ;}
