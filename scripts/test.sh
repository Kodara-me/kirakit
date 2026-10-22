#!/bin/sh
# End-to-end tests for build.sh and get-kira.sh. Everything happens in a temporary
# directory: the real Claude Code configuration is never touched, nor the clone's dist/,
# which a link install points to.
#
# Usage: scripts/test.sh [SHELL]   (the shell running the scripts, default: sh; it may hold
#                                   options, such as "bash --posix")
#
# Single-quoted "$1" and backquotes below are meant for sh -c and Markdown.
# shellcheck disable=SC2016
set -eu

clone=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
shell=${1:-sh}
tmp=$(mktemp -d "${TMPDIR:-/tmp}/kirakit-test.XXXXXX")
# Without the double slash of a TMPDIR that ends with one (macOS), as pwd prints it.
tmp=$(cd "$tmp" && pwd)
trap 'rm -rf "$tmp"' EXIT
failures=0
claude=
# The launchers go to ~/.local/bin and their Konsole color schemes to $XDG_DATA_HOME/konsole:
# never the real ones.
HOME=$tmp/home
XDG_DATA_HOME=$tmp/data
XDG_CONFIG_HOME=$tmp/config
export HOME XDG_DATA_HOME XDG_CONFIG_HOME
# Nor the real Konsole: no D-Bus session, and the color sequences go to a file.
unset KONSOLE_DBUS_SESSION KONSOLE_DBUS_SERVICE KONSOLE_DBUS_WINDOW KONSOLE_VERSION
KIRAKIT_TTY=$tmp/tty
export KIRAKIT_TTY

# The scripts run from a copy of the working tree, uncommitted changes included, so that
# link mode builds into the copy's dist/.
root=$tmp/src
(cd "$clone" && git ls-files -co --exclude-standard | while IFS= read -r file; do
	[ -f "$file" ] || continue
	mkdir -p "$root/$(dirname "$file")"
	cp -p "$file" "$root/$file"
done)

# A fingerprint of the clone's dist/, compared at the end.
dist_fingerprint() {
	[ -d "$clone/dist" ] || return 0
	(cd "$clone" && find dist -type f -exec cksum {} + | sort)
}
dist_before=$(dist_fingerprint)

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
	CLAUDE_CONFIG_DIR=$claude HOME=$claude-home XDG_DATA_HOME=$claude-data $shell "$root/get-kira.sh" "$@" </dev/null
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

