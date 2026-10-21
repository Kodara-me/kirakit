#!/bin/sh
# Build the personalized Claude Code files into DIR (default: dist/):
#   DIR/output-styles/<persona>.md   from personas/_core.md and one overlay per persona
#   DIR/skills/<skill>/              from claude/skills/<skill>/
#   DIR/agents/<agent>.md            from claude/agents/<agent>.md
#   DIR/rules/<rules>.md             from claude/rules/<rules>.md
#   DIR/CLAUDE.md                    from claude/CLAUDE.md
#
# An overlay is a Markdown file whose front matter becomes the style's front matter and
# whose body replaces the {{overlay}} marker of the core text. Files starting with "_" in
# personas/ are not personas.
#
# Markdown files can use these placeholders, filled from the options:
#   {{user}}                  name and description, e.g. "Alex, a female staff software developer"
#   {{they}} {{them}} {{their}}  pronouns (avoid verbs that agree with {{they}})
#   {{language}}              answer language, e.g. "French" or "the language of the conversation"
#   {{co_author}}             the co-author, "NAME <EMAIL>", or nothing
#   {{assistant_name}} {{assistant_email}}  the assistant's git identity, or nothing
#   {{assistant_signing_key}} path to the assistant's public SSH signing key, or nothing
#   {{assistant_github}}      the assistant's GitHub login, or nothing
# A line holding only a placeholder that expands to nothing is removed.
#
# Lines between {{#KEY}} and {{/KEY}} are kept only when KEY is not empty, and lines between
# {{^KEY}} and {{/KEY}} only when it is; KEY is any placeholder above. The markers stand on
# lines of their own, are removed, and blocks can nest.
#
# Usage: build.sh [-o DIR] [--name NAME] [--gender GENDER] [--language LANGUAGE]
#                 [--co-author "NAME <EMAIL>"] [--assistant "NAME <EMAIL>"]
#                 [--assistant-signing-key PATH] [--assistant-github LOGIN] [PERSONA...]
set -eu

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
personas_dir=$root/personas
claude_dir=$root/claude
skills_dir=$claude_dir/skills
out_dir=$root/dist
name=
gender=unspecified
language=auto
co_author=
assistant=
assistant_signing_key=
assistant_github=
nl='
'

die() {
	printf 'build: %s\n' "$*" >&2
	exit 1
}

usage() {
	cat <<EOF
Usage: build.sh [-o DIR] [--name NAME] [--gender GENDER] [--language LANGUAGE]
                [--co-author "NAME <EMAIL>"] [--assistant "NAME <EMAIL>"]
                [--assistant-signing-key PATH] [--assistant-github LOGIN] [PERSONA...]

Build output styles, skills, agents, rules and CLAUDE.md into DIR (default: dist).
With no PERSONA, build every overlay in personas/. Skills are always all built.

  --name NAME                How Kira calls the user (default: none)
  --gender GENDER            male, female, nonbinary or unspecified (default: unspecified)
  --language LANGUAGE        Answer language, or auto to follow the conversation (default: auto)
  --co-author "NAME <EMAIL>" Co-Authored-By trailer for commits (default: none)
  --assistant "NAME <EMAIL>" The assistant's git identity (default: none)
  --assistant-signing-key PATH
                             The assistant's public SSH signing key (default: none)
  --assistant-github LOGIN   The assistant's GitHub account (default: none)
EOF
}

while [ $# -gt 0 ]; do
	case $1 in
	-o | --out | --name | --gender | --language | --co-author | --assistant | \
		--assistant-signing-key | --assistant-github)
		[ $# -ge 2 ] || die "missing value for $1"
		case $1 in
		--name) name=$2 ;;
		--gender) gender=$2 ;;
		--language) language=$2 ;;
		--co-author) co_author=$2 ;;
		--assistant) assistant=$2 ;;
		--assistant-signing-key) assistant_signing_key=$2 ;;
		--assistant-github) assistant_github=$2 ;;
		*) out_dir=$2 ;;
		esac
		shift 2
		;;
	-h | --help)
		usage
		exit 0
		;;
	--)
		shift
		break
		;;
	-*) die "unknown option: $1" ;;
	*) break ;;
	esac
