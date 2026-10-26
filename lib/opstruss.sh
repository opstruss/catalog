# shellcheck shell=sh
#
# Helpers for the script plugins of this catalog. A plugin script loads
# them from its own directory:
#
#   . "$OPSTRUSS_PLUGIN_DIR/../../lib/opstruss.sh"
#
# Each helper is one part of the program contract of OpsTruss, or one thing
# that POSIX sh does poorly, as a list of arguments; what a plugin does with
# its tool stays in the plugin. CONTRIBUTING.md, at the root of the catalog,
# shows them in a plugin and gives the rules for its script.
#
# Loading them sets -eu and umask 077, and traps SIGINT and SIGTERM: on a
# signal, the shell waits for the tool in the foreground, which gets the
# signal too and stops as it does, then ends the script with 130 or 143.
# Without the trap, a shell that is bash would go on to its next line.
#
# The helpers need jq 1.6 or later. A plugin does not define their names
# again: approved, color, fail, input, input_file, known_keys, main, output,
# paths, run_with, scratch, sha256, unchanged, and words; scratch sets tmp.
#
# This file is not a public API; it changes with the plugins of the catalog.

set -eu
umask 077
trap 'exit 130' INT
trap 'exit 143' TERM

# fail prints its arguments to stderr, as one line, and ends the script.
fail() {
	printf '%s\n' "$*" >&2
	exit 1
}

# main runs cmd_<command> with the other arguments, for a script that a
# plugin runs as run: [./<name>.sh, <command>].
main() {
	[ $# -gt 0 ] || fail "usage: $0 <command> [argument...]"
	opstruss_cmd=$1
	shift
	case $opstruss_cmd in
	'' | *[!a-z0-9_]*) fail "unknown command: $opstruss_cmd" ;;
	esac
	command -v "cmd_$opstruss_cmd" >/dev/null 2>&1 || fail "unknown command: $opstruss_cmd"
	"cmd_$opstruss_cmd" "$@"
}

# input prints the input named $1: a string as it is, null or a missing
# input as nothing, and any other value, false among them, as JSON. A
# program outside a run, such as a watch hook, has only INPUT_<NAME>,
# with - as _, which holds the same text. As every $(...), x=$(input x)
# drops the line breaks at the end of a string; input_file keeps them.
input() {
	if [ -n "${OPSTRUSS_INPUTS:-}" ]; then
		jq -r --arg name "$1" \
			'.[$name] | if type == "string" then . elif . == null then "" else tojson end' \
			"$OPSTRUSS_INPUTS"
		return
	fi
	printenv "INPUT_$(printf '%s' "$1" | tr 'a-z-' 'A-Z_')" || true
}

# input_file writes the input named $1 to the file $2 as input prints it,
# with the line breaks at the end of a string, for a tool that reads the
# value from a file.
input_file() {
	jq -j --arg name "$1" \
		'.[$name] | if type == "string" then . elif . == null then "" else tojson end' \
		"$OPSTRUSS_INPUTS" >"$2"
}

# words prints each string of the list input $1 on a line of its own, after
# the text $2, for run_with. $1 may name a list in an object input, as
# args.plan. A missing list prints nothing; a string with a line break ends
# the script, as each line becomes one argument.
#
#   words args.plan >"$tmp/plan.args"
words() {
	opstruss_list "$1" "${2:-}" false
}

# paths prints the list input $1 as words does, with each relative path
# made absolute from the working directory, where every path in an input
# starts: the directory of the file of the unit. The paths then hold for a
# tool that runs in another directory, as tofu -chdir.
#
#   paths var_files -var-file= >"$tmp/vars.args"
paths() {
	opstruss_list "$1" "${2:-}" true
}