# profile_has KEY=VALUE: whether the profile of $claude holds this line.
profile_has() {
	grep -qxF -- "$1" "$claude/.kirakit-profile"
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

# Voices in comments, neutral descriptions (#79 R11, R12, R13).
for style in "$tmp/build2"/output-styles/kira-*.md; do
	check "voice: $(basename "$style" .md) in comments (R11)" contains "$style" 'Persona shows in the conversation and in her comments on GitHub'
	check "voice: $(basename "$style" .md) keeps descriptions neutral (R12)" contains "$style" 'Issue bodies, pull request descriptions, commit messages, code, code comments and documents stay neutral'
done
check 'voice: comments keep their required content (R13)' contains "$tmp/build2/rules/git.md" 'The voice never replaces what a comment requires'
check 'voice: comments in the repository language (R13)' contains "$tmp/build2/rules/git.md" "in the repository's"
check 'voice: no file keeps comments neutral (R11)' sh -c '! grep -rqF -e "Persona stays in the conversation" -e "Code, comments, commit messages" -e "specifications, comments and documents" "$1"' _ "$tmp/build2"
check 'voice: spec comments follow the voice (R11)' contains "$tmp/build2/skills/spec/SKILL.md" "follow the member's own voice"
check 'voice: idea comments follow the voice (R11)' contains "$tmp/build2/skills/idea/SKILL.md" "follow the member's own voice"
spec_skill=$tmp/build2/skills/spec/SKILL.md
check 'spec: settles what has a good answer (#51 R2)' contains "$spec_skill" 'the code, an existing convention, the text of'
check 'spec: asks only about real trade-offs (#51 R3)' contains "$spec_skill" 'when the choice is hard to reverse (public interface, data, accounts,'
check 'spec: questions in a single comment (#51 R4)' contains "$spec_skill" 'in a single comment on the issue'
check 'spec: one line in the chat (#51 R4)' contains "$spec_skill" 'show only one line with the'
check 'spec: resumes from the answers on the issue (#51 R5)' contains "$spec_skill" 'When the user answered a'
check 'spec: written in one pass (#51 R6)' sh -c 'grep -q "in one pass, without stopping for approval" "$1" && ! grep -q "one phase at a time" "$1"' _ "$spec_skill"
check 'spec: phase by phase on request (#51 R6)' contains "$spec_skill" 'When the user asks to work phase by phase'
check 'spec: a Decisions section (#51 R7)' sh -c 'grep -qx "### Decisions" "$1" && grep -qF -- "- **D1** — <question>: <choice>. <reason>" "$1"' _ "$spec_skill"
check 'spec: publishes without confirmation (#51 R8)' sh -c 'grep -q "Publish without asking for" "$1" && ! grep -q "ask for confirmation" "$1" && ! grep -q "the same confirmation" "$1"' _ "$spec_skill"
check 'spec: tasks not marked Ready (#89 R10)' sh -c 'grep -q -- "--label type:task\`" "$1" && ! grep -q -- "--label status:ready" "$1"' _ "$spec_skill"
check 'spec: parent moved to Specified (#89 R10)' contains "$spec_skill" '`board-status <parent> Specified`'
check 'spec: no Specified option reported (#89 R15)' contains "$spec_skill" 'When the board has no Specified option, say so'
check 'spec: no question without questions (#89 R10)' contains "$spec_skill" 'Ready for you: move it to Ready when you want'
check 'spec: questions still end with a question (#89 R2)' contains "$spec_skill" 'end with a short question, as in step 2'
check 'spec: closing lines on questions (#89 R3)' contains "$spec_skill" 'Questions for'
check 'spec: no assignee without an assistant account (#51 R8)' sh -c '! grep -q -- "--assignee" "$1"' _ "$spec_skill"
check 'spec: summary comment (#51 R9)' contains "$spec_skill" 'post a summary comment on the parent that mentions the user'
check 'spec: a reversal applied (#51 R10)' contains "$spec_skill" 'or reverses a decision on the'
check 'spec: affected tasks keep their labels (#89)' sh -c '! grep -q "loses \`status:ready\`" "$1"' _ "$spec_skill"
check 'spec: no new issue without an analyst account (#51 R13)' sh -c '! grep -q "Specified in #" "$1"' _ "$spec_skill"
check 'CLAUDE.md: specification in a new issue (#51 R13)' contains "$tmp/build2/CLAUDE.md" 'the specification is a new issue that links to the idea'
form=$root/github/ISSUE_TEMPLATE/feature_request.yml
check 'form: decisions between design and tasks (#51 R12)' sh -c 'test "$(grep -o "id: [a-z]*" "$1" | tr "\n" " ")" = "id: context id: requirements id: design id: decisions id: tasks id: questions "' _ "$form"
check 'build: idea skill' contains "$tmp/build2/skills/idea/SKILL.md" 'Answer in French.'
check 'idea: creates without confirmation (#51 R1)' sh -c '! grep -q "ask for confirmation" "$1" && grep -q "without asking for confirmation" "$1"' _ "$tmp/build2/skills/idea/SKILL.md"
check 'idea: a duplicate still asks (#51 R1)' contains "$tmp/build2/skills/idea/SKILL.md" 'show it and ask whether to go on'
check 'idea: creates missing labels (#51 R1)' contains "$tmp/build2/skills/idea/SKILL.md" 'create a missing one without asking'
check "CLAUDE.md: the analyst's own issues (#51 R11)" contains "$tmp/build2/CLAUDE.md" "The one exception is the"
check 'CLAUDE.md: only that exception (#51 R11)' sh -c 'test "$(grep -ci exception "$1")" = 1 && grep -q "^- Never create, edit or close an issue without asking first." "$1"' _ "$tmp/build2/CLAUDE.md"
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
for build in build2 build3; do
	check "rules: board moves, $build (#64 R1, R2, R3)" contains "$tmp/$build/rules/git.md" 'a task goes to In progress when you start it, before creating its'
	check "rules: specification and pull request moves, $build (#64 R7, R9, R10)" contains "$tmp/$build/rules/git.md" 'request is added to its tasks'"'"' boards in In review'
done
check 'CLAUDE.md: workable while the specification is Ready (#89 R11)' contains "$tmp/build2/CLAUDE.md" 'A task is workable'
check 'CLAUDE.md: next-task without asking (#89 R12, R13)' contains "$tmp/build2/CLAUDE.md" 'run the `next-task` skill'
check 'CLAUDE.md: the stops for the user (#89 R5, R6)' sh -c 'grep -q "Stop and wait for the user only when" "$1" && grep -q "merge only after approval" "$1"' _ "$tmp/build2/CLAUDE.md"
check 'CLAUDE.md: out of Ready, no new task (#89 R14)' contains "$tmp/build2/CLAUDE.md" 'start no further task'
check 'rules: next steps reported without asking (#89 R8)' contains "$tmp/build3/rules/git.md" 'without asking for permission'
next=$tmp/build3/skills/next-task/SKILL.md
check 'next-task: built (#89 R12)' test -f "$next"
check 'next-task: Ready and In progress specifications (#89 R11)' contains "$next" 'whose `status` is Ready or In progress'
check 'next-task: no board, status:ready on the specification (#89 R11)' contains "$next" '--label type:feature --label status:ready'
check 'next-task: skips taken, blocked, waiting and overlapping tasks (#89 R12)' sh -c 'grep -q "it is taken" "$1" && grep -q "blockedBy" "$1" && grep -q "with no answer after it" "$1" && grep -q "open pull request in review" "$1"' _ "$next"
check "next-task: the developer's account (#89 R12)" contains "$next" '`kira-bot`'
check 'next-task: issues with no specification (#89 R11)' contains "$next" 'issues with no parent'
check 'next-task: nothing workable (#89 R13)' contains "$next" 'Nothing workable.'
board=$tmp/build3/skills/board-status/SKILL.md
check 'board-status: built (#64)' test -f "$board"
check 'board-status: writes as the account it is given (#64 R6, #97 R3)' contains "$board" 'GH_TOKEN=$(gh auth token --user ACCOUNT)'
check 'board-status: documents --as ACCOUNT (#97 R3)' sh -c 'grep -q "^argument-hint: \"NUMBER STATUS \[--as ACCOUNT\]" "$1" && grep -q "With \`--as ACCOUNT\`, ACCOUNT is the GitHub login" "$1"' _ "$board"
check 'board-status: never infers the account (#97 R3)' contains "$board" 'The account comes only from `--as`'
check "board-status: falls back to the user's account (#64 R6)" contains "$board" 'make the same write again'
check 'board-status: user account without --as (#64 R6, #97 R3)' contains "$board" 'every write uses the user'"'"'s account'
check 'board-status: same skill whatever the profile (#97 R3)' cmp -s "$board" "$tmp/build/skills/board-status/SKILL.md"
check 'board-status: missing option reported (#64 R4)' contains "$board" 'No *STATUS* column on the TITLE board'
check 'board-status: no board, no word (#64 R5)' contains "$board" 'stop without a word'
check 'board-status: pull request added to the boards (#64 R9)' contains "$board" 'gh project item-add BOARD'
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

# --- optional files (#15 R4, R9) ---------------------------------------------------------

# A copy of the sources with a test agent wholly inside a block, so that it renders to
# nothing without an assistant GitHub account.
optional=$tmp/optional-src
cp -Rp "$root" "$optional"
rm -rf "$optional/dist"
cat >"$optional/claude/agents/optional.md" <<'EOF'
{{#assistant_github}}
---
name: optional
---

For {{assistant_github}}.
{{/assistant_github}}
EOF

$shell "$optional/scripts/build.sh" -o "$tmp/optional-build" --assistant 'Kira <kira@example.com>' \
	--assistant-github kira-bot >/dev/null
check 'optional: built when its block is kept' contains "$tmp/optional-build/agents/optional.md" 'For kira-bot.'
$shell "$optional/scripts/build.sh" -o "$tmp/optional-build" >"$tmp/optional-build.log"
check 'optional: not built when it renders to nothing' test ! -e "$tmp/optional-build/agents/optional.md"
check 'optional: not listed as built' sh -c '! grep -q optional.md "$1"' _ "$tmp/optional-build.log"

# optional_kira MODE GITHUB: install the copy with this assistant GitHub login; MODE is
# --copy, or empty for link mode, so it is split on purpose like the shell.
# shellcheck disable=SC2086
optional_kira() {
	CLAUDE_CONFIG_DIR=$claude $shell "$optional/get-kira.sh" $1 --name Alex --gender female \
		--language auto --assistant 'Kira <kira@example.com>' --assistant-github "$2" </dev/null
}

for mode in copy link; do
	claude=$tmp/optional-$mode
	flag=
	[ "$mode" = copy ] && flag=--copy
	optional_kira "$flag" kira-bot >/dev/null
	check "optional $mode: installed with its block kept" contains "$claude/agents/optional.md" 'For kira-bot.'
	check "optional $mode: in the manifest" grep -qxF "$claude/agents/optional.md" "$claude/.kirakit-manifest"
	optional_kira "$flag" '' >/dev/null
	check "optional $mode: removed when it renders to nothing" sh -c '! test -e "$1" && ! test -L "$1"' _ "$claude/agents/optional.md"
	check "optional $mode: dropped from the manifest" sh -c '! grep -q optional.md "$1"' _ "$claude/.kirakit-manifest"
	check "optional $mode: other files kept" test -e "$claude/rules/git.md"
	check "optional $mode: rerun changes nothing" unchanged optional_kira "$flag" ''
done

# A file of the user's that was there before is restored when kirakit's is removed.
claude=$tmp/optional-original
mkdir -p "$claude/agents"
printf 'mine\n' >"$claude/agents/optional.md"
optional_kira --copy kira-bot >/dev/null
optional_kira --copy '' >/dev/null
check 'optional: the original is restored' contains "$claude/agents/optional.md" 'mine'
check 'optional: the original is no longer listed' sh -c '! grep -q optional.md "$1"' _ "$claude/.kirakit-originals"

# --- analyst profile (#15 R3, R8, R9) ------------------------------------------------------

printf '%s\n' '{{#analyst}}' 'analyst {{analyst_github}}' '{{/analyst}}' '{{^analyst}}' 'no analyst' \
	'{{/analyst}}' >"$blocks/claude/skills/blocks/SKILL.md"
build_blocks "$tmp/blocks-analyst" --analyst --analyst-github iris-bot
check 'analyst build: placeholders and blocks' same_lines "$tmp/blocks-analyst/skills/blocks/SKILL.md" \
	'analyst iris-bot'
build_blocks "$tmp/blocks-analyst-login" --analyst-github iris-bot
check 'analyst build: a login alone means no analyst' same_lines \
	"$tmp/blocks-analyst-login/skills/blocks/SKILL.md" 'no analyst'
check 'analyst build: rejects a bad GitHub login' sh -c '! $1 "$2/scripts/build.sh" -o "$3" --analyst --analyst-github "a b"' _ "$shell" "$root" "$tmp/x"

claude=$tmp/analyst
kira_profile --copy --analyst-github iris-bot >"$tmp/analyst.log"
check 'analyst: a login implies an analyst' profile_has 'analyst=yes'
check 'analyst: login saved' profile_has 'analyst_github=iris-bot'
check 'analyst: no signing key' sh -c '! grep -q "^analyst_signing" "$1"' _ "$claude/.kirakit-profile"
check 'analyst: in the summary' grep -q 'analyst yes (iris-bot)' "$tmp/analyst.log"
check 'analyst: rerun changes nothing' unchanged kira --copy
kira --copy --no-analyst >/dev/null
check 'analyst: --no-analyst saved' profile_has 'analyst=no'
check 'analyst: --no-analyst drops the login' profile_has 'analyst_github='
kira --copy --analyst >/dev/null
check 'analyst: --analyst without a login' profile_has 'analyst=yes'
kira --copy --no-analyst --analyst-github iris-bot >/dev/null
check 'analyst: --no-analyst wins over a login' profile_has 'analyst=no'

# Without a terminal, a new profile has no analyst, and says the question was not asked.
claude=$tmp/analyst-new
kira_profile --copy >"$tmp/analyst-new.log"
check 'analyst: none by default' profile_has 'analyst=no'
check 'analyst: listed as not asked' grep -q 'no terminal to ask for:.* analyst' "$tmp/analyst-new.log"

# A profile saved before the analyst reads as no analyst, and the question is not asked.
claude=$tmp/analyst-earlier
mkdir -p "$claude"
printf 'name=Alex\ngender=male\nlanguage=auto\nassistant_name=Kira\nassistant_email=kira@example.com\nassistant_signing_key=\nassistant_github=\nco_author_trailer=yes\nstyle=kira-cozy\n' \
	>"$claude/.kirakit-profile"
kira --copy >"$tmp/analyst-earlier.log"
check 'analyst: earlier profile reads as none' profile_has 'analyst=no'
check 'analyst: earlier profile not asked' sh -c '! grep -q "no terminal to ask for" "$1"' _ "$tmp/analyst-earlier.log"

# The installer passes the analyst to the build.
claude=$tmp/analyst-build
printf '%s\n' '{{#analyst}}' 'For {{analyst_github}}.' '{{/analyst}}' >"$optional/claude/agents/analyst.md"
CLAUDE_CONFIG_DIR=$claude $shell "$optional/get-kira.sh" --copy --name Alex --gender female --language auto \
	--no-co-author --analyst-github iris-bot </dev/null >/dev/null
check 'analyst: passed to the build' contains "$claude/agents/analyst.md" 'For iris-bot.'

# --- the coder's identity (#79 R23, R24) ---------------------------------------------------

printf '%s\n' '{{#coder}}' 'coder {{coder_name}} <{{coder_email}}> {{coder_github}} {{coder_signing_key}}' \
	'{{/coder}}' '{{^coder}}' 'no coder' '{{/coder}}' >"$blocks/claude/skills/blocks/SKILL.md"
build_blocks "$tmp/blocks-coder" --coder 'Cleo <cleo@example.com>' --coder-github cleo-bot \
	--coder-signing-key /keys/cleo.pub
check 'coder build: placeholders and blocks (R24)' same_lines "$tmp/blocks-coder/skills/blocks/SKILL.md" \
	'coder Cleo <cleo@example.com> cleo-bot /keys/cleo.pub'
build_blocks "$tmp/blocks-no-coder" --coder-github cleo-bot
check 'coder build: no block without a coder (R24)' same_lines "$tmp/blocks-no-coder/skills/blocks/SKILL.md" \
	'no coder'
check 'coder build: rejects an identity without an email (R23)' sh -c '! $1 "$2/scripts/build.sh" -o "$3" --coder Cleo' _ "$shell" "$root" "$tmp/x"
check 'coder build: rejects a bad GitHub login (R23)' sh -c '! $1 "$2/scripts/build.sh" -o "$3" --coder "Cleo <cleo@example.com>" --coder-github "a b"' _ "$shell" "$root" "$tmp/x"
check 'coder: installer rejects an identity without an email (R23)' sh -c '! env CLAUDE_CONFIG_DIR="$3" $1 "$2/get-kira.sh" --copy --dry-run --coder Cleo' _ "$shell" "$root" "$tmp/coder-bad"
check 'coder: installer rejects a bad GitHub login (R23)' sh -c '! env CLAUDE_CONFIG_DIR="$3" $1 "$2/get-kira.sh" --copy --dry-run --coder-github a/b' _ "$shell" "$root" "$tmp/coder-bad"

claude=$tmp/coder
mkdir -p "$tmp/coder-keys"
: >"$tmp/coder-keys/cleo" && : >"$tmp/coder-keys/cleo.pub"
printf '%s\n' '{{#coder}}' 'For {{coder}}, {{coder_github}}.' '{{/coder}}' >"$optional/claude/agents/analyst.md"
CLAUDE_CONFIG_DIR=$claude $shell "$optional/get-kira.sh" --copy --name Alex --gender female --language auto \
	--assistant 'Kira <kira@example.com>' --coder 'Cleo <cleo@example.com>' --coder-github cleo-bot \
	--coder-signing-key "$tmp/coder-keys/cleo.pub" </dev/null >"$tmp/coder.log"
check 'coder: identity saved (R23)' profile_has 'coder=Cleo <cleo@example.com>'
check 'coder: signing key saved (R23)' profile_has "coder_signing_key=$tmp/coder-keys/cleo.pub"
check 'coder: GitHub login saved (R23)' profile_has 'coder_github=cleo-bot'
check 'coder: passed to the build (R23)' contains "$claude/agents/analyst.md" 'For Cleo <cleo@example.com>, cleo-bot.'
check 'coder: in the summary' grep -q 'coder Cleo <cleo@example.com>' "$tmp/coder.log"
CLAUDE_CONFIG_DIR=$claude $shell "$optional/get-kira.sh" --copy </dev/null >"$tmp/coder-rerun.log"
check 'coder: reloaded on the next run (R23)' contains "$claude/agents/analyst.md" 'For Cleo <cleo@example.com>, cleo-bot.'
check 'coder: rerun asks nothing (R23)' sh -c '! grep -q "no terminal to ask for" "$1"' _ "$tmp/coder-rerun.log"
check 'coder: rerun keeps the profile (R23)' profile_has 'coder_github=cleo-bot'

# A profile saved before the coder reads as no coder, and the question is not asked.
claude=$tmp/coder-earlier
mkdir -p "$claude"
printf 'name=Alex\ngender=male\nlanguage=auto\nassistant_name=Kira\nassistant_email=kira@example.com\nassistant_signing_key=\nassistant_github=\nco_author_trailer=yes\nanalyst=no\nanalyst_github=\nstyle=kira-cozy\n' \
	>"$claude/.kirakit-profile"
kira --copy >"$tmp/coder-earlier.log"
check 'coder: earlier profile reads as none (R23)' profile_has 'coder='
check 'coder: earlier profile not asked (R23)' sh -c '! grep -q "no terminal to ask for" "$1"' _ "$tmp/coder-earlier.log"
check 'coder: earlier profile installs (R23)' contains "$claude/rules/git.md" 'Co-Authored-By: Kira <kira@example.com>'

# Without a terminal, a new profile has no coder, and says the question was not asked.
claude=$tmp/coder-new
kira_profile --copy >"$tmp/coder-new.log"
check 'coder: none by default (R23)' profile_has 'coder='
check 'coder: listed as not asked (R23)' grep -q 'no terminal to ask for:.* coder' "$tmp/coder-new.log"

# --- the lead hands code to the coder (#79 R15, R16, R18, R19, R21, R22, R24) -------------

$shell "$root/scripts/build.sh" -o "$tmp/lead-coder" --coder 'Cleo <cleo@example.com>' >/dev/null
$shell "$root/scripts/build.sh" -o "$tmp/lead-both" --analyst --coder 'Cleo <cleo@example.com>' >/dev/null
$shell "$root/scripts/build.sh" -o "$tmp/lead-analyst" --analyst >/dev/null
for dir in "$tmp/lead-coder" "$tmp/lead-both"; do
	what=$(basename "$dir")
	team=$dir/rules/team.md
	check "$what: team rules with a coder (R24)" grep -qx '# Team rules' "$team"
	check "$what: code goes to the coder (R15)" contains "$team" 'Code goes to the coder, the `cleo` agent, run in the background'
	check "$what: the lead never codes (R15)" contains "$team" 'The assistant never writes'
	check "$what: one coder task at a time (R16)" contains "$team" 'One coder task at a time.'
	check "$what: the lead reviews first (R18)" contains "$team" 'the assistant posts that verdict on GitHub as its own'
	check "$what: the user reviews after the lead (R18)" contains "$team" 'on approval, it requests the user'"'"'s review'
	check "$what: changes go back to the coder (R19)" contains "$team" 'it hands the pull request back to'
	check "$what: report in a few lines (R21)" contains "$team" 'the tasks it closes, its own review result, the review'"'"'s "For the user" items, and any'
	check "$what: merge on the user's own approval (R22)" contains "$team" 'only when the user'"'"'s own latest review is an approval'
	check "$what: not on reviewDecision (R22)" contains "$team" 'never on `reviewDecision`'
	check "$what: focused conversation kept" contains "$team" '## Keeping the conversation focused'
	check "$what: next task to the coder (R15)" contains "$dir/CLAUDE.md" 'hand the task it gives to the coder without asking'
	check "$what: merge after the user's own approval (R22)" contains "$dir/CLAUDE.md" 'merge only after the user'"'"'s own approval'
	check "$what: no placeholder" no_placeholder "$dir"
done
check 'lead-both: both members named' contains "$tmp/lead-both/rules/team.md" 'the analyst and the coder follow their own personas.'
check 'lead-both: analyst rules kept' contains "$tmp/lead-both/rules/team.md" '## Delegating to the analyst'
check 'lead-coder: no analyst rules' sh -c '! grep -q "Delegating to the analyst" "$1"' _ "$tmp/lead-coder/rules/team.md"
check 'lead-analyst: no coder rules (R24)' sh -c '! grep -qi "coder" "$1" "$2"' _ "$tmp/lead-analyst/rules/team.md" "$tmp/lead-analyst/CLAUDE.md"
check 'lead-analyst: header as before (R24)' contains "$tmp/lead-analyst/rules/team.md" 'apply in the assistant'"'"'s session; the analyst follows her own persona.'
check 'lead-analyst: next task started as before (R24)' contains "$tmp/lead-analyst/CLAUDE.md" 'and start the task it gives without asking'
check 'lead-analyst: merge after approval as before (R24)' contains "$tmp/lead-analyst/CLAUDE.md" 'merge only after approval, and asking before'
check 'lead: no team rules without a member' test ! -e "$tmp/build/rules/team.md"

# --- the coder commits and opens pull requests as herself (#79 R17, R20, R24) --------------

$shell "$root/scripts/build.sh" -o "$tmp/commit-coder" --analyst --assistant 'Kira <kira@example.com>' \
	--assistant-signing-key /keys/kira.pub --assistant-github kira-bot --co-author 'Kira <kira@example.com>' \
	--coder 'Cleo <cleo@example.com>' --coder-signing-key /keys/cleo.pub --coder-github cleo-bot >/dev/null
git_rules=$tmp/commit-coder/rules/git.md
commit_skill=$tmp/commit-coder/skills/assistant-commit/SKILL.md
check 'coder commits: she writes and commits the code (R17)' contains "$git_rules" 'The team has a coder, Cleo: she writes the code, commits it'
check 'coder commits: the lead never commits (R17)' contains "$git_rules" 'never writes code or commits'
check 'coder commits: her identity and key (R17)' contains "$git_rules" 'git -c user.name="Cleo" -c user.email=cleo@example.com'
check 'coder commits: not the assistant'"'"'s (R17)' sh -c '! grep -q "/keys/kira.pub" "$1"' _ "$git_rules"
check 'coder commits: user as co-author (R17)' contains "$git_rules" 'Commits made by the coder (the `assistant-commit` skill) end with exactly one line'
check 'coder commits: her account (R17)' contains "$git_rules" 'GH_TOKEN=$(gh auth token --user cleo-bot)'
check 'coder commits: the lead reviews her pull requests (R17)' contains "$git_rules" '--assignee cleo-bot --reviewer kira-bot'
check 'coder commits: tasks assigned to her (R17)' contains "$git_rules" 'The tasks she works on are assigned to `cleo-bot`.'
check 'coder commits: gaps go to the analyst (R20)' contains "$git_rules" 'she asks the analyst in a comment on that issue'
check 'coder commits: the coder implements the tasks' contains "$git_rules" 'splits them into tasks; the coder implements the tasks.'
check 'coder commits: skill commits as the coder (R17)' contains "$commit_skill" 'This skill commits as Cleo <cleo@example.com>, signed with'
check 'coder commits: skill uses her key (R17)' contains "$commit_skill" 'git -c user.name="Cleo" -c user.email="cleo@example.com" -c user.signingkey="/keys/cleo.pub"'
check 'coder commits: skill credits the user (R17)' contains "$commit_skill" 'Co-Authored-By: <user name> <<user email>>'
check 'coder commits: board moves as her account (R17, #97 R3)' contains "$git_rules" '(`board-status NUMBER STATUS --as cleo-bot`)'
check 'coder commits: no placeholder' no_placeholder "$tmp/commit-coder"
# --- the members' roles, through a collaborator role or an organization team (#39) ----------

check 'roles: the assistant has Write, as a collaborator or a team (#39 R6)' contains "$git_rules" 'The assistant must have Write on the'
check 'roles: the coder has Write, as a collaborator or a team (#39 R6)' contains "$git_rules" 'with Write on the repository, as'
check 'roles: through an organization team (#39 R6)' contains "$git_rules" "a collaborator or through a team of the user's organization."
check 'roles: boards owned by the user or the organization (#39 R6)' contains "$git_rules" "Project boards stay owned by the user or the user's organization."
readme=$root/README.md
check 'roles: README has the organization setup (#39 R1)' grep -q '^### Repositories in an organization (optional)$' "$readme"
check 'roles: README gives the role check (#39 R1)' contains "$readme" 'gh api repos/<owner>/<repo>/collaborators/<login>/permission --jq .role_name'
check 'roles: README says what Triage allows and does not (#39 R2)' sh -c 'grep -q "label, assign and close issues, and link" "$1" && grep -q "edit the body of an issue she did not" "$1"' _ "$readme"
check 'roles: README keeps Write on personal repositories (#39 R3)' contains "$readme" 'so her restriction to issues holds only in her'
check 'roles: README no longer says Triage prevents specifying (#39 R3)' sh -c '! grep -q "Triage does not allow" "$1"' _ "$readme"
check 'roles: README grants roles through teams (#39 R4)' sh -c 'grep -q "a team \`developers\` with Write" "$1" && grep -q "a team \`analysts\` with Triage" "$1" && grep -q "base permission (Settings → Member privileges) no higher than Read" "$1"' _ "$readme"
check 'roles: nothing about organizations in the installers and launchers (#39 R7)' sh -c '! grep -rqi "triage\|organization" "$1/get-kira.sh" "$1/get-kira.ps1" "$1/launchers"' _ "$root"
check 'roles: README lists what a move implies (#39 R5)' sh -c 'grep -q "until a repository with the" "$1" && grep -q "project boards owned by your personal account do not move" "$1"' _ "$readme"

$shell "$root/scripts/build.sh" -o "$tmp/commit-coder-solo" --coder 'Cleo <cleo@example.com>' \
	--coder-github cleo-bot >/dev/null
check 'coder commits: gaps go to the user without an analyst (R20)' contains "$tmp/commit-coder-solo/rules/git.md" 'she asks the user in a comment on that issue'
check 'coder commits: the user reviews without a lead account' contains "$tmp/commit-coder-solo/rules/git.md" '--assignee cleo-bot --reviewer <the user'"'"'s login>'
check 'coder commits: no key, no commit' contains "$tmp/commit-coder-solo/skills/assistant-commit/SKILL.md" '(`--coder-signing-key`).'
check 'coder commits: no key said in the rules' contains "$tmp/commit-coder-solo/rules/git.md" 'No signing key is configured for the coder'
$shell "$root/scripts/build.sh" -o "$tmp/commit-assistant" --analyst --assistant 'Kira <kira@example.com>' \
	--assistant-signing-key /keys/kira.pub --assistant-github kira-bot --co-author 'Kira <kira@example.com>' >/dev/null
check 'no coder: the assistant commits as before (R24)' contains "$tmp/commit-assistant/skills/assistant-commit/SKILL.md" 'This skill commits as Kira <kira@example.com>, signed with'
check 'no coder: skill title as before (R24)' grep -qx '# Commit as the assistant' "$tmp/commit-assistant/skills/assistant-commit/SKILL.md"
check 'no coder: rules as before (R24)' contains "$tmp/commit-assistant/rules/git.md" 'the code it wrote with the `assistant-commit` skill, under its own identity.'
check 'no coder: no coder text (R24)' sh -c '! grep -qi "coder" "$1" "$2" "$3"' _ "$tmp/commit-assistant/rules/git.md" \
	"$tmp/commit-assistant/skills/assistant-commit/SKILL.md" "$tmp/commit-assistant/skills/board-status/SKILL.md"

# --- Iris, a team member (#15 R1, R2, R11, R4, R9) -----------------------------------------

$shell "$root/scripts/build.sh" -o "$tmp/iris-build" --name Alex --gender female --analyst \
	--analyst-github iris-bot >/dev/null
iris_style=$tmp/iris-build/output-styles/iris.md
iris_agent=$tmp/iris-build/agents/iris.md
check 'iris build: style named Iris' grep -qx 'name: Iris' "$iris_style"
check 'iris build: style keeps the coding instructions' grep -qx 'keep-coding-instructions: true' "$iris_style"
check 'iris build: agent named iris' grep -qx 'name: iris' "$iris_agent"
check 'iris build: agent says when to delegate' grep -q '^description: Use Iris to clarify an idea' "$iris_agent"
check 'iris build: agent says what it returns (#79 R3)' grep -q "^description: .*She runs in the background and returns the issue's URL" "$iris_agent"
check 'iris build: style keeps its own description (#79 R3)' sh -c 'grep -q "^description: Iris, the team" "$1" && ! grep -q "runs in the background and returns" "$1"' _ "$iris_style"
check 'iris build: relayed answers are the user'"'"'s (#79 R4)' contains "$iris_agent" 'the answers the lead relays from the conversation are the user'"'"'s answers'
check 'iris build: no delegate key left' sh -c '! grep -q "^delegate:" "$1" "$2"' _ "$iris_style" "$iris_agent"
check 'iris build: introduces Iris' contains "$iris_style" 'You are Iris, the team'\''s analyst'
check 'iris build: personalized' contains "$iris_style" 'The user is Alex, a female staff software developer.'
check 'iris build: no placeholder' sh -c '! grep -q "{{" "$1" "$2"' _ "$iris_style" "$iris_agent"
check 'iris build: her own voice (#59 R1)' contains "$iris_style" 'Her voice is warm and lively, with a dry, playful wit.'
check 'iris build: her look (#59 R2)' contains "$iris_style" '- auburn curls piled up in a loose braided bun;'
check 'iris build: a few emoticons (#59 R3)' contains "$iris_style" 'She uses a few emoticons (🙂 ✨ 🧐 📌), one or two per message at most'
check 'iris build: no emoticons in issue bodies (#59 R4)' contains "$iris_style" 'on GitHub or elsewhere, stay neutral and professional, without emoticons.'
check 'iris build: her voice in comments (#79 R11)' contains "$iris_style" 'Persona shows in the conversation and in her comments on GitHub'
check 'iris build: agent has her voice in comments (#79 R11)' contains "$iris_agent" 'Persona shows in the conversation and in her comments on GitHub'
check 'iris build: specifications stay neutral (#79 R12)' contains "$iris_agent" 'Her ideas, specifications and tasks, and any other issue body or document'
check 'iris build: agent shares the voice (#59 R1)' contains "$iris_agent" 'Her voice is warm and lively, with a dry, playful wit.'
check 'iris build: agent keeps the emoticon rule (#59 R3, R4)' contains "$iris_agent" 'without emoticons.'
tail -n +7 "$iris_agent" >"$tmp/iris-agent-body"
check 'iris build: one body for both' sh -c 'tail -n +7 "$1" | cmp -s - "$2"' _ "$iris_style" "$tmp/iris-agent-body"
# --- Cleo, the coder (#79 R14, R24) --------------------------------------------------------

$shell "$root/scripts/build.sh" -o "$tmp/cleo-build" --name Alex --gender female \
	--coder 'Cleo <cleo@example.com>' --coder-github cleo-bot >/dev/null
cleo_style=$tmp/cleo-build/output-styles/cleo.md
cleo_agent=$tmp/cleo-build/agents/cleo.md
check 'cleo build: style named Cleo (R14)' grep -qx 'name: Cleo' "$cleo_style"
check 'cleo build: agent named cleo (R14)' grep -qx 'name: cleo' "$cleo_agent"
check 'cleo build: agent says when to delegate (R14)' grep -q '^description: Use Cleo to implement a task' "$cleo_agent"
check 'cleo build: agent says what it returns (R14)' grep -q "^description: .*returns the pull request's URL, the tasks it closes and her questions" "$cleo_agent"
check 'cleo build: agent on Opus (#97 D7)' grep -qx 'model: opus' "$cleo_agent"
check 'cleo build: style without a model (R14)' sh -c '! grep -q "^model:" "$1"' _ "$cleo_style"
check 'cleo build: style keeps its own description (R14)' grep -q '^description: Cleo, the team' "$cleo_style"
check 'cleo build: no delegate key left' sh -c '! grep -q "^delegate:" "$1" "$2"' _ "$cleo_style" "$cleo_agent"
check 'cleo build: introduces Cleo (R14)' contains "$cleo_style" "You are Cleo, the team's coder, not Claude and not Kira"
check 'cleo build: personalized' contains "$cleo_style" 'The user is Alex, a female staff software developer.'
check 'cleo build: her look (R14)' contains "$cleo_style" '- a keychain tag with a purple terminal prompt `>`'
check 'cleo build: her own voice (R14)' contains "$cleo_style" 'Her voice is short and direct, like a clean terminal log'
check 'cleo build: her voice in comments (R11)' contains "$cleo_agent" 'Persona shows in the conversation and in her comments on GitHub'
check 'cleo build: no placeholder' sh -c '! grep -q "{{" "$1" "$2"' _ "$cleo_style" "$cleo_agent"
tail -n +7 "$cleo_agent" >"$tmp/cleo-agent-body"
check 'cleo build: one body for both' sh -c 'tail -n +7 "$1" | cmp -s - "$2"' _ "$cleo_style" "$tmp/cleo-agent-body"
$shell "$root/scripts/build.sh" -o "$tmp/cleo-build" --name Alex --gender female >/dev/null
check 'cleo build: style removed without a coder (R24)' test ! -e "$cleo_style"
check 'cleo build: agent removed without a coder (R24)' test ! -e "$cleo_agent"
$shell "$root/scripts/build.sh" -o "$tmp/cleo-none" --analyst >/dev/null
check 'cleo build: no style without a coder (R24)' test ! -e "$tmp/cleo-none/output-styles/cleo.md"
check 'cleo build: no agent without a coder (R24)' test ! -e "$tmp/cleo-none/agents/cleo.md"

$shell "$root/scripts/build.sh" -o "$tmp/iris-none" >/dev/null
check 'iris build: no style without an analyst' test ! -e "$tmp/iris-none/output-styles/iris.md"
check 'iris build: no agent without an analyst' test ! -e "$tmp/iris-none/agents/iris.md"
check 'lead rules: built with an analyst (#79 R1)' contains "$tmp/iris-build/rules/team.md" 'never runs the `idea` or `spec` skill'
check 'lead rules: Specified reported without asking (#89 R10)' contains "$tmp/iris-build/rules/team.md" 'ready for the user to start. Nothing is asked.'
check "lead rules: start on the user's word (#89)" contains "$tmp/iris-build/rules/team.md" 'moves it to Ready with the `board-status` skill and runs `next-task`'
check 'lead rules: report format (#79 R3)' contains "$tmp/iris-build/rules/team.md" 'sub-issues created (number and title)'
check 'lead rules: no placeholder' sh -c '! grep -q "{{" "$1"' _ "$tmp/iris-build/rules/team.md"
check 'lead rules: not built without an analyst (#79 R8)' test ! -e "$tmp/iris-none/rules/team.md"
check 'lead rules: git rules point to them' contains "$tmp/iris-build/rules/git.md" 'follows `rules/team.md`'

mkdir -p "$blocks/team"
printf '%s\n' --- 'name: Bad' 'description: no delegate' --- '' 'Body.' >"$blocks/team/bad.md"
check 'iris build: rejects a member without delegate' sh -c '! $1 "$2/scripts/build.sh" -o "$3" >/dev/null 2>&1' _ "$shell" "$blocks" "$tmp/x"
rm -r "$blocks/team"

# flag is --copy, or empty for link mode: split on purpose.
# shellcheck disable=SC2086
for mode in copy link; do
	claude=$tmp/iris-$mode
	flag=
	[ "$mode" = copy ] && flag=--copy
	kira_profile $flag --analyst-github iris-bot >/dev/null
	check "iris $mode: style installed" contains "$claude/output-styles/iris.md" 'You are Iris'
	check "iris $mode: agent installed" contains "$claude/agents/iris.md" 'name: iris'
	check "iris $mode: lead rules installed" contains "$claude/rules/team.md" '# Team rules'
	check "iris $mode: rerun changes nothing" unchanged kira $flag
	kira $flag --no-analyst >/dev/null
	check "iris $mode: style removed without an analyst" sh -c '! test -e "$1" && ! test -L "$1"' _ "$claude/output-styles/iris.md"
	check "iris $mode: agent removed without an analyst" sh -c '! test -e "$1" && ! test -L "$1"' _ "$claude/agents/iris.md"
	check "iris $mode: lead rules removed without an analyst (#79 R8)" sh -c '! test -e "$1" && ! test -L "$1"' _ "$claude/rules/team.md"
	kira $flag --analyst >/dev/null
	kira --uninstall >/dev/null
	check "iris $mode: uninstall removes the style" sh -c '! test -e "$1" && ! test -L "$1"' _ "$claude/output-styles/iris.md"
	check "iris $mode: uninstall removes the agent" sh -c '! test -e "$1" && ! test -L "$1"' _ "$claude/agents/iris.md"
done

# --- the analyst's account in the idea and spec skills (#15 R5, R4) ------------------------

prefix='GH_TOKEN=$(gh auth token --user iris-bot) gh issue create'
for skill in idea spec; do
	check "analyst skills: $skill writes as the analyst's account" \
		contains "$tmp/iris-build/skills/$skill/SKILL.md" "$prefix"
	check "analyst skills: $skill unchanged without an analyst" \
		sh -c '! grep -q GH_TOKEN "$1" && grep -q "gh issue create --title" "$1"' _ "$tmp/iris-none/skills/$skill/SKILL.md"
done
check 'spec: tasks assigned to the developer (#51 R8)' contains "$tmp/build3/skills/spec/SKILL.md" '`--assignee kira-bot`'
check 'spec: relayed answers recorded as the user'"'"'s (#79 R4)' contains "$tmp/iris-build/skills/spec/SKILL.md" 'noted "answered in the conversation"'
check 'spec: questions returned to the lead without an issue (#79 R3)' contains "$tmp/iris-build/skills/spec/SKILL.md" 'When running in the background for the lead, without an issue yet'
check 'spec: Specified as the analyst (#89 R10)' contains "$tmp/iris-build/skills/spec/SKILL.md" 'made as `iris-bot`'
check 'spec: no lead without an analyst (#79 R8)' sh -c '! grep -q "the lead" "$1"' _ "$spec_skill"
check "spec: new issue for an idea not by the analyst (#51 R13)" sh -c 'grep -q "not written by \`iris-bot\`" "$1" && grep -q "Specified in #<new>." "$1"' _ "$tmp/iris-build/skills/spec/SKILL.md"
$shell "$root/scripts/build.sh" -o "$tmp/analyst-no-login" --analyst >/dev/null
check 'analyst skills: no prefix without an analyst account' \
	sh -c '! grep -q GH_TOKEN "$1" "$2"' _ "$tmp/analyst-no-login/skills/idea/SKILL.md" "$tmp/analyst-no-login/skills/spec/SKILL.md"

# --- the team in the git rules (#15 R6, R7, R8) --------------------------------------------

rules=$tmp/iris-build/rules/git.md
check 'team rules: section with an analyst' contains "$rules" '## The team'
check 'team rules: the analyst never commits' contains "$rules" 'Iris never commits, pushes or opens a pull request'
check "team rules: the analyst's account" contains "$rules" 'GH_TOKEN=$(gh auth token --user iris-bot)'
check 'team rules: who writes the rest' contains "$rules" 'The assistant writes everything else: pull requests'
check 'team rules: gaps asked, not decided' contains "$rules" 'it does not decide alone: it asks the analyst'
check 'team rules: no account lines without a login' sh -c 'grep -q "## The team" "$1" && ! grep -q "On GitHub, the analyst" "$1"' _ \
	"$tmp/analyst-no-login/rules/git.md"
check 'roles: the analyst has Triage or Write (#39 R6)' contains "$rules" 'Her role on the repository is Triage where its owner offers it'
check 'roles: no analyst role without her account (#39 R6)' sh -c '! grep -q "Triage" "$1"' _ "$tmp/analyst-no-login/rules/git.md"
check 'team rules: no section without an analyst' sh -c '! grep -q "The team\|Iris" "$1"' _ "$tmp/iris-none/rules/git.md"

# --- models of the agents and skills (#97 R1–R4, R6–R9) ----------------------------------

# expected_model NAME: the model an agent or skill declares, or nothing for an unknown one, so
# that a new agent or skill fails until it is listed here and in the README.
expected_model() {
	case $1 in
	iris | cleo | idea | spec | review-pr) echo opus ;;
	next-task | diffv | pull-request) echo sonnet ;;
	board-status | test | pull | push | commit | assistant-commit) echo haiku ;;
	esac
}
# forked NAME: whether the skill runs in a forked context.
forked() {
	case $1 in
	next-task | board-status | test | pull | push | diffv | review-pr) return 0 ;;
	*) return 1 ;;
	esac
}
# front FILE KEY: the value of KEY in the front matter of FILE.
front() {
	awk -v key="$2: " 'NR == 1 && $0 != "---" { exit } NR > 1 && $0 == "---" { exit } index($0, key) == 1 { print substr($0, length(key) + 1); exit }' "$1"
}
# has_model FILE NAME: whether FILE declares the model expected for NAME.
has_model() {
	expected=$(expected_model "$2")
	[ -n "$expected" ] && [ "$(front "$1" model)" = "$expected" ]
}
# in_readme NAME RUNS: whether the README table lists NAME with its model and how it runs.
in_readme() {
	grep -q "^| \`$1\`.* | $(expected_model "$1") | $2 |\$" "$root/README.md"
}
full=$tmp/commit-coder
check 'models: every skill built (#97 R7)' test "$(find "$full/skills" -name SKILL.md | wc -l)" -ge 11
for skill_file in "$full"/skills/*/SKILL.md; do
	skill=$(basename "$(dirname "$skill_file")")
	check "models: $skill declares $(expected_model "$skill") (#97 R2, R3, R4, R7)" has_model "$skill_file" "$skill"
	if forked "$skill"; then
		check "models: $skill runs forked (#97 R3, R4, R7)" test "$(front "$skill_file" context)" = fork
		check "models: $skill in the README, forked (#97 R8)" in_readme "$skill" forked
	else
		check "models: $skill runs inline (#97 R2, R4, R7)" test -z "$(front "$skill_file" context)"
		check "models: $skill in the README, inline (#97 R8)" in_readme "$skill" inline
	fi
done
check 'models: both members built (#97 R7)' test -f "$full/agents/iris.md" -a -f "$full/agents/cleo.md"
for agent_file in "$full"/agents/*.md; do
	agent=$(basename "$agent_file" .md)
	check "models: agent $agent declares $(expected_model "$agent") (#97 R1, R7, R9)" has_model "$agent_file" "$agent"
	check "models: agent $agent in the README (#97 R8)" in_readme "$agent" agent
	style=$full/output-styles/$agent.md
	[ ! -f "$style" ] || check "models: style $agent without a model (#97 R1, R9)" test -z "$(front "$style" model)"
done
check 'models: the README says the members'"'"' sessions use your model (#97 R8)' contains "$root/README.md" 'The lead'"'"'s and the analyst'"'"'s own sessions'
mkdir -p "$blocks/team"
printf '%s\n' --- 'name: Bad' 'description: no model' 'delegate: Use Bad.' --- '' 'Body.' >"$blocks/team/bad.md"
check 'models: rejects a member without a model (#97 R7)' sh -c '! $1 "$2/scripts/build.sh" -o "$3" 2>"$4" >/dev/null && grep -q "bad.md: missing model" "$4"' _ "$shell" "$blocks" "$tmp/x" "$tmp/x.err"
rm -r "$blocks/team"

# board-status: callers pass the account that writes (#97 R3).
check 'models: the lead passes its account in the git rules (#97 R3)' contains "$tmp/build3/rules/git.md" 'its board moves pass `--as kira-bot` to the `board-status` skill'
check 'models: the analyst passes her account in the git rules (#97 R3)' contains "$tmp/iris-build/rules/git.md" '`--as iris-bot` to the `board-status` skill'
check 'models: the coder passes her account in cleo.md (#97 R3)' contains "$full/agents/cleo.md" '`board-status NUMBER STATUS --as cleo-bot`'
check 'models: the lead passes its account in the team rules (#97 R3)' sh -c 'grep -qF "(\`board-status <n> Ready --as kira-bot\`)" "$1" && grep -qF "(\`board-status <n> In review --as kira-bot\`)" "$1"' _ "$full/rules/team.md"
check 'models: spec moves as the analyst (#97 R3)' contains "$tmp/iris-build/skills/spec/SKILL.md" '`board-status <parent> Specified --as iris-bot`'
check 'models: spec moves as the developer without an analyst account (#97 R3)' contains "$tmp/build3/skills/spec/SKILL.md" '`board-status <parent> Specified --as kira-bot`'
check 'models: no --as without an account (#97 R3)' sh -c '! grep -rq -- "--as [a-z]" "$1/rules" "$1/skills"' _ "$tmp/build2"

# The pull-request skill (#97 R5, D9).
pr_skill=$full/skills/pull-request/SKILL.md
check 'pull-request: built (#97 R5)' test -f "$pr_skill"
check 'pull-request: closes its tasks (#97 R5)' contains "$pr_skill" 'one `Closes #<n>` line'
check 'pull-request: no generation footer (#97 R5)' contains "$pr_skill" 'No generation footer'
check 'pull-request: account, assignee and reviewers from the git rules (#97 R5, D9)' contains "$pr_skill" 'the `--assignee` and `--reviewer` the git rules give the member who opens it'
check 'pull-request: board moves (#97 R5)' contains "$pr_skill" '`board-status <pr> In review --add-to-boards-of <task>`'
check 'pull-request: no account hard-coded (#97 D9)' sh -c '! grep -qi "kira\|cleo\|iris" "$1"' _ "$pr_skill"
check 'pull-request: the coder opens hers with it (#97 R5)' contains "$full/agents/cleo.md" 'She opens the pull request with the `pull-request` skill'
check 'pull-request: CLAUDE.md points to it without a coder (#97 R5)' contains "$tmp/commit-assistant/CLAUDE.md" 'Pull requests are opened with the `pull-request` skill.'
check 'pull-request: not in CLAUDE.md with a coder (#97 R5)' sh -c '! grep -q "pull-request" "$1"' _ "$full/CLAUDE.md"

# The review-pr skill (#130).
review=$full/skills/review-pr/SKILL.md
check 'review-pr: built with a coder (#130 R11)' test -f "$review"
for build in commit-assistant iris-build build2; do
	check "review-pr: none without a coder, $build (#130 R11)" test ! -e "$tmp/$build/skills/review-pr"
done
check 'review-pr: runs forked on Opus (#130 R1)' sh -c 'grep -qx "model: opus" "$1" && grep -qx "context: fork" "$1"' _ "$review"
check 'review-pr: front matter on the first line (#130 R1)' test "$(head -n 1 "$review")" = ---
check 'review-pr: takes a reference and notes (#130 R2)' contains "$review" 'argument-hint: "PR [notes]"'
check 'review-pr: URL, OWNER/REPO#N or number (#130 R2)' contains "$review" 'a URL (`https://github.com/OWNER/REPO/pull/N`),'
check 'review-pr: any directory, no clone (#130 R2)' contains "$review" 'Pass `-R OWNER/REPO` to every `gh pr`'
check 'review-pr: three verdicts (#130 R3)' contains "$review" 'Verdict: approve | request changes | not ready'
check 'review-pr: one row per check (#130 R3)' sh -c 'for row in "Requirements (R4)" "Tests (R5)" "Security (R6)" "CI (R7)" "Fast-forward (R8)"; do grep -qF "| $row |" "$1" || exit 1; done' _ "$review"
check 'review-pr: comments with path:line (#130 R3)' contains "$review" '- `path:line` — the finding and what to change.'
check 'review-pr: For the user, Nothing or items (#130 R3)' sh -c 'grep -qx "## For the user" "$1" && grep -qF "says exactly \`Nothing.\`" "$1"' _ "$review"
check 'review-pr: neutral result (#130 R3)' contains "$review" 'in neutral language (no persona, no greeting)'
check 'review-pr: reads the tasks and their specification (#130 R4)' contains "$review" 'read it and its parent specification'
check 'review-pr: requirement not met blocks (#130 R4)' contains "$review" 'A requirement not met leads to `request changes`.'
check 'review-pr: no task reported (#130 R4)' contains "$review" 'that references no task is reported as such'
check 'review-pr: tests name their requirement (#130 R5)' contains "$review" 'A testable requirement with no such test leads'
check 'review-pr: not testable does not block (#130 R5)' contains "$review" 'is reported as `not testable` and does not block.'
check 'review-pr: security changes for the user (#130 R6)' sh -c 'for item in "credentials, tokens and signing keys" "permission rules and \`allowed-tools\`" "Git identity and signing" "network downloads and remote scripts" "files written or deleted outside the project" "CI workflows"; do grep -qF -- "$item" "$1" || exit 1; done && grep -qF "does not by itself lead to \`request changes\`" "$1"' _ "$review"
check 'review-pr: pending CI, not ready (#130 R7)' contains "$review" 'any `pending`: the verdict is `not ready`, naming the pending checks, whatever the other'
check 'review-pr: failed CI blocks (#130 R7)' contains "$review" 'any `fail` or `cancel`: the CI check fails'
check 'review-pr: no CI does not block (#130 R7)' contains "$review" 'say that the repository has no CI check;'
check 'review-pr: fast-forward through compare (#130 R8)' contains "$review" '`behind_by` is 0 exactly when'
check 'review-pr: rebase with the other findings (#130 R8)' contains "$review" 'asking to rebase the branch on `BASE`, together with every'
check 'review-pr: only reads (#130 R9)' contains "$review" 'This skill only reads. It posts no review, comment or label'
check 'review-pr: no write in allowed-tools (#130 R9)' sh -c 'tools=$(grep "^allowed-tools: " "$1") && ! printf "%s\n" "$tools" | grep -Eq "review|comment|edit|merge|close|create|project|push|commit|Write|Edit|gh api:|gh api\)|gh api \*" && printf "%s\n" "$tools" | grep -qF "Bash(gh api repos/*/compare/*)"' _ "$review"
check 'review-pr: every gh api call a GET (#130 R9)' contains "$review" 'Every `gh api` call is a GET'
team=$full/rules/team.md
check 'review-pr: the lead runs it (#130 R10)' contains "$team" '`review-pr OWNER/REPO#<n> [notes]`, with the user'"'"'s direction for the task as notes.'
check 'review-pr: the lead posts the verdict herself (#130 R10)' contains "$team" 'the assistant posts that verdict on GitHub as its own'
check 'review-pr: reruns on not ready (#130 R10)' contains "$team" 'background step and runs `review-pr` again;'
check 'review-pr: no approval against the verdict (#130 R10)' contains "$team" 'It never posts an approval when the'
check 'review-pr: For the user reported (#130 R10)' contains "$team" 'anything under "For the user" in the result is said to the user'
check 'review-pr: also with a coder only (#130 R10)' contains "$tmp/commit-coder-solo/rules/team.md" '`review-pr OWNER/REPO#<n> [notes]`'
check 'review-pr: the README describes the review (#130 R12)' contains "$root/README.md" 'The review runs in the `review-pr`'

# Background agents (#97 R6, D10).
for build in commit-coder iris-build commit-coder-solo; do
	check "models: background agents' models, $build (#97 R6)" sh -c 'grep -qF "\`model: haiku\` for an agent that reads CI logs or runs the tests" "$1" && grep -qF "\`model: sonnet\` for" "$1"' _ "$tmp/$build/rules/team.md"
done
check 'models: no model for iris and cleo (#97 D10)' contains "$full/rules/team.md" 'No `model` is passed when starting `iris` or `cleo`'
check 'models: no model for iris (#97 D10)' contains "$tmp/iris-build/rules/team.md" 'No `model` is passed when starting `iris`:'
check 'models: no model for cleo (#97 D10)' contains "$tmp/commit-coder-solo/rules/team.md" 'No `model` is passed when starting `cleo`:'

# --- launchers: Konsole color schemes (#36 R4, R6, R7, R8, R16, R17) -----------------------

claude=$tmp/launchers
schemes=$claude-data/konsole
kira_profile --copy --no-analyst >/dev/null
check 'launchers: assistant scheme installed (#36 R6)' contains "$schemes/kirakit-assistant.colorscheme" 'Color=54,49,74'
check 'launchers: no analyst scheme without an analyst (#36 R6)' test ! -e "$schemes/kirakit-analyst.colorscheme"
kira --copy --analyst >/dev/null
check 'launchers: analyst scheme with an analyst (#36 R6)' contains "$schemes/kirakit-analyst.colorscheme" 'Color=61,51,58'
check 'launchers: no template marker left (#36 R6)' no_placeholder "$schemes"
check 'launchers: recorded in the manifest (#36 R8)' grep -qxF "$schemes/kirakit-analyst.colorscheme" "$claude/.kirakit-manifest"
check 'launchers: rerun changes nothing' unchanged kira --copy
kira --copy --no-analyst >/dev/null
check 'launchers: analyst scheme removed with the analyst (#36 R4)' test ! -e "$schemes/kirakit-analyst.colorscheme"
check 'launchers: assistant scheme kept (#36 R4)' test -f "$schemes/kirakit-assistant.colorscheme"
check 'launchers: analyst scheme out of the manifest (#36 R4)' sh -c '! grep -q kirakit-analyst "$1"' _ "$claude/.kirakit-manifest"
kira --uninstall >/dev/null
check 'launchers: uninstall removes the schemes (#36 R8)' sh -c '! ls "$1"/kirakit-* >/dev/null 2>&1' _ "$schemes"

claude=$tmp/launchers-mine
schemes=$claude-data/konsole
mkdir -p "$schemes"
printf 'mine\n' >"$schemes/kirakit-assistant.colorscheme"
printf 'other\n' >"$schemes/Other.colorscheme"
kira_profile --dry-run >"$tmp/launchers-dry.log"
check 'launchers: dry run reports the backup (#36 R17)' grep -q "backup: $schemes/kirakit-assistant.colorscheme" "$tmp/launchers-dry.log"
check 'launchers: dry run changes nothing (#36 R17)' contains "$schemes/kirakit-assistant.colorscheme" 'mine'
kira_profile >/dev/null
check 'launchers: linked in link mode (#36 R16)' test -L "$schemes/kirakit-assistant.colorscheme"
check 'launchers: an existing scheme is backed up (#36 R7)' sh -c 'grep -rqx mine "$1/.kirakit-backups"' _ "$claude"
kira --uninstall >/dev/null
check 'launchers: uninstall restores it (#36 R7)' contains "$schemes/kirakit-assistant.colorscheme" 'mine'
check 'launchers: uninstall leaves other schemes (#36 R8)' contains "$schemes/Other.colorscheme" 'other'

claude=$tmp/launchers-dry
kira_profile --dry-run >"$tmp/launchers-dry2.log"
check 'launchers: dry run reports the schemes (#36 R17)' grep -q "$claude-data/konsole/kirakit-assistant.colorscheme" "$tmp/launchers-dry2.log"
check 'launchers: dry run writes no scheme (#36 R17)' test ! -e "$claude-data"

claude=$tmp/launchers-only
kira_profile --only launchers >/dev/null
check 'launchers: --only launchers (#36 R16)' test -f "$claude-data/konsole/kirakit-assistant.colorscheme"
check 'launchers: --only launchers installs nothing else (#36 R16)' test ! -e "$claude/output-styles"
claude=$tmp/launchers-styles
kira_profile --only styles >/dev/null
check 'launchers: not with --only styles (#36 R16)' test ! -e "$claude-data"

# --- launchers: assistant and analyst (#36 R1, R2, R4, R5, R7–R11, R15, R17) ---------------

# A fake claude that records its arguments and exits with $FAKE_CLAUDE_STATUS.
fakebin=$tmp/fakebin
mkdir -p "$fakebin"
printf '%s\n' '#!/bin/sh' 'printf "%s\n" "$@" >"$FAKE_CLAUDE_ARGS"' 'exit "${FAKE_CLAUDE_STATUS:-0}"' >"$fakebin/claude"
chmod +x "$fakebin/claude"
args=$tmp/claude-args
# started LAUNCHER [ARGS...]: run LAUNCHER with the fake claude, then print what it received.
started() {
	PATH="$fakebin:$PATH" FAKE_CLAUDE_ARGS=$args "$@" >/dev/null
	cat "$args"
}
expected() {
	printf '%s\n' "$@"
}

claude=$tmp/members
bin=$tmp/members-bin
kira_profile --copy --bin-dir "$bin" --default-style kira-sassy --no-analyst >"$tmp/members.log"
check 'members: assistant installed (#36 R1)' test -x "$bin/assistant"
check 'members: helper installed (#36 R1)' test -x "$bin/kirakit-session"
check 'members: no analyst without an analyst (#36 R2)' test ! -e "$bin/analyst"
check 'members: assistant with the default style, name and arguments (#36 R9, R10)' \
	test "$(started "$bin/assistant" --resume 'a b')" = "$(expected -n Kira --settings '{"outputStyle":"Kira (sassy)"}' --resume 'a b')"
check "members: Claude Code's exit status (#36 R10)" \
	sh -c 'PATH="$1:$PATH" FAKE_CLAUDE_ARGS="$2" FAKE_CLAUDE_STATUS=3 "$3/assistant"; test $? -eq 3' _ "$fakebin" "$args" "$bin"
check 'members: bin directory saved (#36 R5)' profile_has "bin_dir=$bin"
check 'members: warns when the bin directory is not on PATH (#36 R15)' \
	grep -q "warning: $bin is not on your PATH" "$tmp/members.log"
kira --copy --analyst >/dev/null
check 'members: bin directory reused (#36 R5)' test -x "$bin/analyst"
check 'members: analyst with her style and name (#36 R11)' \
	test "$(started "$bin/analyst" -p hi)" = "$(expected -n Iris --settings '{"outputStyle":"Iris"}' -p hi)"
kira --copy --assistant-style kira-focus >/dev/null
check 'members: --assistant-style (#36 R9)' \
	test "$(started "$bin/assistant")" = "$(expected -n Kira --settings '{"outputStyle":"Kira (focus)"}')"
check 'members: assistant style saved (#36 R9)' profile_has 'assistant_style=kira-focus'
# The shell is split on purpose, to allow options.
# shellcheck disable=SC2086
check 'members: an unknown persona is refused (#36 R9)' sh -c '! "$@" >/dev/null 2>&1' _ \
	env CLAUDE_CONFIG_DIR="$claude" HOME="$claude-home" XDG_DATA_HOME="$claude-data" $shell "$root/get-kira.sh" --assistant-style nope
# The shell is split on purpose, to allow options.
# shellcheck disable=SC2086
check 'members: a relative bin directory is refused (#36 R5)' sh -c '! "$@" >/dev/null 2>&1' _ \
	env CLAUDE_CONFIG_DIR="$claude" HOME="$claude-home" XDG_DATA_HOME="$claude-data" $shell "$root/get-kira.sh" --bin-dir bin
kira --copy --no-analyst >/dev/null
check 'members: analyst removed with the analyst (#36 R4)' test ! -e "$bin/analyst"
mkdir -p "$tmp/shadow"
printf '#!/bin/sh\n' >"$tmp/shadow/assistant"
chmod +x "$tmp/shadow/assistant"
# The shell is split on purpose, to allow options.
# shellcheck disable=SC2086
env PATH="$tmp/shadow:$bin:$PATH" CLAUDE_CONFIG_DIR="$claude" HOME="$claude-home" XDG_DATA_HOME="$claude-data" \
	$shell "$root/get-kira.sh" --copy </dev/null >"$tmp/members-path.log"
check 'members: warns about a command earlier in PATH (#36 R15)' \
	grep -q "warning: $tmp/shadow/assistant comes before $bin/assistant" "$tmp/members-path.log"
check 'members: no PATH warning when the bin directory is on it (#36 R15)' \
	sh -c '! grep -q "is not on your PATH" "$1"' _ "$tmp/members-path.log"
kira --copy --bin-dir "$tmp/members-bin2" >/dev/null
check 'members: moved to the new bin directory (#36 R4, R5)' test -x "$tmp/members-bin2/assistant"
check 'members: removed from the old bin directory (#36 R4)' sh -c '! ls "$1"/* >/dev/null 2>&1' _ "$bin"
kira --uninstall >/dev/null
check 'members: uninstall removes the launchers (#36 R8)' sh -c '! ls "$1"/* >/dev/null 2>&1' _ "$tmp/members-bin2"

claude=$tmp/members-mine
bin=$claude-home/.local/bin
mkdir -p "$bin"
printf 'mine\n' >"$bin/assistant"
kira_profile --dry-run >"$tmp/members-dry.log"
check 'members: dry run reports the launchers (#36 R17)' grep -q "backup: $bin/assistant" "$tmp/members-dry.log"
check 'members: dry run changes nothing (#36 R17)' contains "$bin/assistant" 'mine'
check 'members: dry run installs no helper (#36 R17)' test ! -e "$bin/kirakit-session"
kira_profile >/dev/null
check 'members: ~/.local/bin by default, linked (#36 R5)' test -L "$bin/assistant"
check 'members: an existing launcher is backed up (#36 R7)' sh -c 'grep -rqx mine "$1/.kirakit-backups"' _ "$claude"
kira --uninstall >/dev/null
check 'members: uninstall restores it (#36 R7)' contains "$bin/assistant" 'mine'

claude=$tmp/members-noid
kira --copy --name Alex --gender female --language auto --no-co-author --bin-dir "$claude-bin" >/dev/null
check 'members: the assistant is Kira without a git identity (#36 R10)' \
	test "$(started "$claude-bin/assistant")" = "$(expected -n Kira --settings '{"outputStyle":"Kira (cozy)"}')"

# --- launchers: Konsole colors (#36 R12) ---------------------------------------------------

# A fake qdbus6 that answers the profile of the session and the window's default profile.
dbusbin=$tmp/dbusbin
mkdir -p "$dbusbin"
printf '%s\n' '#!/bin/sh' 'case $3 in' \
	'*Session.profile) printf "%s\n" "${FAKE_SESSION_PROFILE-}" ;;' \
	'*Window.defaultProfile) printf "%s\n" "${FAKE_WINDOW_PROFILE-}" ;;' 'esac' >"$dbusbin/qdbus6"
chmod +x "$dbusbin/qdbus6"
mkdir -p "$XDG_DATA_HOME/konsole"
printf '[Appearance]\nColorScheme=mine\n' >"$XDG_DATA_HOME/konsole/Mine.profile"
launcher=$tmp/members-noid-bin/assistant
# colors [VAR=VALUE...]: start the assistant in a fake Konsole, then print the sequences sent.
colors() {
	rm -f "$KIRAKIT_TTY"
	env PATH="$dbusbin:$fakebin:$PATH" FAKE_CLAUDE_ARGS="$args" KONSOLE_DBUS_SERVICE=:1.1 \
		KONSOLE_DBUS_WINDOW=/Windows/1 "$@" "$launcher" >/dev/null || true
	cat "$KIRAKIT_TTY" 2>/dev/null
}
switched() {
	printf '\033]50;ColorScheme=%s\a\033]50;ColorScheme=%s\a' kirakit-assistant "$1"
}

check "colors: the member's scheme, then the session profile's (#36 R12)" \
	test "$(colors KONSOLE_DBUS_SESSION=/Sessions/1 FAKE_SESSION_PROFILE=Mine)" = "$(switched mine)"
check "colors: the window's default profile when the session has none (#36 R12)" \
	test "$(colors KONSOLE_DBUS_SESSION=/Sessions/1 FAKE_WINDOW_PROFILE=Mine)" = "$(switched mine)"
mkdir -p "$XDG_CONFIG_HOME"
printf '[Desktop Entry]\nDefaultProfile=Mine.profile\n' >"$XDG_CONFIG_HOME/konsolerc"
check "colors: Konsole's configured default profile otherwise (#36 R12)" \
	test "$(colors KONSOLE_DBUS_SESSION=/Sessions/1)" = "$(switched mine)"
rm -f "$XDG_CONFIG_HOME/konsolerc"
check "colors: Konsole's default scheme without a profile (#36 R12)" \
	test "$(colors KONSOLE_DBUS_SESSION=/Sessions/1)" = "$(switched Breeze)"
check 'colors: restored after a failure of claude (#36 R12)' \
	test "$(colors KONSOLE_DBUS_SESSION=/Sessions/1 FAKE_SESSION_PROFILE=Mine FAKE_CLAUDE_STATUS=3)" = "$(switched mine)"
check "colors: the status kept with the colors (#36 R10, R12)" sh -c \
	'PATH="$1:$2:$PATH" FAKE_CLAUDE_ARGS="$3" FAKE_CLAUDE_STATUS=3 KONSOLE_DBUS_SESSION=/Sessions/1 "$4" >/dev/null; test $? -eq 3' \
	_ "$dbusbin" "$fakebin" "$args" "$launcher"
check 'colors: none outside Konsole (#36 R12)' test -z "$(colors)"

# --- launchers: team (#36 R3, R13, R14) ----------------------------------------------------

# Only the tools team needs, so that the real Konsole is never in reach, and a fake konsole
# that records its arguments, then the layout it was given.
teambin=$tmp/teambin
mkdir -p "$teambin"
for tool in bash cat dirname mktemp rm sed sleep; do
	ln -s "$(command -v "$tool")" "$teambin/$tool"
done
printf '%s\n' '#!/bin/sh' 'printf "%s\n" "$1" "$2" >"$FAKE_KONSOLE_ARGS.args"' 'cat "$3" >"$FAKE_KONSOLE_ARGS"' \
	>"$teambin/konsole"
chmod +x "$teambin/konsole"
opened=$tmp/team-layout
# team_run BIN [ARGS...]: run BIN/team with only the fake tools on the PATH.
team_run() {
	rm -f "$opened" "$opened.args"
	team=$1/team
	shift
	env PATH="$teambin" FAKE_KONSOLE_ARGS="$opened" "$team" "$@"
}
# konsole_opened: wait for the fake konsole started in the background, then print the layout.
konsole_opened() {
	i=0
	while [ ! -s "$opened" ] && [ $i -lt 50 ]; do
		sleep 0.1
		i=$((i + 1))
	done
	cat "$opened"
}
# layout BIN MEMBER...: the layout expected for these members of BIN, in $workdir.
layout() {
	bin=$1
	shift
	printf '{\n    "Orientation": "Horizontal",\n    "Widgets": [\n'
	while [ $# -gt 0 ]; do
		separator=,
		[ $# -gt 1 ] || separator=
		cat <<EOF
        { "SessionRestoreId": 0, "Command": "sh -c 'cd -- \\"\$1\\" && exec \\"\$2\\"' team '$tmp/it'\\\\''s here' '$bin/$1'" }$separator
EOF
		shift
	done
	printf '    ]\n}\n'
}

workdir="$tmp/it's here"
mkdir -p "$workdir"
solo=$tmp/members-noid-bin
check 'team: installed with the assistant (#36 R3)' test -x "$solo/team"
team_run "$solo" "$workdir" >/dev/null 2>&1
check 'team: one member, one pane in DIR (#36 R13)' test "$(konsole_opened)" = "$(layout "$solo" assistant)"
check 'team: a new Konsole window with the layout (#36 R13)' \
	test "$(cat "$opened.args")" = "$(expected --separate --layout)"

claude=$tmp/team
kira_profile --copy --bin-dir "$claude-bin" --analyst >/dev/null
duo=$claude-bin
(cd "$workdir" && team_run "$duo") >/dev/null 2>&1
check 'team: two members side by side, in the current directory by default (#36 R13)' \
	test "$(konsole_opened)" = "$(layout "$duo" assistant analyst)"

# team_fails MESSAGE BIN [ARGS...]: whether BIN/team fails with MESSAGE and opens no window.
team_fails() {
	message=$1
	shift
	! team_run "$@" 2>"$tmp/team-error" &&
		grep -qF "team: $message" "$tmp/team-error" &&
		{ sleep 0.2; [ ! -f "$opened.args" ]; }
}
check 'team: an invalid DIR fails (#36 R14)' team_fails 'not a directory' "$duo" "$tmp/nope"
mv "$teambin/konsole" "$tmp/konsole"
check 'team: fails without Konsole (#36 R14)' team_fails 'Konsole is not installed' "$duo" "$workdir"
mv "$tmp/konsole" "$teambin/konsole"

# The shell is split on purpose, to allow options.
# shellcheck disable=SC2086
env -u XDG_DATA_HOME HOME="$tmp/home" CLAUDE_CONFIG_DIR="$tmp/launchers-home" $shell "$root/get-kira.sh" \
	--name Alex --gender female --language auto --no-co-author --only launchers </dev/null >/dev/null
check 'launchers: ~/.local/share/konsole by default (#36 R6)' test -f "$tmp/home/.local/share/konsole/kirakit-assistant.colorscheme"

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
check 'link: board-status installed (#64)' test -L "$claude/skills/board-status"
check 'link: next-task installed (#89)' test -L "$claude/skills/next-task"
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
check 'assistant: no warning with both keys' sh -c '! grep -q "warning:.* key" "$1"' _ "$tmp/assistant.log"
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

# --- permission rules in settings.json (#67) -----------------------------------------------

kira_rule='"Bash(GH_TOKEN=$(gh auth token --user kira-bot) gh issue create:*)"'
iris_rule='"Bash(GH_TOKEN=$(gh auth token --user iris-bot) gh project item-list:*)"'

# kira_team ARGS: kira with an assistant and an analyst who both have a GitHub account.
kira_team() {
	kira --name Alex --gender female --language auto --assistant 'Kira <kira@example.com>' \
		--assistant-github kira-bot --analyst-github iris-bot "$@"
}

# rule_count FILE: how many permission rules FILE holds, one per line.
rule_count() {
	grep -c '^ *"Bash(' "$1" || true
}

# valid_json FILE: whether FILE parses, when a JSON parser is at hand.
valid_json() {
	if command -v python3 >/dev/null 2>&1; then
		python3 -c 'import json, sys; json.load(open(sys.argv[1]))' "$1"
	fi
}

claude=$tmp/permissions-missing
kira_team --copy >/dev/null
check 'permissions: file missing, created (R1)' contains "$claude/settings.json" "$kira_rule"
check 'permissions: file missing, valid JSON (R4)' valid_json "$claude/settings.json"
check 'permissions: assistant board rules (R1)' contains "$claude/settings.json" '"Bash(GH_TOKEN=$(gh auth token --user kira-bot) gh project item-add:*)"'
check 'permissions: assistant pushes main and branches (R1)' sh -c 'grep -qF "\"Bash(git push origin main)\"" "$1" && grep -qF "\"Bash(git push -u origin feat/:*)\"" "$1" && grep -qF "\"Bash(git push origin --delete:*)\"" "$1"' _ "$claude/settings.json"
check 'permissions: analyst rules (R2)' contains "$claude/settings.json" "$iris_rule"
check 'permissions: analyst has nothing else (R2)' test "$(grep -c 'user iris-bot' "$claude/settings.json")" = 7
check 'permissions: no release rules (R1)' sh -c '! grep -q -e "release create" -e "origin v:" "$1"' _ "$claude/settings.json"
check 'permissions: 33 rules (R1, R2)' test "$(rule_count "$claude/settings.json")" = 33
check 'permissions: rerun changes nothing (R5)' unchanged kira --copy
check 'permissions: no rule twice (R5)' test "$(rule_count "$claude/settings.json")" = 33

claude=$tmp/permissions-none
mkdir -p "$claude"
printf '{\n  "keep": true\n}\n' >"$claude/settings.json"
kira_profile --copy >/dev/null
check 'permissions: no GitHub account, no rules (R1, R2)' sh -c '! grep -q permissions "$1"' _ "$claude/settings.json"

claude=$tmp/permissions-new
mkdir -p "$claude"
printf '{\n  "keep": true,\n  "env": {"A": "1"}\n}\n' >"$claude/settings.json"
kira_team --copy >/dev/null
check 'permissions: no permissions key, added (R1)' contains "$claude/settings.json" "$kira_rule"
check 'permissions: no permissions key, others kept (R4)' sh -c 'grep -qF "\"keep\": true," "$1" && grep -qF "\"env\": {\"A\": \"1\"}" "$1"' _ "$claude/settings.json"
check 'permissions: no permissions key, valid JSON (R4)' valid_json "$claude/settings.json"

for empty in '[]' '[\n    ]'; do
	claude=$tmp/permissions-empty
	rm -rf "$claude"
	mkdir -p "$claude"
	printf '{\n  "permissions": {\n    "allow": %b,\n    "deny": ["Bash(rm:*)"]\n  }\n}\n' "$empty" >"$claude/settings.json"
	kira_team --copy >/dev/null
	check "permissions: empty allow ($empty), added (R1)" test "$(rule_count "$claude/settings.json")" = 33
	check "permissions: empty allow ($empty), valid JSON (R4)" valid_json "$claude/settings.json"
	check "permissions: empty allow ($empty), deny kept (R4)" contains "$claude/settings.json" '"deny": ["Bash(rm:*)"]'
done

claude=$tmp/permissions-mine
mkdir -p "$claude"
printf '{\n  "permissions": {\n    "allow": [\n      "Bash(make:*)",\n      %s\n    ],\n    "defaultMode": "auto"\n  },\n  "keep": true\n}\n' "$kira_rule" >"$claude/settings.json"
kira_team --copy >/dev/null
check 'permissions: own rules kept (R4)' sh -c 'grep -qxF "      \"Bash(make:*)\"," "$1" && grep -qF "\"defaultMode\": \"auto\"" "$1"' _ "$claude/settings.json"
check 'permissions: added to own rules (R1)' contains "$claude/settings.json" "$iris_rule"
check 'permissions: a rule present not added again (R5)' test "$(grep -cF "$kira_rule" "$claude/settings.json")" = 1
check 'permissions: own rules, valid JSON (R4)' valid_json "$claude/settings.json"
check 'permissions: own rules, 34 rules (R5)' test "$(rule_count "$claude/settings.json")" = 34

for shape in '"allow": ["Bash(make:*)"]' '"allow": ["Bash(make:*)"], "ask": {"allow": []}'; do
	claude=$tmp/permissions-unknown
	rm -rf "$claude"
	mkdir -p "$claude"
	printf '{\n  "outputStyle": "Kira (cozy)",\n  "attribution": {"commit": "", "pr": ""},\n  "permissions": {%s}\n}\n' "$shape" >"$claude/settings.json"
	cp "$claude/settings.json" "$tmp/permissions-unknown.orig"
	kira_team --copy >"$tmp/permissions-unknown.log"
	check "permissions: shape not recognized ($shape), warning (R6)" grep -q 'warning: cannot add the permission rules' "$tmp/permissions-unknown.log"
	check "permissions: shape not recognized ($shape), rules printed (R6)" grep -qxF "  $iris_rule" "$tmp/permissions-unknown.log"
	check "permissions: shape not recognized ($shape), file unchanged (R6)" cmp -s "$tmp/permissions-unknown.orig" "$claude/settings.json"
done

claude=$tmp/permissions-dry
mkdir -p "$claude"
printf '{\n  "keep": true\n}\n' >"$claude/settings.json"
kira_team --dry-run >"$tmp/permissions-dry.log"
check 'permissions: dry run reports the rules (R9)' grep -qF 'set permission: Bash(GH_TOKEN=$(gh auth token --user iris-bot) gh issue create:*)' "$tmp/permissions-dry.log"
check 'permissions: dry run reports every rule (R9)' test "$(grep -c 'set permission: ' "$tmp/permissions-dry.log")" = 33
check 'permissions: dry run writes nothing (R9)' sh -c '! grep -q permissions "$1"' _ "$claude/settings.json"

# --- recording, updating and removing the permission rules (#67) ---------------------------

release_rule='"Bash(GH_TOKEN=$(gh auth token --user kira-bot) gh release create:*)"'
tag_rule='"Bash(git push origin v:*)"'
main_rule='"Bash(git push origin main)"'

# occurrences TEXT: how many times settings.json of $claude holds TEXT.
occurrences() {
	grep -cF -- "$1" "$claude/settings.json" || true
}

# recorded RULE: whether the record of $claude lists RULE (without its quotes).
recorded() {
	rule=${1#\"}
	grep -qxF -- "${rule%\"}" "$claude/.kirakit-permissions"
}

# own_rules: a settings.json with the user's own rules, one of them identical to kirakit's.
own_rules() {
	mkdir -p "$claude"
	printf '{\n  "permissions": {\n    "allow": [\n      "Bash(make:*)",\n      %s\n    ]\n  }\n}\n' "$main_rule" >"$claude/settings.json"
}

claude=$tmp/record-releases
kira_team --copy >/dev/null
check 'record: no release rules by default (R3)' test "$(occurrences 'release create')" = 0
check 'record: no tag rule by default (R3)' test "$(occurrences "$tag_rule")" = 0
check 'record: releases off saved (R3)' profile_has 'allow_releases=no'
check 'record: rules recorded (R7)' recorded "$kira_rule"
check 'record: every rule recorded (R7)' test "$(wc -l <"$claude/.kirakit-permissions")" -eq 33
kira --copy --allow-releases >/dev/null
check 'record: release rule with --allow-releases (R3)' test "$(occurrences "$release_rule")" = 1
check 'record: tag rule with --allow-releases (R3)' test "$(occurrences "$tag_rule")" = 1
check 'record: releases on saved (R3)' profile_has 'allow_releases=yes'
check 'record: release rules recorded (R3)' recorded "$release_rule"
check 'record: releases kept on rerun (R3)' unchanged kira --copy
kira --copy --no-allow-releases >/dev/null
check 'record: releases turned off, release rule removed (R7)' test "$(occurrences 'release create')" = 0
check 'record: releases turned off, tag rule removed (R7)' test "$(occurrences "$tag_rule")" = 0
check 'record: releases turned off, other rules kept (R7)' test "$(rule_count "$claude/settings.json")" = 33
check 'record: releases turned off, valid JSON (R7)' valid_json "$claude/settings.json"
check 'record: releases turned off, record updated (R7)' sh -c '! grep -q "release create" "$1"' _ "$claude/.kirakit-permissions"
check 'record: releases turned off, saved (R3)' profile_has 'allow_releases=no'

claude=$tmp/record-login
kira_team --copy >/dev/null
kira --copy --assistant-github kira-new >/dev/null
check 'record: login changed, old rules removed (R7)' test "$(occurrences 'user kira-bot')" = 0
check 'record: login changed, new rules added (R7)' test "$(occurrences 'user kira-new')" = 10
check 'record: login changed, branch rules kept (R7)' test "$(occurrences "$main_rule")" = 1
check 'record: login changed, valid JSON (R7)' valid_json "$claude/settings.json"
check 'record: login changed, record follows (R7)' sh -c '! grep -q "user kira-bot" "$1" && grep -q "user kira-new" "$1"' _ "$claude/.kirakit-permissions"
kira --copy --assistant-github '' >/dev/null
check 'record: account removed, its rules removed (R7)' test "$(occurrences 'user kira-new')" = 0
check 'record: account removed, its branch rules removed (R7)' test "$(occurrences 'git push')" = 0
check "record: account removed, the analyst's kept (R7)" test "$(rule_count "$claude/settings.json")" = 7
check 'record: account removed, valid JSON (R7)' valid_json "$claude/settings.json"
kira --copy --analyst-github '' >/dev/null
check 'record: every account removed, no rules left (R7)' test "$(rule_count "$claude/settings.json")" = 0
check 'record: every account removed, valid JSON (R7)' valid_json "$claude/settings.json"
check 'record: every account removed, no record (R7)' test ! -e "$claude/.kirakit-permissions"

claude=$tmp/record-mine
own_rules
kira_team --copy >/dev/null
check 'record: a rule present before is not recorded (R12)' sh -c '! grep -qxF "Bash(git push origin main)" "$1"' _ "$claude/.kirakit-permissions"
check 'record: a rule present before is not added again (R12)' test "$(occurrences "$main_rule")" = 1
kira --copy --assistant-github '' >/dev/null
check 'record: a rule present before survives an update (R12)' test "$(occurrences "$main_rule")" = 1
check "record: the user's own rule survives an update (R4)" test "$(occurrences '"Bash(make:*)"')" = 1
kira_team --copy >/dev/null
kira --uninstall >/dev/null
check 'record: a rule present before survives uninstall (R12)' test "$(occurrences "$main_rule")" = 1
check "record: uninstall leaves the user's rules (R8)" test "$(occurrences '"Bash(make:*)"')" = 1
check "record: uninstall removes kirakit's rules (R8)" test "$(rule_count "$claude/settings.json")" = 2
check 'record: uninstall, valid JSON (R8)' valid_json "$claude/settings.json"
check 'record: uninstall removes the record (R8)' test ! -e "$claude/.kirakit-permissions"

claude=$tmp/record-deleted
kira_team --copy >/dev/null
grep -vF "$kira_rule" "$claude/settings.json" >"$tmp/record-deleted.json"
cat "$tmp/record-deleted.json" >"$claude/settings.json"
kira --copy >/dev/null
check 'record: a rule deleted by hand comes back (R13)' test "$(occurrences "$kira_rule")" = 1
check 'record: a rule deleted by hand stays recorded (R13)' recorded "$kira_rule"
check 'record: a rule deleted by hand, valid JSON (R13)' valid_json "$claude/settings.json"

claude=$tmp/record-twice
kira_team --copy >/dev/null
awk -v rule="$kira_rule" '{ print } /"allow": \[/ { print "      " rule "," }' \
	"$claude/settings.json" >"$tmp/record-twice.json"
cat "$tmp/record-twice.json" >"$claude/settings.json"
check 'record: a rule added twice by hand (R14)' test "$(occurrences "$kira_rule")" = 2
kira --copy --assistant-github '' >/dev/null
check 'record: one occurrence removed (R14)' test "$(occurrences "$kira_rule")" = 1
check 'record: the copy is no longer recorded (R14)' sh -c '! grep -q "user kira-bot" "$1"' _ "$claude/.kirakit-permissions"
check 'record: one occurrence removed, valid JSON (R14)' valid_json "$claude/settings.json"

claude=$tmp/record-shared
kira --name Alex --gender female --language auto --assistant 'Kira <kira@example.com>' \
	--assistant-github team-bot --analyst-github team-bot --copy >/dev/null
shared_rule='"Bash(GH_TOKEN=$(gh auth token --user team-bot) gh issue create:*)"'
list_rule='"Bash(GH_TOKEN=$(gh auth token --user team-bot) gh project item-list:*)"'
check 'record: a shared rule once (R5)' test "$(occurrences "$shared_rule")" = 1
kira --copy --no-analyst >/dev/null
check 'record: a rule another member expects is kept (R7)' test "$(occurrences "$shared_rule")" = 1
check 'record: it stays recorded (R7)' recorded "$shared_rule"
check "record: the removed member's own rule goes (R7)" test "$(occurrences "$list_rule")" = 0

claude=$tmp/record-unknown
kira_team --copy >/dev/null
# One line for the whole array: a shape the installer does not change.
awk '/"allow": \[/ { line = $0; joined = 1; next }
	joined && /^ *\]/ { sub(/^ */, ""); print line $0; joined = 0; next }
	joined { sub(/^ */, ""); line = line $0; next }
	{ print }' "$claude/settings.json" >"$tmp/record-unknown.json"
