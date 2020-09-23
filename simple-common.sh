
# src: build.sh #L125
DIR="$(cd "${0%/*}" && pwd)"
_basename="$(basename "${0%.*}")"


OUTPUT="$DIR/out"

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
	mkdir -p "$OUTPUT"

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

Tag()   {( tag="$1"; shift; logf '\t%s%b' "$tag" "${1:+: $*}" )}

OK()    { Tag OK    "$*" ;}
Warn()  { Tag WARN  "$*" | _log "$WARNFILE" ;}
Error() { Tag ERROR "$*"; exit 1 ;}
