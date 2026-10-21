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
trap 'rm -rf "$tmp"' EXIT
failures=0
claude=
# The launchers go to ~/.local/bin and their Konsole color schemes to $XDG_DATA_HOME/konsole:
# never the real ones.
HOME=$tmp/home
XDG_DATA_HOME=$tmp/data
export HOME XDG_DATA_HOME

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
check 'spec: tasks marked Ready (#51 R8)' contains "$spec_skill" '--label type:task --label status:ready'
check 'spec: no assignee without an assistant account (#51 R8)' sh -c '! grep -q -- "--assignee" "$1"' _ "$spec_skill"
check 'spec: summary comment (#51 R9)' contains "$spec_skill" 'post a summary comment on the parent that mentions the user'
check 'spec: a reversal applied (#51 R10)' contains "$spec_skill" 'or reverses a decision on the'
check 'spec: affected tasks lose Ready (#51 R10)' contains "$spec_skill" 'loses `status:ready`'
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

# --- Iris, a team member (#15 R1, R2, R11, R4, R9) -----------------------------------------

$shell "$root/scripts/build.sh" -o "$tmp/iris-build" --name Alex --gender female --analyst \
	--analyst-github iris-bot >/dev/null
iris_style=$tmp/iris-build/output-styles/iris.md
iris_agent=$tmp/iris-build/agents/iris.md
check 'iris build: style named Iris' grep -qx 'name: Iris' "$iris_style"
check 'iris build: style keeps the coding instructions' grep -qx 'keep-coding-instructions: true' "$iris_style"
check 'iris build: agent named iris' grep -qx 'name: iris' "$iris_agent"
check 'iris build: agent says when to delegate' grep -q '^description: Use Iris to clarify an idea' "$iris_agent"
check 'iris build: no delegate key left' sh -c '! grep -q "^delegate:" "$1" "$2"' _ "$iris_style" "$iris_agent"
check 'iris build: introduces Iris' contains "$iris_style" 'You are Iris, the team'\''s analyst'
check 'iris build: personalized' contains "$iris_style" 'The user is Alex, a female staff software developer.'
check 'iris build: no placeholder' sh -c '! grep -q "{{" "$1" "$2"' _ "$iris_style" "$iris_agent"
check 'iris build: her own voice (#59 R1)' contains "$iris_style" 'Her voice is warm and lively, with a dry, playful wit.'
check 'iris build: her look (#59 R2)' contains "$iris_style" '- auburn curls piled up in a loose braided bun;'
check 'iris build: a few emoticons (#59 R3)' contains "$iris_style" 'She uses a few emoticons (🙂 ✨ 🧐 📌), one or two per message at most'
check 'iris build: no emoticons on GitHub (#59 R4)' contains "$iris_style" 'on GitHub or elsewhere, stay neutral and professional, without emoticons.'
check 'iris build: agent shares the voice (#59 R1)' contains "$iris_agent" 'Her voice is warm and lively, with a dry, playful wit.'
check 'iris build: agent keeps the emoticon rule (#59 R3, R4)' contains "$iris_agent" 'without emoticons.'
tail -n +6 "$iris_agent" >"$tmp/iris-agent-body"
check 'iris build: one body for both' sh -c 'tail -n +7 "$1" | cmp -s - "$2"' _ "$iris_style" "$tmp/iris-agent-body"
$shell "$root/scripts/build.sh" -o "$tmp/iris-none" >/dev/null
check 'iris build: no style without an analyst' test ! -e "$tmp/iris-none/output-styles/iris.md"
check 'iris build: no agent without an analyst' test ! -e "$tmp/iris-none/agents/iris.md"

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
	check "iris $mode: rerun changes nothing" unchanged kira $flag
	kira $flag --no-analyst >/dev/null
	check "iris $mode: style removed without an analyst" sh -c '! test -e "$1" && ! test -L "$1"' _ "$claude/output-styles/iris.md"
	check "iris $mode: agent removed without an analyst" sh -c '! test -e "$1" && ! test -L "$1"' _ "$claude/agents/iris.md"
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
check 'team rules: no section without an analyst' sh -c '! grep -q "The team\|Iris" "$1"' _ "$tmp/iris-none/rules/git.md"

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
(PATH="$tmp/shadow:$bin:$PATH" && kira --copy >"$tmp/members-path.log")
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

# --- the clone -----------------------------------------------------------------------------

check "clone: dist/ unchanged" test "$(dist_fingerprint)" = "$dist_before"

if [ "$failures" -gt 0 ]; then
	printf '%s test(s) failed\n' "$failures"
	exit 1
fi
printf 'all tests passed\n'