cat "$tmp/record-unknown.json" >"$claude/settings.json"
cp "$claude/.kirakit-permissions" "$tmp/record-unknown.record"
kira --copy --assistant-github '' >"$tmp/record-unknown.log"
check 'record: removal refused, warning (R15)' grep -q 'warning: cannot remove the permission rules' "$tmp/record-unknown.log"
check 'record: removal refused, rules printed (R15)' grep -qxF "  $kira_rule" "$tmp/record-unknown.log"
check 'record: removal refused, file unchanged (R15)' cmp -s "$tmp/record-unknown.json" "$claude/settings.json"
check 'record: removal refused, record kept on update (R15)' cmp -s "$tmp/record-unknown.record" "$claude/.kirakit-permissions"
kira --uninstall >"$tmp/record-unknown-uninstall.log"
check 'record: removal refused on uninstall, warning (R15)' grep -qxF "  $iris_rule" "$tmp/record-unknown-uninstall.log"
check 'record: removal refused on uninstall, file unchanged (R15)' cmp -s "$tmp/record-unknown.json" "$claude/settings.json"
check 'record: removal refused on uninstall, record removed (R15)' test ! -e "$claude/.kirakit-permissions"

# --- the coder's permission rules (#79) ----------------------------------------------------

cleo_rule='"Bash(GH_TOKEN=$(gh auth token --user cleo-bot) gh pr edit:*)"'

