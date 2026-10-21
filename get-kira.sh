#!/bin/sh
# Install kirakit into the Claude Code configuration directory.
#
# From a clone, files are symlinked back to the clone by default. When piped from curl,
# the repository is fetched into a temporary directory and files are copied.
#
# Output styles, skills, agents and CLAUDE.md are personalized from a profile: how Kira
# calls the user, the user's gender, the answer language and the assistant (git identity,
# signing key, GitHub account, Co-Authored-By trailers). The installer asks once (on the
# terminal, even when piped from curl) and saves the answers in $CLAUDE_DIR/.kirakit-profile
# for later runs.
#
# Usage: get-kira.sh [options] (see --help)
set -eu

KIRAKIT_REPO=${KIRAKIT_REPO:-https://github.com/jstmichel/kirakit.git}
CLAUDE_DIR=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
# Set to the release tag in the copy attached to each GitHub release, so that it installs
# its own version.
KIRAKIT_VERSION=

dry_run=0
uninstall=0
mode=
only=
personas=
github_target=
work=
backup_dir=
build_dir=
reconfigure=0
installed=
originals_new=
profile=$CLAUDE_DIR/.kirakit-profile
manifest=$CLAUDE_DIR/.kirakit-manifest
originals=$CLAUDE_DIR/.kirakit-originals
profile_keys='name gender language assistant assistant_signing_key assistant_github co_author_trailer'
nl='
'
tab=$(printf '\t')

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
  --assistant "NAME <EMAIL>" The assistant's git identity (its commits, and its trailer in yours)
  --assistant-signing-key PATH
                             The assistant's public SSH signing key (empty: it never commits)
  --assistant-github LOGIN   The assistant's own GitHub account (empty: none)
  --co-author "NAME <EMAIL>" Same as --assistant, with Co-Authored-By trailers
  --no-co-author             Add no Co-Authored-By trailer to commits
  --default-style PERSONA    Output style selected in settings.json (default: kira-cozy)
  --reconfigure              Ask all profile questions again
  --persona NAME             Install only this persona (repeatable; default: all)
  --only COMPONENT           styles, claude (CLAUDE.md, rules, settings, agents, skills) or github
  --target DIR               Repository for --only github (default: the current one)
  --link                     Symlink files to the local clone (default from a clone)
  --copy                     Copy files (default without a clone)
  --uninstall                Remove what kirakit installed in the configuration directory
  -h, --help                 Show this help

Without --only, styles and claude are installed. The github component copies issue and pull
request templates, workflows and Copilot instructions into a repository's .github directory.

Profile options are asked once and saved in \$CLAUDE_CONFIG_DIR/.kirakit-profile.

Environment:
  CLAUDE_CONFIG_DIR  Claude Code configuration directory (default: ~/.claude)
  KIRAKIT_REPO       Repository fetched without a clone (default: $KIRAKIT_REPO)
  KIRAKIT_REF        Branch or tag fetched without a clone (default: the latest release)
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

# backup PATH [ROOT [PREFIX] [cp]]: move PATH (or copy it, with "cp") into this run's
# backup directory, under PREFIX followed by PATH relative to ROOT.
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
	rel=${1#"${2:-$CLAUDE_DIR}"/}
	dest=$backup_dir/${3-}$rel
	log "backup: $1 -> $dest"
	run mkdir -p "$(dirname -- "$dest")"
	if [ "${4-}" = cp ]; then
		run cp -p -- "$1" "$dest"
	else
		run mv -- "$1" "$dest"
	fi
}

# The branch or tag to fetch without a clone: KIRAKIT_REF, else the version this copy was
# released with, else the highest vX.Y.Z tag of the repository, else main.
resolve_ref() {
	if [ -n "${KIRAKIT_REF-}" ]; then
		printf '%s\n' "$KIRAKIT_REF"
		return
	fi
	if [ -n "$KIRAKIT_VERSION" ]; then
		printf '%s\n' "$KIRAKIT_VERSION"
		return
	fi
	latest=$(git ls-remote --tags --refs -- "$KIRAKIT_REPO" 'v*' 2>/dev/null | awk '
		{ tag = $2; sub("^refs/tags/", "", tag) }
		tag ~ /^v[0-9]+\.[0-9]+\.[0-9]+$/ {
			split(substr(tag, 2), part, ".")
			key = sprintf("%09d%09d%09d", part[1], part[2], part[3])
			if (key > best) { best = key; latest = tag }
		}
		END { if (latest != "") print latest }')
	printf '%s\n' "${latest:-main}"
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

# listed FILE PATH: whether PATH is the first field of a line of FILE.
listed() {
	[ -f "$1" ] && awk -F "$tab" -v path="$2" '$1 == path { found = 1; exit } END { exit !found }' "$1"
}

# install_file SOURCE TARGET [ROOT PREFIX]: link or copy SOURCE (a file or a directory) to
# TARGET, backing up anything else there. Targets in the configuration directory (no ROOT)
# are recorded in the manifest for --uninstall, with the backup of what was there before
# kirakit so that --uninstall can restore it.
install_file() {
	if [ -z "${3-}" ]; then
		installed="$installed$2$nl"
	fi
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
		backup "$2" "${3-}" "${4-}"
		if [ -z "${3-}" ] && ! listed "$manifest" "$2" && ! listed "$originals" "$2"; then
			originals_new="$originals_new$2$tab$dest$nl"
		fi
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

ask_assistant() {
	if [ -n "$1" ]; then
		current_name=${1% <*}
		current_email=${1##*<}
		current_email=${current_email%>}
	else
		current_name=Kira
		current_email=
	fi
	assistant_name_answer=$(ask "Assistant's name" "$current_name")
	while :; do
		assistant_email_answer=$(ask "Assistant's email (empty: none)" "$current_email")
		if [ -z "$assistant_email_answer" ]; then
			echo
			return
		fi
		if valid_co_author "$assistant_name_answer <$assistant_email_answer>"; then
			printf '%s <%s>\n' "$assistant_name_answer" "$assistant_email_answer"
			return
		fi
		printf 'Expected an email address such as kira@example.com.\n' >/dev/tty
	done
}

ask_signing_key() {
	ask "Assistant's public SSH signing key (empty: the assistant does not commit as itself)" "$1"
}

ask_github() {
	while :; do
		login=$(ask "Assistant's GitHub login (empty: none)" "$1")
		if valid_github "$login"; then
			printf '%s\n' "$login"
			return
		fi
		printf 'Expected a GitHub login (letters, digits and hyphens).\n' >/dev/tty
	done
}

ask_trailer() {
	while :; do
		case $(ask 'Add Co-Authored-By trailers to commit messages? (y/n)' "$1") in
		[Yy]*) echo yes && return ;;
		[Nn]*) echo no && return ;;
		esac
	done
}

# Whether the value is empty or a GitHub login.
valid_github() {
	case $1 in
	*[!A-Za-z0-9-]*) return 1 ;;
	esac
}

# Expand a leading "~/" so that the saved path does not depend on the shell.
expand_home() {
	# shellcheck disable=SC2088 # a literal "~/", expanded here
	case $1 in
	'~/'*) printf '%s/%s\n' "$HOME" "${1#'~/'}" ;;
	*) printf '%s\n' "$1" ;;
	esac
}

