#!/bin/sh
# Install kirakit into the Claude Code configuration directory.
#
# From a clone, files are symlinked back to the clone by default. When piped from curl,
# the repository is fetched into a temporary directory and files are copied.
#
# Output styles and skills are personalized from a profile: how Kira calls the user, the
# user's gender, the answer language and the commit co-author. The installer asks once (on
# the terminal, even when piped from curl) and saves the answers in
# $CLAUDE_DIR/.kirakit-profile for later runs.
#
# Usage: get-kira.sh [options] (see --help)
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
build_dir=
reconfigure=0
profile=$CLAUDE_DIR/.kirakit-profile
profile_keys='name gender language co_author'

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
  --dry-run                  Print what would change, change nothing
  --name NAME                How Kira calls you
  --gender GENDER            male, female, nonbinary or unspecified
  --language LANGUAGE        Answer language, or auto to follow the conversation
  --co-author "NAME <EMAIL>" Add this Co-Authored-By trailer to commits
  --no-co-author             Add no Co-Authored-By trailer to commits
  --reconfigure              Ask all profile questions again
  --persona NAME             Install only this persona (repeatable; default: all)
  --only COMPONENT           Install one component: styles, claude (skills) or github
  --link                     Symlink files to the local clone (default from a clone)
  --copy                     Copy files (default without a clone)
  --uninstall                Remove installed files (not implemented yet)
  -h, --help                 Show this help

Profile options are asked once and saved in \$CLAUDE_CONFIG_DIR/.kirakit-profile.

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

# Whether TARGET is already an identical copy of SOURCE (a file or a directory).
same_copy() {
	if [ -L "$2" ]; then
		return 1
	elif [ -d "$1" ]; then
		[ -d "$2" ] && diff -r -q -- "$1" "$2" >/dev/null 2>&1
	else
		[ -f "$2" ] && cmp -s -- "$1" "$2"
	fi
}

# install_file SOURCE TARGET: link or copy SOURCE (a file or a directory) to TARGET,
# backing up anything else there.
install_file() {
	if [ "$mode" = link ]; then
		if [ -L "$2" ] && [ "$(readlink "$2")" = "$1" ]; then
			log "up to date: $2"
			return
		fi
	elif same_copy "$1" "$2"; then
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
		run cp -R -- "$1" "$2"
	fi
}

# Whether the value is empty or looks like "NAME <EMAIL>".
valid_co_author() {
	case $1 in
	'') return 0 ;;
	*'<'*'<'* | *'>'*'>'*) return 1 ;;
	?*' <'?*@?*'>') ;;
	*) return 1 ;;
	esac
	email=${1##*<}
	case $email in *[[:space:]]*) return 1 ;; esac
}

# Whether questions can be asked: true on a terminal, even when stdin is a pipe from curl.
# The subshell matters: a failed redirection on ":" would exit a POSIX shell.
can_prompt() {
	(: </dev/tty) 2>/dev/null
}

# ask QUESTION [DEFAULT]: print the answer, or DEFAULT when the answer is empty.
ask() {
	if [ -n "${2-}" ]; then
		printf '%s [%s] ' "$1" "$2" >/dev/tty
	else
		printf '%s ' "$1" >/dev/tty
	fi
	IFS= read -r answer </dev/tty || answer=
	printf '%s\n' "${answer:-${2-}}"
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
		case $(ask 'Choice' "$default") in
		1) echo male && return ;;
		2) echo female && return ;;
		3) echo nonbinary && return ;;
		4) echo unspecified && return ;;
		esac
	done
}

ask_co_author() {
	if [ -n "$1" ]; then default=y; else default=n; fi
	while :; do
		case $(ask 'Add a Co-Authored-By trailer to your commit messages? (y/n)' "$default") in
		[Yy]*) break ;;
		[Nn]*) echo && return ;;
		esac
	done
	if [ -n "$1" ]; then
		current_name=${1% <*}
		current_email=${1##*<}
		current_email=${current_email%>}
	else
		current_name=Kira
		current_email=
	fi
	co_name=$(ask 'Co-author name' "$current_name")
	while :; do
		co_email=$(ask 'Co-author email' "$current_email")
		if [ -n "$co_email" ] && valid_co_author "$co_name <$co_email>"; then
			printf '%s <%s>\n' "$co_name" "$co_email"
			return
		fi
		printf 'Expected a name and an email address such as kira@example.com.\n' >/dev/tty
	done
}

load_profile() {
	[ -f "$profile" ] || return 0
	while IFS='=' read -r key value; do
		case $key in
		name) saved_name=$value ;;
		gender) saved_gender=$value ;;
		language) saved_language=$value ;;
		co_author) saved_co_author=$value ;;
		esac
	done <"$profile"
}

# should_ask KEY: whether to ask for KEY, i.e. it was not given as an option and either it
# is not saved yet or --reconfigure was passed.
should_ask() {
	eval "given=\${opt_$1+set} saved=\${saved_$1+set}"
	[ -z "$given" ] && { [ "$reconfigure" -eq 1 ] || [ -z "$saved" ]; }
}

