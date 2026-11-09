#!/bin/sh
# Ansible playbooks as units. plan runs the playbook in check mode, and
# each host that it would change is an update; up runs it. The data of
# set_stats, without per_host, become the outputs of the unit, with their
# types.
#
# ansible-playbook runs in the directory of the playbook, so an ansible.cfg
# there applies. The callback of the plugin, opstruss_stats.py, writes the
# stats of the run to a file. It runs from a copy in the directory of the
# call, before the callback plugins that the configuration names, which
# stay: Python would write its bytecode next to the file it loads, and a
# new file in the plugin changes the hash of the package.
#
# The plan is not exact: check mode skips a task that cannot run without
# changing the host, as command and shell do, and up runs the playbook
# again.
#
# The unit has no destroy: a playbook has no reverse, so destroy forgets
# the unit, and a playbook that undoes it runs as a task.
#
# shellcheck source-path=SCRIPTDIR source=../../lib/opstruss.sh
. "$OPSTRUSS_PLUGIN_DIR/../../lib/opstruss.sh"

# ansible-core 2.16 is the oldest release that the tests of the plugin run
# with.
ansible_version=$(ansible-playbook --version)
ansible_version=$(printf '%s\n' "$ansible_version" | sed -n '1s/.*core \([0-9][0-9.]*\).*/\1/p')
at_least "$ansible_version" 2.16 ||
	fail "ansible needs ansible-core 2.16 or later; this is ${ansible_version:-unknown}"

# setup reads the inputs into $tmp/run.args, the arguments of every run of
# the unit, moves to the directory of the playbook, and sets name, the
# playbook there, and the variables of the callback.
setup() {
	known_keys args playbook check
	scratch
	playbook=$(input playbook)
	[ -f "$playbook" ] || fail "the playbook $playbook does not exist"
	# The inventories and the variables hold for the directory of the
	# playbook too.
	paths inventory --inventory= >"$tmp/run.args"
	input_file vars "$tmp/vars.json"
	[ -s "$tmp/vars.json" ] || echo '{}' >"$tmp/vars.json"
	echo "--extra-vars=@$tmp/vars.json" >>"$tmp/run.args"
	limit=$(input limit)
	[ -z "$limit" ] || printf '%s\n' "--limit=$limit" >>"$tmp/run.args"
	words args.playbook >>"$tmp/run.args"
	name=$(basename "$playbook")
	cd "$(dirname "$playbook")" || exit
	# dump reads every callback, and warns of each that is deprecated.
	ANSIBLE_DEPRECATION_WARNINGS=false ansible-config dump --format json >"$tmp/config.json"
	mkdir "$tmp/callback"
	cp "$OPSTRUSS_PLUGIN_DIR/opstruss_stats.py" "$tmp/callback/"
	ANSIBLE_CALLBACK_PLUGINS=$(jq -r --arg dir "$tmp/callback" \
		'[$dir] + ([.[] | select(.name == "DEFAULT_CALLBACK_PLUGIN_PATH") | .value][0] // []) | join(":")' \
		"$tmp/config.json")
	OPSTRUSS_ANSIBLE_STATS=$tmp/stats.json
	export ANSIBLE_CALLBACK_PLUGINS OPSTRUSS_ANSIBLE_STATS
}

cmd_plan() {
	setup
	cp "$tmp/run.args" "$tmp/check.args"
	words args.check >>"$tmp/check.args"
	printf '%s\n' "$name" >>"$tmp/check.args"
	run_with "$tmp/check.args" ansible-playbook --check --diff
	if [ -n "${OPSTRUSS_STATE:-}" ]; then
		jq '.pending.outputs // .outputs // {}' "$OPSTRUSS_STATE"
	else
		echo '{}'
	fi >"$tmp/last.json"
	jq --slurpfile last "$tmp/last.json" '$last[0] as $last | {
		changes: [.hosts | to_entries[] | select(.value.changed > 0)
			| {resource: ("host." + .key), action: "update"}],
		outputs: [.custom | to_entries[] | select($last[.key] != .value) | .key],
		exact: false
	}' "$tmp/stats.json" >"$OPSTRUSS_PLAN"
}

# up gives the outputs of set_stats also when the playbook fails part way,
# as OpsTruss keeps them as pending.
cmd_up() {
	setup
	printf '%s\n' "$name" >>"$tmp/run.args"
	rc=0
	run_with "$tmp/run.args" ansible-playbook || rc=$?
	if [ -s "$tmp/stats.json" ]; then
		jq '.custom // {}' "$tmp/stats.json" >"$OPSTRUSS_OUTPUT"
		jq '{changed: ([.hosts[].changed] | add // 0) > 0}' "$tmp/stats.json" >"$OPSTRUSS_RESULT"
	fi
	exit "$rc"
}

main "$@"
