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
check 'build: spec skill' contains "$tmp/build2/skills/spec/SKILL.md" 'Answer in French.'
check 'build: idea skill' contains "$tmp/build2/skills/idea/SKILL.md" 'Answer in French.'
check 'build: co-author trailer' contains "$tmp/build2/rules/git.md" 'Co-Authored-By: Kira <kira@example.com>'
check 'build: no attribution text in skills' sh -c '! grep -rq "Co-Authored-By: [A-Z]" "$1/skills"' _ "$tmp/build2"
check 'build: CLAUDE.md does not import the rules' sh -c '! grep -q "^@" "$1/CLAUDE.md"' _ "$tmp/build2"
check 'build: no rules for the assistant without a key' contains "$tmp/build2/rules/git.md" 'it never commits as itself'
check 'build: no GitHub section without a login' sh -c '! grep -q "GitHub account" "$1/rules/git.md"' _ "$tmp/build2"
$shell "$root/scripts/build.sh" -o "$tmp/build3" --co-author 'Kira <kira@example.com>' \
	--assistant 'Kira <kira@example.com>' --assistant-signing-key /keys/kira.pub --assistant-github kira-bot >/dev/null
check 'rules: assistant commit command' contains "$tmp/build3/rules/git.md" '-c user.signingkey=/keys/kira.pub'
check 'rules: which skill commits' contains "$tmp/build3/rules/git.md" 'use `assistant-commit` for changes'
check 'rules: user trailer for assistant commits' contains "$tmp/build3/rules/git.md" "the user's \`git config user.name\`"
check 'rules: GitHub account section' contains "$tmp/build3/rules/git.md" 'GH_TOKEN=$(gh auth token --user kira-bot)'
check 'rules: questions in comments' contains "$tmp/build3/rules/git.md" 'Can I continue?'
$shell "$root/scripts/build.sh" -o "$tmp/build4" --assistant 'Kira <kira@example.com>' \
	--assistant-signing-key /keys/kira.pub >/dev/null
check 'rules: --no-co-author means no trailer at all' contains "$tmp/build4/rules/git.md" 'Commit messages have no `Co-Authored-By` line.'
check 'rules: no assistant trailer without co-author' sh -c '! grep -q "Commits made by the assistant" "$1/rules/git.md"' _ "$tmp/build4"

# --- assistant-commit ----------------------------------------------------------------------

# R7: without a signing key, the skill only says it cannot commit.
check 'assistant-commit: stops without a key' contains "$tmp/build2/skills/assistant-commit/SKILL.md" 'never commits as itself. Do not commit'
check 'assistant-commit: no command without a key' sh -c '! grep -q "git -c user.name" "$1"' _ "$tmp/build2/skills/assistant-commit/SKILL.md"
check "assistant-commit: asks for the user's trailer" contains "$tmp/build3/skills/assistant-commit/SKILL.md" 'Co-Authored-By: <user name> <<user email>>'
check 'assistant-commit: no trailer with --no-co-author' contains "$tmp/build4/skills/assistant-commit/SKILL.md" 'No `Co-Authored-By` line.'

# R5: run the commit command written in the skill, with a throwaway key, in a scratch
# repository isolated from the user's git configuration.
if command -v ssh-keygen >/dev/null 2>&1; then
	keys=$tmp/commit-keys
	mkdir -p "$keys"
	ssh-keygen -q -t ed25519 -N '' -C test -f "$keys/kira"
	$shell "$root/scripts/build.sh" -o "$tmp/build-ac" --co-author 'Kira <kira@example.com>' \
		--assistant 'Kira <kira@example.com>' --assistant-signing-key "$keys/kira.pub" >/dev/null
	skill=$tmp/build-ac/skills/assistant-commit/SKILL.md
	command=$(sed -n 's/^ *\(git -c user.name=.*\)$/\1/p' "$skill")
	nl='