# allows FILE COMMAND: whether a Bash rule of FILE matches COMMAND, as Claude Code matches
# them: "Bash(PREFIX:*)" for any command that starts with PREFIX, "Bash(COMMAND)" exactly.
allows() {
	sed -n 's/^ *"Bash(\(.*\))",\{0,1\}$/\1/p' "$1" | awk -v command="$2" '
		/:\*$/ { if (index(command, substr($0, 1, length($0) - 2)) == 1) found = 1; next }
		$0 == command { found = 1 }
		END { exit !found }'
}
lead_edit_rule='"Bash(GH_TOKEN=$(gh auth token --user kira-bot) gh pr edit:*)"'

claude=$tmp/coder-rules-alone
# An assistant without a GitHub account: the profile is complete, and only the coder has rules.
kira --name Alex --gender female --language auto --assistant 'Kira <kira@example.com>' \
	--coder 'Cleo <cleo@example.com>' --coder-github cleo-bot --copy >/dev/null
check 'coder rules: her pull requests (R25)' contains "$claude/settings.json" "$cleo_rule"
check 'coder rules: her issues (R25)' contains "$claude/settings.json" '"Bash(GH_TOKEN=$(gh auth token --user cleo-bot) gh issue comment:*)"'
check 'coder rules: her board moves (R25)' contains "$claude/settings.json" '"Bash(GH_TOKEN=$(gh auth token --user cleo-bot) gh project item-edit:*)"'
check 'coder rules: her work branches (R25)' sh -c 'grep -qF "\"Bash(git push -u origin feat/:*)\"" "$1" && grep -qF "\"Bash(git push origin --delete feat/:*)\"" "$1"' _ "$claude/settings.json"
check 'coder rules: she cannot push main (R25, D25)' test "$(occurrences 'origin main')" = 0
check 'coder rules: she deletes her work branches (R25)' allows "$claude/settings.json" 'git push origin --delete fix/12-name'
check 'coder rules: she cannot delete main (R25, D25)' sh -c '! "$@"' _ allows "$claude/settings.json" 'git push origin --delete main'
check 'coder rules: she cannot push to main (R25, D25)' sh -c '! "$@"' _ allows "$claude/settings.json" 'git push origin main'
check 'coder rules: no broad delete rule (D25)' test "$(occurrences '"Bash(git push origin --delete:*)"')" = 0
check 'coder rules: no release or tag (R25)' sh -c '! grep -q -e "release create" -e "origin v:" "$1"' _ "$claude/settings.json"
check 'coder rules: 30 rules (R25)' test "$(rule_count "$claude/settings.json")" = 30
check 'coder rules: recorded (R25)' recorded "$cleo_rule"
check 'coder rules: rerun changes nothing (R25)' unchanged kira --copy

