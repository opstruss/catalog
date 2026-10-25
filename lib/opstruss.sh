# shellcheck shell=sh
#
# Helpers for the script plugins of this catalog. A plugin script loads
# them from its own directory:
#
#   . "$OPSTRUSS_PLUGIN_DIR/../../lib/opstruss.sh"
#
# The helpers are POSIX sh and need jq. Loading them sets -eu and umask
# 077, and traps SIGINT and SIGTERM so that the script ends with 130 or
# 143, as a shell does for a signal, instead of going on to its next line.
#
# Rules for the scripts that use them:
#
# - No set -x: it prints the values of inputs, secrets among them, to the log.
# - Write outputs and plans to their files, not through a pipe, when their
#   failure matters: set -e sees only the last command of a pipe.
# - A function joins this file once two plugins use it.
#
# This file is not a public API; it changes with the plugins of the catalog.

set -eu
umask 077
trap 'exit 130' INT
trap 'exit 143' TERM

# fail prints its arguments to stderr and ends the script.
fail() {
	printf '%s\n' "$*" >&2
	exit 1
}

# input prints the input named $1: a string as it is, null or a missing
# input as nothing, and any other value, false among them, as JSON. A
# program outside a run, such as a watch hook, has only INPUT_<NAME>,
# with - as _, which holds the same text.
input() {
	if [ -n "${OPSTRUSS_INPUTS:-}" ]; then
		jq -r --arg name "$1" \
			'.[$name] | if type == "string" then . elif . == null then "" else tojson end' \
			"$OPSTRUSS_INPUTS"
		return
	fi
	printenv "INPUT_$(printf '%s' "$1" | tr 'a-z-' 'A-Z_')" || true
}

# result writes the result of the call: jq -n with the arguments, for
# example result '{changed: false}'.
result() {
	jq -n "$@" >"$OPSTRUSS_RESULT"
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