'
	repo=$tmp/commit-repo
	git init -q "$repo"
	(
		export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
		cd "$repo"
		git config user.name Alex
		git config user.email alex@example.com
		printf 'a\n' >file
		git add file
		# The command ends with a heredoc start; the message and its end follow.
		eval "$command${nl}feat: add a file${nl}${nl}Co-Authored-By: Alex <alex@example.com>${nl}MESSAGE"
	) >/dev/null 2>&1 || true
	printf 'kira@example.com namespaces="git" %s\n' "$(cut -d' ' -f1,2 "$keys/kira.pub")" >"$keys/allowed"
	check 'assistant-commit: one command in the skill' test "$(printf '%s\n' "$command" | grep -c .)" -eq 1
	check 'assistant-commit: authored by the assistant' test \
		"$(GIT_CONFIG_GLOBAL=/dev/null git -C "$repo" log -1 --format='%an <%ae>|%cn <%ce>')" = \
		'Kira <kira@example.com>|Kira <kira@example.com>'
	check 'assistant-commit: signed with its key' env GIT_CONFIG_GLOBAL=/dev/null \
		git -C "$repo" -c gpg.ssh.allowedSignersFile="$keys/allowed" verify-commit HEAD
	check "assistant-commit: the user's trailer" test \
		"$(GIT_CONFIG_GLOBAL=/dev/null git -C "$repo" log -1 --format=%B | sed '/^$/d' | tail -n 1)" = \
		'Co-Authored-By: Alex <alex@example.com>'
	check "assistant-commit: the user's config untouched" test \
		"$(GIT_CONFIG_GLOBAL=/dev/null git -C "$repo" config user.name)" = Alex
else
	printf 'skip  assistant-commit: ssh-keygen not found\n'
fi
check 'build: rejects a bad co-author' sh -c '! $1 "$2/scripts/build.sh" -o "$3" --co-author Kira' _ "$shell" "$root" "$tmp/x"