load_profile() {
	[ -f "$profile" ] || return 0
	while IFS='=' read -r key value; do
		case $key in
		name) saved_name=$value ;;
		gender) saved_gender=$value ;;
		language) saved_language=$value ;;
		co_author) saved_co_author=$value ;;
		assistant_name) saved_assistant_name=$value ;;
		assistant_email) saved_assistant_email=$value ;;
		assistant_signing_key) saved_assistant_signing_key=$value ;;
		assistant_github) saved_assistant_github=$value ;;
		co_author_trailer) saved_co_author_trailer=$value ;;
		style) saved_style=$value ;;
		esac
	done <"$profile"
	if [ -n "${saved_assistant_name+set}" ]; then
		if [ -n "$saved_assistant_email" ]; then
			saved_assistant="$saved_assistant_name <$saved_assistant_email>"
		else
			saved_assistant=
		fi
	elif [ -n "${saved_co_author+set}" ]; then
		# Profiles before the assistant identity: the co-author was the assistant.
		saved_assistant=$saved_co_author
		if [ -n "$saved_co_author" ]; then
			saved_co_author_trailer=yes
		else
			saved_co_author_trailer=no
		fi
	fi
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
	assistant=${opt_assistant-${saved_assistant-}}
	assistant_signing_key=${opt_assistant_signing_key-${saved_assistant_signing_key-}}
	assistant_github=${opt_assistant_github-${saved_assistant_github-}}
	if [ -n "$assistant" ]; then default_trailer=yes; else default_trailer=no; fi
	co_author_trailer=${opt_co_author_trailer-${saved_co_author_trailer-$default_trailer}}
	default_style=${opt_style-${saved_style:-kira-cozy}}

	missing=
	for key in $profile_keys; do
		case $key in
		assistant_* | co_author_trailer)
			# Meaningless without an assistant identity, unless it is about to be asked.
			case "$missing " in *' assistant '*) ;; *) [ -n "$assistant" ] || continue ;; esac
			;;
		esac
		if should_ask "$key"; then
			missing="$missing $key"
		fi
	done
	if [ -n "$missing" ]; then
		if ! can_prompt; then
			log "no terminal to ask for:$missing; using defaults (see --help)"
			# The optional assistant values default to empty; only a missing required value
			# keeps the profile unsaved, so that a later run on a terminal asks for it.
			for key in $missing; do
				case $key in name | gender | language | assistant) no_save=1 ;; esac
			done
			missing=
		fi
	fi
	for key in $missing; do
		case $key in
		name) user_name=$(ask 'How should Kira call you?' "$user_name") ;;
		gender) user_gender=$(ask_gender "$user_gender") ;;
		language) user_language=$(ask 'Which language should Kira answer in? (auto follows the conversation)' "$user_language") ;;
		assistant) assistant=$(ask_assistant "$assistant") ;;
		# The other assistant values mean nothing without an assistant identity.
		assistant_signing_key) [ -z "$assistant" ] || assistant_signing_key=$(ask_signing_key "$assistant_signing_key") ;;
		assistant_github) [ -z "$assistant" ] || assistant_github=$(ask_github "$assistant_github") ;;
		co_author_trailer)
			if [ -n "$assistant" ]; then default_trailer=yes; else default_trailer=no; fi
			[ -z "$assistant" ] || co_author_trailer=$(ask_trailer "${saved_co_author_trailer-$default_trailer}")
			;;
		esac
	done
	if [ -z "$assistant" ]; then
		assistant_signing_key='' assistant_github='' co_author_trailer=no
	fi
	assistant_signing_key=$(expand_home "$assistant_signing_key")
	if [ -n "$assistant" ]; then
		assistant_name=${assistant% <*}
		assistant_email=${assistant##*<}
		assistant_email=${assistant_email%>}
	else
		assistant_name='' assistant_email=''
	fi

	[ -z "${no_save-}" ] || return 0
	profile_text="name=$user_name${nl}gender=$user_gender${nl}language=$user_language${nl}assistant_name=$assistant_name${nl}assistant_email=$assistant_email${nl}assistant_signing_key=$assistant_signing_key${nl}assistant_github=$assistant_github${nl}co_author_trailer=$co_author_trailer${nl}style=$default_style"
	if [ -f "$profile" ] && [ "$(cat "$profile")" = "$profile_text" ]; then
		return
	fi
	log "save profile: $profile"
	if [ "$dry_run" -eq 1 ]; then
		printf '[dry-run] write %s to %s\n' "$(printf '%s' "$profile_text" | tr '\n' ' ')" "$profile"
	else
		mkdir -p "$CLAUDE_DIR"
		printf '%s\n' "$profile_text" >"$profile"
	fi
}

