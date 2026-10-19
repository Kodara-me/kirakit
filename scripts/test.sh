#!/bin/sh
# End-to-end tests for build.sh and get-kira.sh. Everything happens in a temporary
# directory: the real Claude Code configuration is never touched.
#
# Usage: scripts/test.sh [SHELL]   (the shell running the scripts, default: sh; it may hold
#                                   options, such as "bash --posix")
#
# Single-quoted "$1" and backquotes below are meant for sh -c and Markdown.
# shellcheck disable=SC2016
set -eu

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
shell=${1:-sh}
tmp=$(mktemp -d "${TMPDIR:-/tmp}/kirakit-test.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
failures=0
claude=

check() {
	description=$1
	shift
	if "$@" >/dev/null 2>&1; then
		printf 'ok    %s\n' "$description"
	else
		printf 'FAIL  %s\n' "$description"
		failures=$((failures + 1))
	fi
}

# The shell is split on purpose, to allow options.
# shellcheck disable=SC2086
kira() {
	CLAUDE_CONFIG_DIR=$claude $shell "$root/get-kira.sh" "$@" </dev/null
}

# kira with a complete profile, so that nothing is asked.
kira_profile() {
	kira --name Alex --gender female --language auto --co-author 'Kira <kira@example.com>' "$@"
}

# Whether a run succeeded and changed nothing.
unchanged() {
	output=$("$@") || return 1
	! printf '%s\n' "$output" | grep -Eq '^kirakit: (link|copy|backup|set|save)'
}

no_placeholder() {
	! grep -rq '{{' "$1"
}

contains() {
	grep -qF -- "$2" "$1"
}

# --- build ---------------------------------------------------------------------------------

$shell "$root/scripts/build.sh" -o "$tmp/build" >/dev/null
check 'build: no placeholder left' no_placeholder "$tmp/build"
check 'build: generic profile' contains "$tmp/build/output-styles/kira-cozy.md" 'The user is a staff software developer.'
$shell "$root/scripts/build.sh" -o "$tmp/build2" --name Alex --gender female --language French \
	--co-author 'Kira <kira@example.com>' >/dev/null
check 'build: pronouns' contains "$tmp/build2/output-styles/kira-sassy.md" 'sitting beside her'
check 'build: language' contains "$tmp/build2/skills/push/SKILL.md" 'Answer in French.'
check 'build: co-author trailer' contains "$tmp/build2/skills/commit/SKILL.md" 'Co-Authored-By: Kira <kira@example.com>'
check 'build: rejects a bad co-author' sh -c '! $1 "$2/scripts/build.sh" -o "$3" --co-author Kira' _ "$shell" "$root" "$tmp/x"

# --- dry run -------------------------------------------------------------------------------

claude=$tmp/dry
kira_profile --dry-run >/dev/null
check 'dry run: writes nothing' test ! -e "$claude"

# --- link mode -----------------------------------------------------------------------------

claude=$tmp/link
mkdir -p "$claude"
printf '# mine\n' >"$claude/CLAUDE.md"
printf '{\n  "outputStyle": "Other",\n  "keep": true\n}\n' >"$claude/settings.json"
kira_profile >/dev/null
check 'link: styles are links' test -L "$claude/output-styles/kira-cozy.md"
check 'link: skills are links' test -L "$claude/skills/commit"
check 'link: CLAUDE.md is a link' test -L "$claude/CLAUDE.md"
check 'link: outputStyle set' contains "$claude/settings.json" '"outputStyle": "Kira (cozy)"'
check 'link: other settings kept' contains "$claude/settings.json" '"keep": true'
check 'link: profile saved' contains "$claude/.kirakit-profile" 'co_author=Kira <kira@example.com>'
check 'link: rerun changes nothing' unchanged kira
kira --uninstall >/dev/null
check 'uninstall: links removed' test ! -e "$claude/output-styles/kira-cozy.md"
check 'uninstall: original CLAUDE.md restored' contains "$claude/CLAUDE.md" '# mine'
check 'uninstall: manifest removed' test ! -e "$claude/.kirakit-manifest"

# --- copy mode -----------------------------------------------------------------------------

claude=$tmp/copy
kira_profile --copy --default-style kira-focus >/dev/null
check 'copy: styles are files' test -f "$claude/output-styles/kira-focus.md" -a ! -L "$claude/output-styles/kira-focus.md"
check 'copy: settings created' contains "$claude/settings.json" '"outputStyle": "Kira (focus)"'
check 'copy: rerun changes nothing' unchanged kira --copy
kira --uninstall >/dev/null
check 'uninstall: copies moved to backups' test ! -e "$claude/skills/commit"
check 'uninstall: backups kept' test -d "$claude/.kirakit-backups"

# --- no terminal ---------------------------------------------------------------------------

claude=$tmp/generic
kira --copy >/dev/null
check 'no terminal: generic styles' contains "$claude/output-styles/kira-cozy.md" 'The user is a staff software developer.'
check 'no terminal: no profile saved' test ! -e "$claude/.kirakit-profile"

# --- github --------------------------------------------------------------------------------

claude=$tmp/github-claude
git init -q "$tmp/project"
(cd "$tmp/project" && CLAUDE_CONFIG_DIR=$claude $shell "$root/get-kira.sh" --only github >/dev/null)
check 'github: templates copied' test -f "$tmp/project/.github/ISSUE_TEMPLATE/feature_request.yml"
check 'github: workflow copied' test -f "$tmp/project/.github/workflows/pr-title.yml"
check 'github: rerun changes nothing' unchanged kira --only github --target "$tmp/project"
check 'github: needs a repository' sh -c 'cd "$1" && ! CLAUDE_CONFIG_DIR="$2" $3 "$4/get-kira.sh" --only github' _ "$tmp" "$claude" "$shell" "$root"

# --- without a clone (curl) ----------------------------------------------------------------

# Commit the working tree into a scratch repository, so uncommitted changes are tested too.
mkdir "$tmp/remote"
(cd "$root" && git ls-files -co --exclude-standard | while IFS= read -r file; do
	[ -f "$file" ] || continue
	mkdir -p "$tmp/remote/$(dirname "$file")"
	cp -p "$file" "$tmp/remote/$file"
done)
git -C "$tmp/remote" init -q -b main
git -C "$tmp/remote" -c core.safecrlf=false add -A
git -C "$tmp/remote" -c user.name=test -c user.email=test@example.com -c commit.gpgsign=false \
	commit -q -m test
claude=$tmp/curl
CLAUDE_CONFIG_DIR=$claude KIRAKIT_REPO="file://$tmp/remote" KIRAKIT_REF=main \
	$shell -s -- --name Alex --gender female --language auto --no-co-author \
	<"$root/get-kira.sh" >/dev/null
check 'curl: styles copied' test -f "$claude/output-styles/kira-cozy.md" -a ! -L "$claude/output-styles/kira-cozy.md"
check 'curl: no co-author' contains "$claude/skills/commit/SKILL.md" 'add no `Co-Authored-By` line'

if [ "$failures" -gt 0 ]; then
	printf '%s test(s) failed\n' "$failures"
	exit 1
fi
printf 'all tests passed\n'
