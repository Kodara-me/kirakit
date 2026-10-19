#!/bin/sh
# Install kirakit configuration into the Claude Code configuration directory.
#
# From a clone, files are symlinked back to the clone by default. When piped from curl,
# the repository is fetched into a temporary directory and files are copied.
#
# The output styles are personalized with the user's name and gender. The installer asks
# for them once (on the terminal, even when piped from curl) and saves them in
# $CLAUDE_DIR/.kirakit-profile for later runs.
#
# Usage: get-kira.sh [--dry-run] [--name NAME] [--gender GENDER] [--persona NAME]...
set -eu

KIRAKIT_REPO=${KIRAKIT_REPO:-https://github.com/jstmichel/kirakit.git}
KIRAKIT_REF=${KIRAKIT_REF:-main}
CLAUDE_DIR=${CLAUDE_CONFIG_DIR:-$HOME/.claude}

dry_run=0
mode=
only=
personas=
work=
backup_dir=
reconfigure=0
profile=$CLAUDE_DIR/.kirakit-profile
user_name=
user_gender=
saved=0

log() {
	printf 'kirakit: %s\n' "$*"
}

die() {
	printf 'kirakit: error: %s\n' "$*" >&2
	exit 1
}

usage() {
	cat <<EOF
Usage: get-kira.sh [options]

Options:
  --dry-run          Print what would change, change nothing
  --name NAME        How Kira calls you (asked once, then saved)
  --gender GENDER    male, female, nonbinary or unspecified (asked once, then saved)
  --reconfigure      Ask for name and gender again
  --persona NAME     Install only this persona (repeatable; default: all)
  --only COMPONENT   Install one component: styles, claude or github
  --link             Symlink files to the local clone (default from a clone)
  --copy             Copy files (default without a clone)
  --uninstall        Remove installed files (not implemented yet)
  -h, --help         Show this help

Environment:
  CLAUDE_CONFIG_DIR  Claude Code configuration directory (default: ~/.claude)
  KIRAKIT_REPO       Repository fetched without a clone (default: $KIRAKIT_REPO)
  KIRAKIT_REF        Branch or tag fetched without a clone (default: $KIRAKIT_REF)
EOF
}

# Run a command, or only print it in dry-run mode.
run() {
	if [ "$dry_run" -eq 1 ]; then
		printf '[dry-run] %s\n' "$*"
	else
		"$@"
	fi
}

cleanup() {
	if [ -n "$work" ]; then
		rm -rf -- "$work"
	fi
}

work_dir() {
	if [ -z "$work" ]; then
		work=$(mktemp -d "${TMPDIR:-/tmp}/kirakit.XXXXXX")
	fi
}

# Move an existing file or symlink into this run's backup directory.
backup() {
	if [ -z "$backup_dir" ]; then
		# Never reuse the directory of an earlier run started within the same second.
		base=$CLAUDE_DIR/.kirakit-backups/$(date +%Y%m%d-%H%M%S)
		backup_dir=$base
		n=1
		while [ -e "$backup_dir" ]; do
			backup_dir=$base-$n
			n=$((n + 1))
		done
	fi
	rel=${1#"$CLAUDE_DIR"/}
	dest=$backup_dir/$rel
	log "backup: $1 -> $dest"
	run mkdir -p "$(dirname -- "$dest")"
	run mv -- "$1" "$dest"
}

# install_file SOURCE TARGET: link or copy SOURCE to TARGET, backing up anything else there.
install_file() {
	if [ "$mode" = link ]; then
		if [ -L "$2" ] && [ "$(readlink "$2")" = "$1" ]; then
			log "up to date: $2"
			return
		fi
	elif [ -f "$2" ] && [ ! -L "$2" ] && cmp -s "$1" "$2"; then
		log "up to date: $2"
		return
	fi

	if [ -e "$2" ] || [ -L "$2" ]; then
		backup "$2"
	fi
	run mkdir -p "$(dirname -- "$2")"
	if [ "$mode" = link ]; then
		log "link: $2 -> $1"
		run ln -s -- "$1" "$2"
	else
		log "copy: $1 -> $2"
		run cp -- "$1" "$2"
	fi
}

# Whether questions can be asked: true on a terminal, even when stdin is a pipe from curl.
can_prompt() {
	(: </dev/tty) 2>/dev/null
}

ask_name() {
	printf 'How should Kira call you? [%s] ' "$1" >/dev/tty
	IFS= read -r answer </dev/tty || answer=
	printf '%s\n' "${answer:-$1}"
}

ask_gender() {
	case $1 in
	male) default=1 ;;
	female) default=2 ;;
	nonbinary) default=3 ;;
	*) default=4 ;;
	esac
	cat >/dev/tty <<EOF
How should Kira refer to you?
  1) male (he/him)
  2) female (she/her)
  3) non-binary (they/them)
  4) prefer not to say (they/them)
EOF
	while :; do
		printf 'Choice [%s] ' "$default" >/dev/tty
		IFS= read -r answer </dev/tty || answer=
		case ${answer:-$default} in
		1) echo male && return ;;
		2) echo female && return ;;
		3) echo nonbinary && return ;;
		4) echo unspecified && return ;;
		esac
	done
}