# R8: warn about a signing key that is not there; the installer never creates one.
check_signing_key() {
	[ -n "$assistant_signing_key" ] || return 0
	if [ ! -f "$assistant_signing_key" ]; then
		log "warning: the assistant's signing key $assistant_signing_key does not exist; it cannot commit as itself until it does"
	elif [ ! -f "${assistant_signing_key%.pub}" ]; then
		log "warning: no private key next to $assistant_signing_key; the assistant cannot sign with it"
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
	if [ "$co_author_trailer" = yes ]; then co_author=$assistant; else co_author=; fi
	sh "$src/scripts/build.sh" -o "$build_dir" --name "$user_name" --gender "$user_gender" \
		--language "$user_language" --co-author "$co_author" --assistant "$assistant" \
		--assistant-signing-key "$assistant_signing_key" --assistant-github "$assistant_github" \
		>/dev/null || exit 1
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

# Copy settings.json to the backups once per run, before its first change.
backup_settings() {
	if [ -f "$settings" ] && [ -z "${settings_backed_up-}" ]; then
		backup "$settings" "$CLAUDE_DIR" '' cp
		settings_backed_up=1
	fi
}

# insert_setting LINE FILE: print FILE with LINE as the first setting, or a new object.
insert_setting() {
	if [ ! -s "$2" ] || [ "$(tr -d ' \t\r\n' <"$2")" = '{}' ]; then
		printf '{\n  %s\n}\n' "$1"
		return
	fi
	awk -v line="$1" '
		!done && (i = index($0, "{")) {
			print substr($0, 1, i)
			print "  " line ","
			rest = substr($0, i + 1)
			if (rest ~ /[^ \t]/) print rest
			done = 1
			next
		}
		{ print }' "$2"
}

# R11: turn off the attribution Claude Code suggests, so the git rules are the only ones. An
# "attribution" setting the user wrote is left alone: without a JSON parser, it cannot be
# merged safely.
set_attribution() {
	settings=$CLAUDE_DIR/settings.json
	line='"attribution": {"commit": "", "pr": ""}'
	if [ -f "$settings" ]; then
		flat=$(tr -d ' \t\r\n' <"$settings")
		case $flat in
		*'"attribution":{"commit":"","pr":""}'* | *'"attribution":{"pr":"","commit":""}'*)
			log "up to date: $settings (attribution)"
			return
			;;
		*'"attribution":'*)
			log "warning: $settings already sets \"attribution\"; left unchanged. For the git rules alone to apply, set it by hand to: $line"
			return
			;;
		esac
	fi
	work_dir
	insert_setting "$line" "$settings" >"$work/settings.json"
	backup_settings
	log "set attribution: commit and pr off in $settings"
	if [ "$dry_run" -eq 0 ]; then
		mkdir -p "$CLAUDE_DIR"
		# Write in place to keep the file's permissions and any symlink.
		cat "$work/settings.json" >"$settings"
	fi
}

