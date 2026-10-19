#!/bin/sh
# Build Claude Code output styles from personas/_core.md and one overlay per persona.
#
# An overlay is a Markdown file whose front matter becomes the style's front matter and
# whose body replaces the {{overlay}} marker of the core text. Files starting with "_" are
# not personas.
#
# The text can refer to the user with these placeholders:
#   {{user}}   name and description, e.g. "Alex, a female staff software developer"
#   {{they}}   {{them}}   {{their}}   pronouns (avoid verbs that agree with {{they}})
#
# Usage: build-styles.sh [-o DIR] [--name NAME] [--gender GENDER] [PERSONA...]
set -eu

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
personas_dir=$root/personas
out_dir=$root/dist/output-styles
name=
gender=unspecified
nl='
'

die() {
	printf 'build-styles: %s\n' "$*" >&2
	exit 1
}

usage() {
	cat <<EOF
Usage: build-styles.sh [-o DIR] [--name NAME] [--gender GENDER] [PERSONA...]

Build output styles into DIR (default: dist/output-styles).
With no PERSONA, build every overlay in personas/.

  --name NAME      How Kira calls the user (default: none)
  --gender GENDER  male, female, nonbinary or unspecified (default: unspecified)
EOF
}

while [ $# -gt 0 ]; do
	case $1 in
	-o | --out | --name | --gender)
		[ $# -ge 2 ] || die "missing value for $1"
		case $1 in
		--name) name=$2 ;;
		--gender) gender=$2 ;;
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

case $name in
*"$nl"* | *'{{'* | *'}}'*) die "invalid name: $name" ;;
esac

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

build_one() {
	overlay=$personas_dir/$1.md
	[ -f "$overlay" ] || die "unknown persona: $1"
	awk 'NR == 1 && $0 != "---" { exit 1 } NR > 1 && $0 == "---" { found = 1; exit } END { exit !found }' "$overlay" ||
		die "$overlay: missing front matter"

	tmp=$out_dir/.$1.md.tmp
	body=$out_dir/.$1.body.tmp
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
	} | KIRA_USER=$user KIRA_THEY=$they KIRA_THEM=$them KIRA_THEIR=$their awk '
		# Literal replacement: values may contain characters special to gsub.
		function replace(s, key, value,   i, out) {
			out = ""
			while ((i = index(s, key)) > 0) {
				out = out substr(s, 1, i - 1) value
				s = substr(s, i + length(key))
			}
			return out s
		}
		{
			$0 = replace($0, "{{user}}", ENVIRON["KIRA_USER"])
			$0 = replace($0, "{{they}}", ENVIRON["KIRA_THEY"])
			$0 = replace($0, "{{them}}", ENVIRON["KIRA_THEM"])
			$0 = replace($0, "{{their}}", ENVIRON["KIRA_THEIR"])
			print
		}' >"$tmp"
	rm -f "$body"

	unknown=$(sed -n 's/.*\({{[^}]*}}\).*/\1/p' "$tmp" | head -n 1)
	if [ -n "$unknown" ]; then
		rm -f "$tmp"
		die "$overlay: unknown placeholder $unknown"
	fi
	mv -f "$tmp" "$out_dir/$1.md"
	printf '%s\n' "$out_dir/$1.md"
}

mkdir -p "$out_dir"
for persona in "$@"; do
	build_one "$persona"
done