done

for value in "$name" "$language" "$co_author" "$assistant" "$assistant_signing_key"; do
	case $value in
	*"$nl"* | *'{{'* | *'}}'*) die "invalid value: $value" ;;
	esac
done

case $gender in
male) they=he them=him their=his adjective='male ' ;;
female) they=she them=her their=her adjective='female ' ;;
nonbinary) they=they them=them their=their adjective='non-binary ' ;;
unspecified) they=they them=them their=their adjective= ;;
*) die "unknown gender: $gender (expected male, female, nonbinary or unspecified)" ;;
esac

user="a ${adjective}staff software developer"
if [ -n "$name" ]; then
	user="$name, $user"
fi

case $language in
'' | auto) language='the language of the conversation' ;;
esac

case $co_author in
'' | ?*' <'?*@?*'>') ;;
*) die "invalid co-author: $co_author (expected \"NAME <EMAIL>\")" ;;
esac

case $assistant in
'') assistant_name='' assistant_email='' ;;
?*' <'?*@?*'>')
	assistant_name=${assistant% <*}
	assistant_email=${assistant##*<}
	assistant_email=${assistant_email%>}
	;;
*) die "invalid assistant: $assistant (expected \"NAME <EMAIL>\")" ;;
esac

case $assistant_github in
*[!A-Za-z0-9-]*) die "invalid GitHub login: $assistant_github" ;;
esac

export KIRA_USER="$user" KIRA_THEY="$they" KIRA_THEM="$them" KIRA_THEIR="$their" \
	KIRA_LANGUAGE="$language" KIRA_CO_AUTHOR="$co_author" KIRA_ASSISTANT_NAME="$assistant_name" \
	KIRA_ASSISTANT_EMAIL="$assistant_email" KIRA_ASSISTANT_SIGNING_KEY="$assistant_signing_key" \
	KIRA_ASSISTANT_GITHUB="$assistant_github"