# Set "outputStyle" in settings.json to the default style, leaving every other setting as it
# is: Claude Code writes to this file too, so it is edited in place, never replaced.
set_output_style() {
	settings=$CLAUDE_DIR/settings.json
	value=$(sed -n 's/^name: //p' "$build_dir/output-styles/$default_style.md" | head -n 1)
	case $value in
	'' | *'"'* | *\\*) die "cannot use the name of $default_style as outputStyle: $value" ;;
	esac
	line="\"outputStyle\": \"$value\""
	if [ -f "$settings" ] && grep -qF "$line" "$settings"; then
		log "up to date: $settings (outputStyle)"
		return
	fi

	work_dir
	new=$work/settings.json
	if [ -s "$settings" ] && grep -q '"outputStyle"[[:space:]]*:' "$settings"; then
		escaped=$(printf '%s\n' "$line" | sed 's/[&|\\]/\\&/g')
		sed "s|\"outputStyle\"[[:space:]]*:[[:space:]]*\"[^\"]*\"|$escaped|" "$settings" >"$new"
	else
		insert_setting "$line" "$settings" >"$new"
	fi

	backup_settings
	log "set outputStyle: $value in $settings"
	if [ "$dry_run" -eq 0 ]; then
		mkdir -p "$CLAUDE_DIR"
		# Write in place to keep the file's permissions and any symlink.
		cat "$new" >"$settings"
	fi
}