opstruss_list() {
	jq -r --arg path "$1" --arg prefix "$2" --argjson absolute "$3" --arg pwd "$PWD" '
		(getpath($path | split(".")) // []) as $list
		| if ($list | type) != "array" then error("the input \($path) is not a list")
		elif any($list[]; type != "string") then error("an item of the input \($path) is not a string")
		elif any($list[]; contains("\n")) then error("an item of the input \($path) holds a line break")
		else $list[] end
		| if $absolute and (startswith("/") | not) then "\($pwd)/\(until(startswith("./") | not; .[2:]))" else . end
		| $prefix + .' "$OPSTRUSS_INPUTS"
}

# known_keys ends the script when the object input $1 has a key other than
# the ones after it, as one that a typo changed, which OpsTruss lets
# through:
#
#   known_keys args init plan apply
known_keys() {
	opstruss_name=$1
	shift
	opstruss_unknown=$(jq -r --arg name "$opstruss_name" \
		'(.[$name] // {} | keys) - $ARGS.positional | join(", ")' "$OPSTRUSS_INPUTS" --args "$@")
	[ -z "$opstruss_unknown" ] || fail "the input $opstruss_name has $opstruss_unknown, which is not one of: $*"
}

# run_with runs the command in its arguments after the file $1, with each
# line of that file as one more argument after them, as written: no shell
# splits, globs, or runs it. words and paths write such a file:
#
#   run_with "$tmp/plan.args" tofu plan -out="$planfile"
run_with() {
	opstruss_file=$1
	shift
	while IFS= read -r opstruss_line; do
		set -- "$@" "$opstruss_line"
	done <"$opstruss_file"
	"$@"
}

# scratch sets tmp to a new directory for the files of the call, as the
# variables of a tool, which goes when the script ends, by a signal too,
# so that no value stays there longer than the call. A script that ends
# with exec leaves it to OpsTruss, which removes OPSTRUSS_TEMP at the end
# of the run.
scratch() {
	tmp=$(mktemp -d "$OPSTRUSS_TEMP/call.XXXXXX")
	trap 'rm -rf "$tmp"' EXIT
}

# color reports whether the tool may print in color: not when OpsTruss sets
# NO_COLOR, which it does when it shows the output of the run without color,
# or reads it as an output. A plugin asks its tool for color with a flag,
# never through the environment, which the programs of the tool would get
# too.
color() {
	[ -z "${NO_COLOR:-}" ]
}

# output writes the output $1 with the text $2, which OpsTruss reads by the
# type that the output declares: a string as it is, a number, true or false,
# or JSON for an array or an object. The text may hold any line, as the
# block ends with a line that it does not hold. A plugin with outputs: tool
# writes $OPSTRUSS_OUTPUT as one JSON object instead, which keeps the types
# of the outputs that no declaration names.
output() {
	opstruss_end=EOF
	opstruss_nl='
'
	while
		case "$opstruss_nl$2$opstruss_nl" in
		*"$opstruss_nl$opstruss_end$opstruss_nl"*) true ;;
		*) false ;;
		esac
	do
		opstruss_end=${opstruss_end}_
	done
	printf '%s<<%s\n%s\n%s\n' "$1" "$opstruss_end" "$2" "$opstruss_end" >>"$OPSTRUSS_OUTPUT"
}

# unchanged writes the result of a call that changed nothing. Without it, a
# call that succeeds changed something, as OpsTruss reads a result without
# changed.
unchanged() {
	printf '{"changed": false}\n' >"$OPSTRUSS_RESULT"
}

# approved reports whether $1, the digest of what up is about to apply, is
# the digest of the plan that was approved. Without an approved plan, as
# when the plan wrote no digest, every digest passes.
approved() {
	[ -z "${OPSTRUSS_DIGEST:-}" ] || [ "$1" = "$OPSTRUSS_DIGEST" ]
}

# sha256 prints the SHA-256 of the file $1, or of stdin, in hex.
sha256() {
	if command -v sha256sum >/dev/null 2>&1; then
		opstruss_sum=$(sha256sum "$@")
	else
		opstruss_sum=$(shasum -a 256 "$@")
	fi
	printf '%s\n' "${opstruss_sum%% *}"
}