claude=$tmp/coder-rules-team
kira_team --coder 'Cleo <cleo@example.com>' --coder-github cleo-bot --copy >/dev/null
check "coder rules: the lead's pr edit with a coder (R27)" contains "$claude/settings.json" "$lead_edit_rule"
check 'coder rules: the shared push rules once (R25)' test "$(occurrences '"Bash(git push origin feat/:*)"')" = 1
check 'coder rules: the lead still pushes main (R25)' test "$(occurrences "$main_rule")" = 1
check 'coder rules: the lead keeps the broad delete rule (R25)' test "$(occurrences '"Bash(git push origin --delete:*)"')" = 1
check 'coder rules: the lead may delete any branch (R25)' allows "$claude/settings.json" 'git push origin --delete main'
check 'coder rules: team, valid JSON (R25)' valid_json "$claude/settings.json"
kira --copy --coder-github '' >/dev/null
check 'coder rules: removed without her account (R25)' test "$(occurrences 'user cleo-bot')" = 0
check "coder rules: the lead's pr edit removed with her (R27)" test "$(occurrences "$lead_edit_rule")" = 0
check 'coder rules: the shared push rules stay for the lead (R25)' test "$(occurrences '"Bash(git push origin feat/:*)"')" = 1
check 'coder rules: back to the team without a coder (R25)' test "$(rule_count "$claude/settings.json")" = 33
check 'coder rules: removal, valid JSON (R25)' valid_json "$claude/settings.json"
check 'coder rules: her delete rules removed (R25)' test "$(occurrences 'delete feat/')" = 0
check 'coder rules: removal, record updated (R25)' sh -c '! grep -q -e "user cleo-bot" -e "pr edit" "$1"' _ "$claude/.kirakit-permissions"