install_claude() {
	if [ -f "$build_dir/CLAUDE.md" ]; then
		install_file "$(built CLAUDE.md)" "$CLAUDE_DIR/CLAUDE.md"
	fi
	for file in "$src"/claude/agents/*.md; do
		[ -f "$file" ] || continue
		agent=$(basename "$file")
		install_file "$(built "agents/$agent")" "$CLAUDE_DIR/agents/$agent"
	done
	# Claude Code loads every file of rules/ on its own.
	for file in "$src"/claude/rules/*.md; do
		[ -f "$file" ] || continue
		rules=$(basename "$file")
		install_file "$(built "rules/$rules")" "$CLAUDE_DIR/rules/$rules"
	done
	# Skills are directories holding a SKILL.md, installed as a whole.
	for dir in "$src"/claude/skills/*/; do
		[ -f "$dir/SKILL.md" ] || continue
		skill=$(basename "$dir")
		install_file "$(built "skills/$skill")" "$CLAUDE_DIR/skills/$skill"
	done
	set_output_style
	set_attribution
}

# Copy github/ into the target repository's .github directory. Files are always copied:
# they belong to that repository and are committed there.
install_github() {
	if [ -z "$github_target" ]; then
		github_target=$(git rev-parse --show-toplevel 2>/dev/null) ||
			die "--only github needs a Git repository: run it from one or pass --target DIR"
	fi
	[ -d "$github_target" ] || die "not a directory: $github_target"
	github_target=$(CDPATH='' cd -- "$github_target" && pwd)
	log "github target: $github_target/.github"
	mode=copy
	find "$src/github" -type f ! -name .gitkeep | sort | while IFS= read -r file; do
		rel=${file#"$src/github/"}
		install_file "$file" "$github_target/.github/$rel" "$github_target" \
			"github/$(basename "$github_target")/"
	done
}

# Merge this run's targets into the manifest read by --uninstall, and the backups of files
# that were there before kirakit into the list of originals.
write_manifest() {
	[ -n "$installed" ] || return 0
	if [ "$dry_run" -eq 1 ]; then
		printf '[dry-run] record installed files in %s\n' "$manifest"
		return
	fi
	{
		if [ -f "$manifest" ]; then
			cat "$manifest"
		fi
		printf '%s' "$installed"
	} | sort -u >"$manifest.tmp"
	mv -f "$manifest.tmp" "$manifest"
	if [ -n "$originals_new" ]; then
		printf '%s' "$originals_new" >>"$originals"
	fi
}

# Remove what the manifest lists: symlinks are deleted, copies are moved to the backups, and
# files that were there before kirakit are restored.
uninstall_all() {
	[ -f "$manifest" ] || die "nothing to uninstall: $manifest not found"
	while IFS= read -r path; do
		case $path in
		'') continue ;;
		*/../* | */..) log "skip: $path" && continue ;;
		"$CLAUDE_DIR"/*) ;;
		*) log "skip (outside $CLAUDE_DIR): $path" && continue ;;
		esac
		if [ -L "$path" ]; then
			log "remove link: $path"
			run rm -f -- "$path"
		elif [ -e "$path" ]; then
			backup "$path"
		fi
		original=
		if [ -f "$originals" ]; then
			original=$(awk -F "$tab" -v path="$path" '$1 == path { print $2; exit }' "$originals")
		fi
		if [ -n "$original" ] && { [ -e "$original" ] || [ -L "$original" ]; }; then
			log "restore: $original -> $path"
			run mv -- "$original" "$path"
		fi
	done <"$manifest"
	log "remove manifest: $manifest"
	run rm -f -- "$manifest" "$originals"
	log "kept: $profile, $CLAUDE_DIR/.kirakit-backups and the outputStyle and attribution settings"
}

while [ $# -gt 0 ]; do
	case $1 in
	--dry-run) dry_run=1 ;;
	--name | --gender | --language | --co-author | --assistant | --assistant-signing-key | \
		--assistant-github | --default-style | --persona | --only | --target)
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
		--co-author | --assistant)
			if [ -z "$2" ] || ! valid_co_author "$2"; then
				die "invalid ${1#--}: $2 (expected \"NAME <EMAIL>\")"
			fi
			opt_assistant=$2
			# --co-author predates the assistant identity: it also asks for the trailer.
			[ "$1" = --assistant ] || opt_co_author_trailer=yes
			;;
		--assistant-signing-key)
			case $2 in *"$nl"*) die "invalid signing key path: $2" ;; esac
			opt_assistant_signing_key=$2
			;;
		--assistant-github)
			valid_github "$2" || die "invalid GitHub login: $2"
			opt_assistant_github=$2
			;;
		--default-style | --persona)
			case $2 in
			'' | -* | *[!A-Za-z0-9_-]*) die "invalid persona name: $2" ;;
			esac
			if [ "$1" = --persona ]; then
				personas="$personas $2"
			else
				opt_style=$2
			fi
			;;
		--only)
			case $2 in
			styles | claude | github) only=$2 ;;
			*) die "unknown component: $2 (expected styles, claude or github)" ;;
			esac
			;;
		--target) github_target=$2 ;;
		esac
		shift
		;;
	--no-co-author) opt_co_author_trailer=no ;;
	--reconfigure) reconfigure=1 ;;
	--link) mode='link' ;;
	--copy) mode=copy ;;
	--uninstall) uninstall=1 ;;
	-h | --help)
		usage
		exit 0
		;;
	*) die "unknown option: $1 (see --help)" ;;
	esac
	shift
done

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

[ "$dry_run" -eq 0 ] || log "dry run: nothing will be changed"

if [ "$uninstall" -eq 1 ]; then
	uninstall_all
	log "done"
	exit 0
fi

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
	ref=$(resolve_ref)
	log "fetching $KIRAKIT_REPO ($ref)"
	git clone --quiet --depth 1 --branch "$ref" -- "$KIRAKIT_REPO" "$work/repo" ||
		die "could not fetch $KIRAKIT_REPO"
	src=$work/repo
	mode=copy
fi
[ -n "$mode" ] || mode='link'

for persona in $personas ${opt_style-}; do
	[ -f "$src/personas/$persona.md" ] || die "unknown persona: $persona"
done

log "source: $src ($mode mode)"

if [ "$only" = github ]; then
	install_github
	log "done"
	exit 0
fi

log "target: $CLAUDE_DIR"
setup_profile
[ -f "$src/personas/$default_style.md" ] || die "unknown default style: $default_style"
log "profile: ${user_name:-(no name)}, $user_gender, language $user_language, assistant ${assistant:-none}, co-author trailers $co_author_trailer, style $default_style"
check_signing_key
build

if [ -z "$only" ] || [ "$only" = styles ]; then
	install_styles
fi
if [ -z "$only" ] || [ "$only" = claude ]; then
	install_claude
fi
write_manifest

log "done"