load_profile() {
	[ -f "$profile" ] || return 0
	saved=1
	while IFS='=' read -r key value; do
		case $key in
		name) saved_name=$value ;;
		gender) saved_gender=$value ;;
		esac
	done <"$profile"
}

# Resolve name and gender from options, the saved profile, then questions.
setup_profile() {
	load_profile
	user_name=${opt_name-${saved_name-}}
	user_gender=${opt_gender-${saved_gender-}}

	if [ "$saved" -eq 0 ] || [ "$reconfigure" -eq 1 ]; then
		if can_prompt; then
			[ -n "${opt_name+set}" ] || user_name=$(ask_name "$user_name")
			[ -n "${opt_gender+set}" ] || user_gender=$(ask_gender "$user_gender")
		elif [ -z "${opt_name+set}" ] && [ -z "${opt_gender+set}" ]; then
			log "no terminal to ask your name and gender: using a generic profile (see --name, --gender)"
			user_gender=${user_gender:-unspecified}
			return
		fi
	fi
	user_gender=${user_gender:-unspecified}

	if [ "$saved" -eq 1 ] && [ "$user_name" = "${saved_name-}" ] && [ "$user_gender" = "${saved_gender-}" ]; then
		return
	fi
	log "save profile: $profile"
	if [ "$dry_run" -eq 1 ]; then
		printf '[dry-run] write name=%s gender=%s to %s\n' "$user_name" "$user_gender" "$profile"
	else
		mkdir -p "$CLAUDE_DIR"
		printf 'name=%s\ngender=%s\n' "$user_name" "$user_gender" >"$profile"
	fi
}

install_styles() {
	# Build into the clone for symlinks, into a temporary directory otherwise, so that a
	# dry run never writes outside it.
	if [ "$mode" = link ] && [ "$dry_run" -eq 0 ]; then
		build_dir=$src/dist/output-styles
	else
		work_dir
		build_dir=$work/output-styles
	fi

	# shellcheck disable=SC2086 # persona names are split on purpose
	built=$(sh "$src/scripts/build-styles.sh" -o "$build_dir" \
		--name "$user_name" --gender "$user_gender" $personas) || exit 1

	printf '%s\n' "$built" | while IFS= read -r file; do
		name=$(basename "$file")
		if [ "$mode" = link ]; then
			file=$src/dist/output-styles/$name
		fi
		install_file "$file" "$CLAUDE_DIR/output-styles/$name"
	done
}

while [ $# -gt 0 ]; do
	case $1 in
	--dry-run) dry_run=1 ;;
	--persona)
		[ $# -ge 2 ] || die "missing value for $1"
		case $2 in
		'' | -* | *[!A-Za-z0-9_-]*) die "invalid persona name: $2" ;;
		esac
		personas="$personas $2"
		shift
		;;
	--only)
		[ $# -ge 2 ] || die "missing value for $1"
		case $2 in
		styles | claude | github) only=$2 ;;
		*) die "unknown component: $2 (expected styles, claude or github)" ;;
		esac
		shift
		;;
	--name)
		[ $# -ge 2 ] || die "missing value for $1"
		opt_name=$2
		shift
		;;
	--gender)
		[ $# -ge 2 ] || die "missing value for $1"
		case $2 in
		male | female | nonbinary | unspecified) opt_gender=$2 ;;
		*) die "unknown gender: $2 (expected male, female, nonbinary or unspecified)" ;;
		esac
		shift
		;;
	--reconfigure) reconfigure=1 ;;
	--link) mode=link ;;
	--copy) mode=copy ;;
	--uninstall) die "--uninstall is not implemented yet" ;;
	-h | --help)
		usage
		exit 0
		;;
	*) die "unknown option: $1 (see --help)" ;;
	esac
	shift
done

case $only in
claude | github) die "component '$only' is not implemented yet" ;;
esac

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

[ "$dry_run" -eq 0 ] || log "dry run: nothing will be changed"

# Use the clone this script lives in, if any; otherwise fetch the repository.
src=
case $0 in
*get-kira.sh)
	dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
	if [ -f "$dir/personas/_core.md" ]; then
		src=$dir
	fi
	;;
esac

if [ -z "$src" ]; then
	[ "$mode" != link ] || die "--link needs a local clone: run get-kira.sh from the repository"
	command -v git >/dev/null 2>&1 || die "git is required"
	work_dir
	log "fetching $KIRAKIT_REPO ($KIRAKIT_REF)"
	git clone --quiet --depth 1 --branch "$KIRAKIT_REF" -- "$KIRAKIT_REPO" "$work/repo" ||
		die "could not fetch $KIRAKIT_REPO"
	src=$work/repo
	mode=copy
fi
[ -n "$mode" ] || mode=link

log "source: $src ($mode mode)"
log "target: $CLAUDE_DIR"

setup_profile
log "profile: ${user_name:-(no name)}, $user_gender"
install_styles

log "done"