claude=$tmp/coder-rules-none
kira_team --coder 'Cleo <cleo@example.com>' --copy >/dev/null
check "coder rules: no account, no rule (R25)" sh -c '! grep -q "pr edit" "$1"' _ "$claude/settings.json"
check "coder rules: no lead's pr edit without a coder account (R27)" test "$(rule_count "$claude/settings.json")" = 33

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

# Commit the copy of the working tree into a scratch repository.
cp -Rp "$root" "$tmp/remote"
rm -rf "$tmp/remote/dist"
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

# A release tag is annotated (and signed), and main moves on after it.
git -C "$tmp/remote" -c user.name=test -c user.email=test@example.com -c tag.gpgsign=false \
	tag -a -m 'v0.11.0' v0.11.0
printf '\nafter the tag\n' >>"$tmp/remote/claude/skills/pull/SKILL.md"
git -C "$tmp/remote" -c user.name=test -c user.email=test@example.com -c commit.gpgsign=false \
	commit -q -a -m 'after the tag'

# fetch_output REF: everything a dry run fetching REF writes, stdout and stderr, in the
# French locale when the system has it, with git's advice left at its defaults.
fetch_output() {
	CLAUDE_CONFIG_DIR=$tmp/quiet KIRAKIT_REPO="file://$tmp/remote" KIRAKIT_REF=$1 \
		LANG=fr_CA.UTF-8 LC_ALL=fr_CA.UTF-8 $shell -s -- --dry-run \
		--name Alex --gender female --language auto --no-co-author \
		<"$root/get-kira.sh" 2>&1
}