# Resolve the profile from options, the saved profile, then questions.
setup_profile() {
	load_profile
	user_name=${opt_name-${saved_name-}}
	user_gender=${opt_gender-${saved_gender-unspecified}}
	user_language=${opt_language-${saved_language-auto}}
	co_author=${opt_co_author-${saved_co_author-}}

	missing=
	for key in $profile_keys; do
		if should_ask "$key"; then
			missing="$missing $key"
		fi
	done
	if [ -n "$missing" ]; then
		if ! can_prompt; then
			log "no terminal to ask for:$missing; using defaults (see --help)"
			return
		fi
		for key in $missing; do
			case $key in
			name) user_name=$(ask 'How should Kira call you?' "$user_name") ;;
			gender) user_gender=$(ask_gender "$user_gender") ;;
			language) user_language=$(ask 'Which language should Kira answer in? (auto follows the conversation)' "$user_language") ;;
			co_author) co_author=$(ask_co_author "$co_author") ;;
			esac
		done
	fi

	if [ -n "${saved_co_author+set}" ] && [ "$user_name" = "${saved_name-}" ] &&
		[ "$user_gender" = "${saved_gender-}" ] && [ "$user_language" = "${saved_language-}" ] &&
		[ "$co_author" = "$saved_co_author" ]; then
		return
	fi
	log "save profile: $profile"
	if [ "$dry_run" -eq 1 ]; then
		printf '[dry-run] write name=%s gender=%s language=%s co_author=%s to %s\n' \
			"$user_name" "$user_gender" "$user_language" "$co_author" "$profile"
	else
		mkdir -p "$CLAUDE_DIR"
		printf 'name=%s\ngender=%s\nlanguage=%s\nco_author=%s\n' \
			"$user_name" "$user_gender" "$user_language" "$co_author" >"$profile"
	fi
}

# Build into the clone for symlinks, into a temporary directory otherwise, so that a dry
# run never writes outside it.
build() {
	if [ "$mode" = link ] && [ "$dry_run" -eq 0 ]; then
		build_dir=$src/dist
	else
		work_dir
		build_dir=$work/dist
	fi
	sh "$src/scripts/build.sh" -o "$build_dir" --name "$user_name" --gender "$user_gender" \
		--language "$user_language" --co-author "$co_author" >/dev/null || exit 1
}

# built PATH: where an installed file comes from; symlinks always point into the clone.
built() {
	if [ "$mode" = link ]; then
		printf '%s\n' "$src/dist/$1"
	else
		printf '%s\n' "$build_dir/$1"
	fi
}

install_styles() {
	for file in "$src"/personas/*.md; do
		persona=$(basename "$file" .md)
		case $persona in _*) continue ;; esac
		if [ -n "$personas" ]; then
			case " $personas " in *" $persona "*) ;; *) continue ;; esac
		fi
		install_file "$(built "output-styles/$persona.md")" "$CLAUDE_DIR/output-styles/$persona.md"
	done
}

# Skills are directories holding a SKILL.md, installed as a whole.
install_skills() {
	for dir in "$src"/claude/skills/*/; do
		[ -f "$dir/SKILL.md" ] || continue
		skill=$(basename "$dir")
		install_file "$(built "skills/$skill")" "$CLAUDE_DIR/skills/$skill"
	done
}

while [ $# -gt 0 ]; do
	case $1 in
	--dry-run) dry_run=1 ;;
	--name | --gender | --language | --co-author | --persona | --only)
		[ $# -ge 2 ] || die "missing value for $1"
		case $1 in
		--name) opt_name=$2 ;;
		--gender)
			case $2 in
			male | female | nonbinary | unspecified) opt_gender=$2 ;;
			*) die "unknown gender: $2 (expected male, female, nonbinary or unspecified)" ;;
			esac
			;;
		--language) opt_language=$2 ;;
		--co-author)
			[ -n "$2" ] && valid_co_author "$2" || die "invalid co-author: $2 (expected \"NAME <EMAIL>\")"
			opt_co_author=$2
			;;
		--persona)
			case $2 in
			'' | -* | *[!A-Za-z0-9_-]*) die "invalid persona name: $2" ;;
			esac
			personas="$personas $2"
			;;
		--only)
			case $2 in
			styles | claude | github) only=$2 ;;
			*) die "unknown component: $2 (expected styles, claude or github)" ;;
			esac
			;;
		esac
		shift
		;;
	--no-co-author) opt_co_author= ;;
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
github) die "component '$only' is not implemented yet" ;;
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

for persona in $personas; do
	[ -f "$src/personas/$persona.md" ] || die "unknown persona: $persona"
done

log "source: $src ($mode mode)"
log "target: $CLAUDE_DIR"

setup_profile
log "profile: ${user_name:-(no name)}, $user_gender, language $user_language, co-author ${co_author:-none}"
build

if [ -z "$only" ] || [ "$only" = styles ]; then
	install_styles
fi
if [ -z "$only" ] || [ "$only" = claude ]; then
	install_skills
fi

log "done"