# render FILE [ORIGIN]: print FILE with its placeholders filled and its blocks resolved;
# errors name ORIGIN (default: FILE).
render() {
	awk -v file="${2:-$1}" '
		# Literal replacement: values may contain characters special to gsub.
		function replace(s, key, value,   i, out) {
			out = ""
			while ((i = index(s, key)) > 0) {
				out = out substr(s, 1, i - 1) value
				s = substr(s, i + length(key))
			}
			return out s
		}
		function fail(message, where) {
			printf "build: %s:%s: %s\n", file, where, message > "/dev/stderr"
			failed = 1
			exit 1
		}
		BEGIN {
			n = split("user they them their language co_author assistant_name assistant_email assistant_signing_key assistant_github", keys, " ")
			for (k = 1; k <= n; k++) known[keys[k]] = 1
			depth = 0
			hidden = 0
		}
		# Block markers: {{#KEY}}, {{^KEY}} and {{/KEY}} on lines of their own.
		/^\{\{[#^\/][a-z_]+\}\}$/ {
			kind = substr($0, 3, 1)
			key = substr($0, 4, length($0) - 5)
			if (!(key in known)) fail("unknown block " key, NR)
			if (kind == "/") {
				if (depth == 0 || open[depth] != key) fail("unexpected {{/" key "}}", NR)
				if (!shown[depth]) hidden--
				depth--
			} else {
				set = ENVIRON["KIRA_" toupper(key)] != ""
				depth++
				open[depth] = key
				shown[depth] = (kind == "#") ? set : !set
				if (!shown[depth]) hidden++
			}
			next
		}
		hidden { next }
		{
			for (k = 1; k <= n; k++) {
				key = "{{" keys[k] "}}"
				value = ENVIRON["KIRA_" toupper(keys[k])]
				if ($0 == key && value == "") next
				$0 = replace($0, key, value)
			}
			print
		}
		END {
			if (!failed && depth > 0) fail("missing {{/" open[depth] "}}", "end")
		}' "$1"
}

# check FILE SOURCE: fail on any placeholder left in FILE.
check() {
	unknown=$(sed -n 's/.*\({{[^}]*}}\).*/\1/p' "$1" | head -n 1)
	[ -z "$unknown" ] || die "$2: unknown placeholder $unknown"
}

core=$personas_dir/_core.md
[ -f "$core" ] || die "missing $core"
grep -qF '{{overlay}}' "$core" || die "$core: missing {{overlay}} marker"

if [ $# -eq 0 ]; then
	for file in "$personas_dir"/*.md; do
		persona=$(basename "$file" .md)
		case $persona in _*) continue ;; esac
		set -- "$@" "$persona"
	done
fi

build_style() {
	overlay=$personas_dir/$1.md
	[ -f "$overlay" ] || die "unknown persona: $1"
	awk 'NR == 1 && $0 != "---" { exit 1 } NR > 1 && $0 == "---" { found = 1; exit } END { exit !found }' "$overlay" ||
		die "$overlay: missing front matter"

	dir=$out_dir/output-styles
	body=$dir/.$1.body.tmp
	merged=$dir/.$1.merged.tmp
	# Overlay body, without the blank lines that follow the front matter.
	awk 'body && (started || $0 != "") { started = 1; print } NR > 1 && $0 == "---" { body = 1 }' "$overlay" >"$body"
	{
		# Front matter, delimiters included.
		awk '{ print } NR > 1 && $0 == "---" { exit }' "$overlay"
		printf '\n'
		awk -v body="$body" '
			BEGIN { while ((getline line < body) > 0) text = (n++ ? text "\n" : "") line }
			i = index($0, "{{overlay}}") { $0 = substr($0, 1, i - 1) text substr($0, i + 11) }
			{ print }' "$core"
	} >"$merged"
	render "$merged" "$overlay" >"$dir/.$1.md.tmp" || {
		rm -f "$body" "$merged" "$dir/.$1.md.tmp"
		exit 1
	}
	rm -f "$body" "$merged"
	check "$dir/.$1.md.tmp" "$overlay" || {
		rm -f "$dir/.$1.md.tmp"
		exit 1
	}
	mv -f "$dir/.$1.md.tmp" "$dir/$1.md"
	printf '%s\n' "$dir/$1.md"
}

# build_file SOURCE DEST: render one Markdown file.
build_file() {
	mkdir -p "$(dirname "$2")"
	render "$1" >"$2.tmp" || {
		rm -f "$2.tmp"
		exit 1
	}
	check "$2.tmp" "$1" || {
		rm -f "$2.tmp"
		exit 1
	}
	mv -f "$2.tmp" "$2"
	printf '%s\n' "$2"
}

# Skills are copied whole, with their Markdown files rendered.
build_skill() {
	skill=$(basename "$1")
	dest=$out_dir/skills/$skill
	rm -rf "$dest.tmp"
	cp -R "$1" "$dest.tmp"
	find "$dest.tmp" -type f -name '*.md' | while IFS= read -r file; do
		origin=$1/${file#"$dest.tmp"/}
		# Explicit exit: errexit does not apply on the left of the || below.
		render "$file" "$origin" >"$file.rendered" || exit 1
		mv -f "$file.rendered" "$file"
		check "$file" "$origin"
	done || {
		rm -rf "$dest.tmp"
		exit 1
	}
	rm -rf "$dest"
	mv "$dest.tmp" "$dest"
	printf '%s\n' "$dest"
}

mkdir -p "$out_dir/output-styles" "$out_dir/skills"
for persona in "$@"; do
	build_style "$persona"
done
for dir in "$skills_dir"/*/; do
	[ -f "$dir/SKILL.md" ] || continue
	build_skill "${dir%/}"
done
for file in "$claude_dir"/agents/*.md; do
	[ -f "$file" ] || continue
	build_file "$file" "$out_dir/agents/$(basename "$file")"
done
for file in "$claude_dir"/rules/*.md; do
	[ -f "$file" ] || continue
	build_file "$file" "$out_dir/rules/$(basename "$file")"
done
if [ -f "$claude_dir/CLAUDE.md" ]; then
	build_file "$claude_dir/CLAUDE.md" "$out_dir/CLAUDE.md"
fi