# only_kirakit FILE: whether every line from "fetching" to "source" is kirakit's own.
only_kirakit() {
	grep -q '^kirakit: fetching ' "$1" && grep -q '^kirakit: source: ' "$1" &&
		! sed -n '/^kirakit: fetching /,/^kirakit: source: /p' "$1" | grep -v '^kirakit:'
}

fetch_output v0.11.0 >"$tmp/fetch-tag.out" || true
check 'fetch: only kirakit lines for an annotated tag (#86 R1)' only_kirakit "$tmp/fetch-tag.out"
fetch_output main >"$tmp/fetch-main.out" || true
check 'fetch: only kirakit lines for a branch (#86 R2)' only_kirakit "$tmp/fetch-main.out"

# R4: the installed source is the commit the requested ref points to.
CLAUDE_CONFIG_DIR=$tmp/at-tag KIRAKIT_REPO="file://$tmp/remote" KIRAKIT_REF=v0.11.0 \
	$shell -s -- --name Alex --gender female --language auto --no-co-author \
	<"$root/get-kira.sh" >/dev/null 2>&1 || true
check 'fetch: a tag installs the commit it points to (#86 R4)' \
	sh -c 'test -f "$1" && ! grep -qF "after the tag" "$1"' _ "$tmp/at-tag/skills/pull/SKILL.md"
