#!/bin/sh
# The dotfiles of chezmoi as a unit. On a machine that chezmoi has set up,
# plan fetches the source, so a new commit in the repository shows up, and
# lists each file that differs from the source, as one edited by hand; up
# pulls and applies, over such edits.
#
# chezmoi runs with --no-tty and no stdin, and git with
# GIT_TERMINAL_PROMPT=0: a prompt that the input prompts does not answer
# fails at once, with the message of chezmoi, rather than wait.
#
# The unit has no destroy: chezmoi purge would remove the source, which can
# hold commits that were never pushed, so destroy forgets the unit and
# leaves the source and the files.
#
# shellcheck source-path=SCRIPTDIR source=../../lib/opstruss.sh
. "$OPSTRUSS_PLUGIN_DIR/../../lib/opstruss.sh"

# chezmoi 2.40 is the oldest release that the tests of the plugin run
# with.
chezmoi_version=$(chezmoi --version)
chezmoi_version=$(printf '%s\n' "$chezmoi_version" | sed -n '1s/^chezmoi version v\{0,1\}\([0-9][0-9.]*\).*/\1/p')
at_least "$chezmoi_version" 2.40 ||
	fail "chezmoi needs chezmoi 2.40 or later; this is ${chezmoi_version:-unknown}"

setup() {
	known_keys args init update
	scratch
	GIT_TERMINAL_PROMPT=0
	export GIT_TERMINAL_PROMPT
	source=$(chezmoi source-path)
}

# ready reports whether chezmoi has set the machine up: a source, and the
# configuration that its template made. An init that failed at a prompt
# leaves the source without the configuration.
ready() {
	[ -d "$source/.git" ] && chezmoi cat-config >/dev/null 2>&1
}

# prompts prints the flags of chezmoi init that answer the input prompts,
# one a line. chezmoi takes a pair with one = as it is, but without the
# quotes at its ends, and reads one with more as CSV, where a comma would
# end it: such a pair with a comma or a quote goes in quotes.
prompts() {
	bad=$(jq -r '.prompts // {} | [to_entries[] | select(.value | type | IN("string", "boolean", "number") | not) | .key] | join(", ")' "$OPSTRUSS_INPUTS")
	[ -z "$bad" ] || fail "the input prompts has $bad, which is not a string, a boolean, or an integer"
	bad=$(jq -r '.prompts // {} | [to_entries[] | select("\(.key)=\(.value)" | ([scan("=")] | length) == 1 and (startswith("\"") or endswith("\""))) | .key] | join(", ")' "$OPSTRUSS_INPUTS")
	[ -z "$bad" ] || fail "the input prompts has $bad, whose prompt or answer starts or ends with a quote, which chezmoi drops"
	jq -r '.prompts // {} | to_entries[]
		| {string: "String", boolean: "Bool", number: "Int"}[.value | type] as $kind
		| "\(.key)=\(.value)" as $pair
		| "--prompt\($kind)="
			+ if ($pair | [scan("=")] | length) > 1 and ($pair | test("[,\"]"))
			then "\"" + ($pair | gsub("\""; "\"\"")) + "\"" else $pair end' \
		"$OPSTRUSS_INPUTS"
}

cmd_plan() {
	setup
	if ! ready; then
		echo '{"changes": [{"resource": "dotfiles", "action": "create"}], "outputs": ["commit", "files"], "exact": false}' >"$OPSTRUSS_PLAN"
		return
	fi
	chezmoi git -- fetch --quiet </dev/null
	behind=$(chezmoi git -- rev-list --count 'HEAD..@{upstream}')
	[ "$behind" = 0 ] || echo "the source is $behind commits behind its repository"
	chezmoi status --no-tty </dev/null >"$tmp/status"
	jq -Rn --argjson behind "$behind" '
		[inputs | select(length > 3) | .[3:]] as $files
		| {
			changes: ((if $behind > 0 then [{resource: "source", action: "update"}] else [] end)
				+ [$files[] | {resource: ("file." + .), action: "update"}]),
			outputs: (if $behind > 0 or ($files | length) > 0 then ["commit", "files"] else [] end),
			exact: false
		}' "$tmp/status" >"$OPSTRUSS_PLAN"
}

cmd_up() {
	setup
	if ready; then
		before=$(chezmoi git -- rev-parse HEAD)
		chezmoi status --no-tty </dev/null >"$tmp/status"
		words args.update >"$tmp/update.args"
		run_with "$tmp/update.args" chezmoi update --force --no-tty </dev/null
		after=$(chezmoi git -- rev-parse HEAD)
		[ "$before" != "$after" ] || [ -s "$tmp/status" ] || unchanged
	else
		prompts >"$tmp/init.args"
		words args.init >>"$tmp/init.args"
		repo=$(input repo)
		printf '%s\n' -- "$repo" >>"$tmp/init.args"
		run_with "$tmp/init.args" chezmoi init --apply --force --no-tty </dev/null
	fi
	commit=$(chezmoi git -- rev-parse --short HEAD)
	output commit "$commit"
	chezmoi managed --include files --no-tty </dev/null >"$tmp/files"
	files=$(jq -Rnc '[inputs]' "$tmp/files")
	output files "$files"
}

main "$@"