# Conditional blocks and assistant placeholders, on a copy of the sources with a test skill.
blocks=$tmp/blocks-src
mkdir -p "$blocks/claude/skills/blocks"
cp -R "$root/scripts" "$root/personas" "$blocks/"
cp "$root/claude/CLAUDE.md" "$blocks/claude/"
cat >"$blocks/claude/skills/blocks/SKILL.md" <<'EOF'
first
{{#assistant_github}}
github {{assistant_github}}
{{#assistant_signing_key}}
key {{assistant_signing_key}}
{{/assistant_signing_key}}
{{/assistant_github}}
{{^assistant_github}}
no github
{{/assistant_github}}
assistant {{assistant_name}} <{{assistant_email}}>
last
EOF

# build_blocks DIR OPTION...: build the copy into DIR.
build_blocks() {
	out=$1
	shift
	$shell "$blocks/scripts/build.sh" -o "$out" "$@" >/dev/null 2>&1
}

# same_lines FILE LINE...: whether FILE holds exactly these lines.
same_lines() {
	file=$1
	shift
	printf '%s\n' "$@" | cmp -s - "$file"
}

build_blocks "$tmp/blocks-all" --assistant 'Kira <kira@example.com>' --assistant-github kira-bot \
	--assistant-signing-key /keys/kira.pub
check 'blocks: kept when set, nested too' same_lines "$tmp/blocks-all/skills/blocks/SKILL.md" \
	first 'github kira-bot' 'key /keys/kira.pub' 'assistant Kira <kira@example.com>' last
build_blocks "$tmp/blocks-nokey" --assistant 'Kira <kira@example.com>' --assistant-github kira-bot
check 'blocks: nested block dropped when empty' same_lines "$tmp/blocks-nokey/skills/blocks/SKILL.md" \
	first 'github kira-bot' 'assistant Kira <kira@example.com>' last
build_blocks "$tmp/blocks-none"
check 'blocks: inverted block kept when empty' same_lines "$tmp/blocks-none/skills/blocks/SKILL.md" \
	first 'no github' 'assistant  <>' last
check 'build: rejects a bad assistant' sh -c '! $1 "$2/scripts/build.sh" -o "$3" --assistant Kira' _ "$shell" "$root" "$tmp/x"
check 'build: rejects a bad GitHub login' sh -c '! $1 "$2/scripts/build.sh" -o "$3" --assistant-github "a b"' _ "$shell" "$root" "$tmp/x"
printf '{{#assistant_github}}\nopen\n' >"$blocks/claude/skills/blocks/SKILL.md"
check 'blocks: rejects an unclosed block' sh -c '! $1 "$2/scripts/build.sh" -o "$3"' _ "$shell" "$blocks" "$tmp/x"
printf 'text\n{{/assistant_github}}\n' >"$blocks/claude/skills/blocks/SKILL.md"
check 'blocks: rejects an unopened block' sh -c '! $1 "$2/scripts/build.sh" -o "$3"' _ "$shell" "$blocks" "$tmp/x"
printf '{{#nothing}}\n{{/nothing}}\n' >"$blocks/claude/skills/blocks/SKILL.md"
check 'blocks: rejects an unknown key' sh -c '! $1 "$2/scripts/build.sh" -o "$3"' _ "$shell" "$blocks" "$tmp/x"

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
check 'link: rules are links' test -L "$claude/rules/git.md"
check 'link: outputStyle set' contains "$claude/settings.json" '"outputStyle": "Kira (cozy)"'
check 'link: other settings kept' contains "$claude/settings.json" '"keep": true'
check 'link: profile saved' contains "$claude/.kirakit-profile" 'assistant_email=kira@example.com'
check 'link: rerun changes nothing' unchanged kira
kira --uninstall >/dev/null
check 'uninstall: links removed' test ! -e "$claude/output-styles/kira-cozy.md"
check 'uninstall: rules removed' test ! -e "$claude/rules/git.md"
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

# --- assistant profile ---------------------------------------------------------------------

# profile_has KEY=VALUE: whether the profile of $claude holds this line.
profile_has() {
	grep -qxF -- "$1" "$claude/.kirakit-profile"
}

claude=$tmp/assistant
mkdir -p "$tmp/keys"
: >"$tmp/keys/kira" && : >"$tmp/keys/kira.pub"
kira --copy --name Alex --gender female --language auto --co-author 'Kira <kira@example.com>' \
	--assistant-signing-key "$tmp/keys/kira.pub" --assistant-github kira-bot >"$tmp/assistant.log"
check 'assistant: name saved' profile_has 'assistant_name=Kira'
check 'assistant: email saved' profile_has 'assistant_email=kira@example.com'
check 'assistant: signing key saved' profile_has "assistant_signing_key=$tmp/keys/kira.pub"
check 'assistant: GitHub login saved' profile_has 'assistant_github=kira-bot'
check 'assistant: --co-author asks for trailers' profile_has 'co_author_trailer=yes'
check 'assistant: no co_author key' sh -c '! grep -q "^co_author=" "$1"' _ "$claude/.kirakit-profile"
check 'assistant: no warning with both keys' sh -c '! grep -q warning "$1"' _ "$tmp/assistant.log"
check 'assistant: trailer in the rules' contains "$claude/rules/git.md" 'Co-Authored-By: Kira <kira@example.com>'
check 'assistant: rerun changes nothing' unchanged kira --copy

# Without a terminal, the optional assistant values default to empty, and trailers to yes.
claude=$tmp/assistant-only
kira --copy --name Alex --gender female --language auto --assistant 'Kira <kira@example.com>' >/dev/null
check 'assistant only: profile saved' profile_has 'assistant_name=Kira'
check 'assistant only: no signing key' profile_has 'assistant_signing_key='
check 'assistant only: trailers by default' profile_has 'co_author_trailer=yes'
check 'assistant only: trailer in the rules' contains "$claude/rules/git.md" 'Co-Authored-By: Kira <kira@example.com>'
check 'assistant only: rerun changes nothing' unchanged kira --copy

claude=$tmp/assistant-no-trailer
kira_profile --copy --no-co-author >/dev/null
check 'no trailer: saved' profile_has 'co_author_trailer=no'
check 'no trailer: assistant kept' profile_has 'assistant_name=Kira'
check 'no trailer: rules have none' contains "$claude/rules/git.md" 'Commit messages have no `Co-Authored-By` line.'

# R8: the installer warns about a missing key and never creates one.
claude=$tmp/missing-key
kira_profile --copy --assistant-signing-key "$tmp/keys/none.pub" >"$tmp/missing-key.log" 2>&1
check 'missing key: warned' grep -q 'signing key .* does not exist' "$tmp/missing-key.log"
check 'missing key: not created' test ! -e "$tmp/keys/none.pub"
: >"$tmp/keys/public-only.pub"
kira_profile --copy --assistant-signing-key "$tmp/keys/public-only.pub" >"$tmp/public-only.log" 2>&1
check 'missing private key: warned' grep -q 'no private key next to' "$tmp/public-only.log"
status=0
kira_profile --copy --assistant-github 'a b' >/dev/null 2>&1 || status=$?
check 'bad GitHub login: rejected' test "$status" -ne 0

# R2: profiles saved before the assistant identity are migrated without asking.
claude=$tmp/migrate
mkdir -p "$claude"
printf 'name=Alex\ngender=male\nlanguage=auto\nco_author=Kira <kira@example.com>\nstyle=kira-cozy\n' \
	>"$claude/.kirakit-profile"
kira --copy >/dev/null
check 'migrate: assistant from co_author' profile_has 'assistant_email=kira@example.com'
check 'migrate: trailers kept' profile_has 'co_author_trailer=yes'
check 'migrate: co_author dropped' sh -c '! grep -q "^co_author=" "$1"' _ "$claude/.kirakit-profile"
check 'migrate: other values kept' profile_has 'name=Alex'

claude=$tmp/migrate-none
mkdir -p "$claude"
printf 'name=Alex\ngender=male\nlanguage=auto\nco_author=\nstyle=kira-cozy\n' >"$claude/.kirakit-profile"
kira --copy >/dev/null
check 'migrate: no co-author means no trailers' profile_has 'co_author_trailer=no'
check 'migrate: no assistant' profile_has 'assistant_name='

# --- attribution in settings.json (R11) ----------------------------------------------------

attribution='"attribution": {"commit": "", "pr": ""}'

claude=$tmp/attribution
mkdir -p "$claude"
printf '{\n  "keep": true\n}\n' >"$claude/settings.json"
cp "$claude/settings.json" "$tmp/settings.orig"
kira_profile --copy >"$tmp/attribution.log"
check 'attribution: set' contains "$claude/settings.json" "$attribution"
check 'attribution: other settings kept' contains "$claude/settings.json" '"keep": true'
check 'attribution: original backed up once' sh -c 'cmp -s "$1" "$(find "$2/.kirakit-backups" -name settings.json | head -n 1)"' _ \
	"$tmp/settings.orig" "$claude"
check 'attribution: rerun changes nothing' unchanged kira --copy
kira --uninstall >/dev/null
check 'attribution: kept by uninstall' contains "$claude/settings.json" "$attribution"

claude=$tmp/attribution-same
mkdir -p "$claude"
printf '{\n  "attribution": {\n    "pr": "",\n    "commit": ""\n  }\n}\n' >"$claude/settings.json"
kira_profile --copy >"$tmp/attribution-same.log"
check 'attribution: same value in another layout is up to date' grep -q 'up to date: .*(attribution)' "$tmp/attribution-same.log"

claude=$tmp/attribution-mine
mkdir -p "$claude"
printf '{\n  "attribution": {"commit": "Mine"}\n}\n' >"$claude/settings.json"
kira_profile --copy >"$tmp/attribution-mine.log"
check 'attribution: a user value is warned about' grep -q 'already sets "attribution"; left unchanged' "$tmp/attribution-mine.log"
check 'attribution: a user value is left unchanged' contains "$claude/settings.json" '"attribution": {"commit": "Mine"}'

claude=$tmp/attribution-dry
mkdir -p "$claude"
printf '{\n  "keep": true\n}\n' >"$claude/settings.json"
kira_profile --dry-run >"$tmp/attribution-dry.log"
check 'attribution: dry run reports' grep -q 'set attribution' "$tmp/attribution-dry.log"
check 'attribution: dry run writes nothing' sh -c '! grep -q attribution "$1"' _ "$claude/settings.json"

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
check 'curl: no co-author' contains "$claude/rules/git.md" 'Commit messages have no `Co-Authored-By` line.'

# Which branch or tag a run without a clone fetches.
fetched() {
	CLAUDE_CONFIG_DIR=$tmp/ref KIRAKIT_REPO="file://$tmp/remote" $shell -s -- --dry-run \
		--name Alex --gender female --language auto --no-co-author <"$1" |
		sed -n 's/^kirakit: fetching .* (\(.*\))$/\1/p'
}

check 'ref: main without release tags' test "$(fetched "$root/get-kira.sh")" = main
for tag in v0.9.0 v0.10.0 v0.2.1 v1.0.0-rc1; do
	git -C "$tmp/remote" -c tag.gpgsign=false tag "$tag"
done
check 'ref: highest release tag by default' test "$(fetched "$root/get-kira.sh")" = v0.10.0
sed 's/^KIRAKIT_VERSION=$/KIRAKIT_VERSION=v0.9.0/' "$root/get-kira.sh" >"$tmp/stamped.sh"
check 'ref: a stamped copy installs its own version' test "$(fetched "$tmp/stamped.sh")" = v0.9.0
check 'ref: KIRAKIT_REF wins' test "$(KIRAKIT_REF=main fetched "$tmp/stamped.sh")" = main

if [ "$failures" -gt 0 ]; then
	printf '%s test(s) failed\n' "$failures"
	exit 1
fi
printf 'all tests passed\n'
