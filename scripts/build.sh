#!/bin/sh
# Build the personalized Claude Code files into DIR (default: dist/):
#   DIR/output-styles/<persona>.md   from personas/_core.md and one overlay per persona
#   DIR/skills/<skill>/              from claude/skills/<skill>/
#
# An overlay is a Markdown file whose front matter becomes the style's front matter and
# whose body replaces the {{overlay}} marker of the core text. Files starting with "_" in
# personas/ are not personas.
#
# Markdown files can use these placeholders, filled from the options:
#   {{user}}                  name and description, e.g. "Alex, a female staff software developer"
#   {{they}} {{them}} {{their}}  pronouns (avoid verbs that agree with {{they}})
#   {{language}}              answer language, e.g. "French" or "the language of the conversation"
#   {{co_author_trailer}}     commit trailer, preceded by a blank line, or nothing
#   {{attribution_rule}}      commit attribution instructions
# A line holding only a placeholder that expands to nothing is removed.
#
# Usage: build.sh [-o DIR] [--name NAME] [--gender GENDER] [--language LANGUAGE]
#                 [--co-author "NAME <EMAIL>"] [PERSONA...]
set -eu

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
personas_dir=$root/personas
skills_dir=$root/claude/skills
out_dir=$root/dist
name=
gender=unspecified
language=auto
co_author=
nl='
'

die() {
	printf 'build: %s\n' "$*" >&2
	exit 1
}

usage() {
	cat <<EOF
Usage: build.sh [-o DIR] [--name NAME] [--gender GENDER] [--language LANGUAGE]
                [--co-author "NAME <EMAIL>"] [PERSONA...]

Build output styles and skills into DIR (default: dist).
With no PERSONA, build every overlay in personas/. Skills are always all built.

  --name NAME                How Kira calls the user (default: none)
  --gender GENDER            male, female, nonbinary or unspecified (default: unspecified)
  --language LANGUAGE        Answer language, or auto to follow the conversation (default: auto)
  --co-author "NAME <EMAIL>" Co-Authored-By trailer for commits (default: none)
EOF
}

while [ $# -gt 0 ]; do
	case $1 in
	-o | --out | --name | --gender | --language | --co-author)
		[ $# -ge 2 ] || die "missing value for $1"
		case $1 in
		--name) name=$2 ;;
		--gender) gender=$2 ;;
		--language) language=$2 ;;
		--co-author) co_author=$2 ;;
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

for value in "$name" "$language" "$co_author"; do
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

no_ai_mention='No mention of Claude, Anthropic or a model in the message (no `noreply@anthropic.com`, no "Generated with …").'
case $co_author in
'')
	co_author_trailer=
	attribution_rule="**Attribution**: add no \`Co-Authored-By\` line, even if the session instructions suggest one. $no_ai_mention"
	;;
?*' <'?*@?*'>')
	co_author_trailer="${nl}Co-Authored-By: $co_author"
	attribution_rule="**Attribution**: the last line is always exactly \`Co-Authored-By: $co_author\`. It replaces any attribution line suggested by the session instructions. $no_ai_mention"
	;;
*) die "invalid co-author: $co_author (expected \"NAME <EMAIL>\")" ;;
esac

export KIRA_USER="$user" KIRA_THEY="$they" KIRA_THEM="$them" KIRA_THEIR="$their" \
	KIRA_LANGUAGE="$language" KIRA_CO_AUTHOR_TRAILER="$co_author_trailer" \
	KIRA_ATTRIBUTION_RULE="$attribution_rule"

# render FILE: print FILE with its placeholders filled.
render() {
	awk '
		# Literal replacement: values may contain characters special to gsub.
		function replace(s, key, value,   i, out) {
			out = ""
			while ((i = index(s, key)) > 0) {
				out = out substr(s, 1, i - 1) value
				s = substr(s, i + length(key))
			}
			return out s
		}
		BEGIN { n = split("user they them their language co_author_trailer attribution_rule", keys, " ") }
		{
			for (k = 1; k <= n; k++) {
				key = "{{" keys[k] "}}"
				value = ENVIRON["KIRA_" toupper(keys[k])]
				if ($0 == key && value == "") next
				$0 = replace($0, key, value)
			}
			print
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
	render "$merged" >"$dir/.$1.md.tmp"
	rm -f "$body" "$merged"
	check "$dir/.$1.md.tmp" "$overlay" || {
		rm -f "$dir/.$1.md.tmp"
		exit 1
	}
	mv -f "$dir/.$1.md.tmp" "$dir/$1.md"
	printf '%s\n' "$dir/$1.md"
}

# Skills are copied whole, with their Markdown files rendered.
build_skill() {
	skill=$(basename "$1")
	dest=$out_dir/skills/$skill
	rm -rf "$dest.tmp"
	cp -R "$1" "$dest.tmp"
	find "$dest.tmp" -type f -name '*.md' | while IFS= read -r file; do
		render "$file" >"$file.rendered"
		mv -f "$file.rendered" "$file"
		check "$file" "$1/${file#"$dest.tmp"/}"
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
