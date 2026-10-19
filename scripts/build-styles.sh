#!/bin/sh
# Build Claude Code output styles from personas/_core.md and one overlay per persona.
#
# An overlay is a Markdown file whose front matter becomes the style's front matter and
# whose body replaces the {{overlay}} line of the core text. Files starting with "_" are
# not personas.
#
# Usage: build-styles.sh [-o DIR] [PERSONA...]
set -eu

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
personas_dir=$root/personas
out_dir=$root/dist/output-styles

die() {
	printf 'build-styles: %s\n' "$*" >&2
	exit 1
}

usage() {
	cat <<EOF
Usage: build-styles.sh [-o DIR] [PERSONA...]

Build output styles into DIR (default: dist/output-styles).
With no PERSONA, build every overlay in personas/.
EOF
}

while [ $# -gt 0 ]; do
	case $1 in
	-o | --out)
		[ $# -ge 2 ] || die "missing value for $1"
		out_dir=$2
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

core=$personas_dir/_core.md
[ -f "$core" ] || die "missing $core"
grep -qx '{{overlay}}' "$core" || die "$core: missing {{overlay}} line"

if [ $# -eq 0 ]; then
	for file in "$personas_dir"/*.md; do
		name=$(basename "$file" .md)
		case $name in _*) continue ;; esac
		set -- "$@" "$name"
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
		awk -v body="$body" '$0 == "{{overlay}}" { while ((getline line < body) > 0) print line; next } { print }' "$core"
	} >"$tmp"
	rm -f "$body"
	mv -f "$tmp" "$out_dir/$1.md"
	printf '%s\n' "$out_dir/$1.md"
}

mkdir -p "$out_dir"
for name in "$@"; do
	build_one "$name"
done