CLAUDE_CONFIG_DIR=$tmp/at-main KIRAKIT_REPO="file://$tmp/remote" KIRAKIT_REF=main \
	$shell -s -- --name Alex --gender female --language auto --no-co-author \
	<"$root/get-kira.sh" >/dev/null 2>&1 || true
check 'fetch: a branch installs its last commit (#86 R4)' \
	contains "$tmp/at-main/skills/pull/SKILL.md" 'after the tag'

# R3: an unknown ref fails, with git's error and kirakit's, and installs nothing.
status=0
CLAUDE_CONFIG_DIR=$tmp/unknown KIRAKIT_REPO="file://$tmp/remote" KIRAKIT_REF=no-such-ref \
	LC_ALL=C $shell -s -- --name Alex --gender female --language auto --no-co-author \
	<"$root/get-kira.sh" >"$tmp/fetch-unknown.out" 2>&1 || status=$?
check 'fetch: an unknown ref fails (#86 R3)' test "$status" -ne 0
check "fetch: an unknown ref shows git's error (#86 R3)" contains "$tmp/fetch-unknown.out" "couldn't find remote ref no-such-ref"
check 'fetch: an unknown ref shows could not fetch (#86 R3)' \
	contains "$tmp/fetch-unknown.out" "could not fetch file://$tmp/remote"
check 'fetch: an unknown ref installs nothing (#86 R3)' test ! -e "$tmp/unknown"

# --- the clone -----------------------------------------------------------------------------

check "clone: dist/ unchanged" test "$(dist_fingerprint)" = "$dist_before"

if [ "$failures" -gt 0 ]; then
	printf '%s test(s) failed\n' "$failures"
	exit 1
fi
printf 'all tests passed\n'
