#!/bin/sh
# OpenTofu root modules as units. plan saves a plan file that up applies
# as approved, and the state of the module lives in the tool directory of
# the unit, which the local backend of OpsTruss gives.
#
# The work directory of the unit keeps only what tofu init fetches, its
# providers and modules. Files that hold values, as the variables and the
# plan file, live in OPSTRUSS_TEMP, which OpsTruss removes at the end of
# the run.
#
# The lock file of the providers, .terraform.lock.hcl, belongs to the
# module: its user commits it, and every unit that uses the module shares
# it, as Terraform workspaces share one configuration. A module that
# cannot be written, as a remote source, needs one that covers its
# providers.
#
# shellcheck source-path=SCRIPTDIR source=../../lib/opstruss.sh
. "$OPSTRUSS_PLUGIN_DIR/../../lib/opstruss.sh"

# setup reads the inputs, writes the variables, and runs tofu init with
# its data in the work directory of the unit, so the module stays as it is.
# The files of the call live in $tmp, and the plan file of the unit in
# $plans, which the plan and the up of the same run share.
setup() {
	dir=$(input dir)
	[ -d "$dir" ] || fail "the module directory $dir does not exist"
	[ -n "${OPSTRUSS_STATE_DIR:-}" ] || fail "a module keeps its state only with the local backend of OpsTruss yet"
	tmp=$(mktemp -d "$OPSTRUSS_TEMP/tofu.XXXXXX")
	trap 'rm -rf "$tmp"' EXIT
	plans=$OPSTRUSS_TEMP/tofu-plan-$(printf '%s' "$OPSTRUSS_ADDRESS" | sha256 | cut -c1-16)
	mkdir -p "$plans"
	state=$OPSTRUSS_STATE_DIR/terraform.tfstate
	vars=$tmp/vars.tfvars.json
	planfile=$plans/plan.tfplan
	# tofu prints color unless OpsTruss shows the output of the run without.
	nocolor=${NO_COLOR:+-no-color}
	TF_DATA_DIR=${OPSTRUSS_WORKDIR:-$tmp}/data
	TF_IN_AUTOMATION=1
	export TF_DATA_DIR TF_IN_AUTOMATION
	jq '.vars // {}' "$OPSTRUSS_INPUTS" >"$vars"
	lockfile=
	[ -w "$dir" ] || lockfile=-lockfile=readonly
	if ! tofu -chdir="$dir" init -input=false -no-color ${lockfile:+"$lockfile"} >"$tmp/init.log" 2>&1; then
		cat "$tmp/init.log" >&2
		[ -z "$lockfile" ] || fail "the module in $dir has no .terraform.lock.hcl that covers its providers; its author commits one, made with tofu providers lock"
		fail "tofu init failed"
	fi
}

# inspect reads the plan file into the changes that a plan of OpsTruss
# lists, in $tmp/changes.json, and their digest.
inspect() {
	tofu -chdir="$dir" show -json -no-color "$planfile" >"$tmp/plan.json"
	jq -cS '{
		resources: [.resource_changes[]? | select(.change.actions != ["no-op"] and .change.actions != ["read"])
			| {address, actions: .change.actions, after: .change.after, unknown: .change.after_unknown}],
		outputs: [.output_changes // {} | to_entries[] | select(.value.actions != ["no-op"])
			| {name: .key, actions: .value.actions, after: .value.after}]
	}' "$tmp/plan.json" >"$tmp/changes.json"
	digest="sha256:$(sha256 "$tmp/changes.json")"
}

# plan_tofu writes a new plan file.
plan_tofu() {
	tofu -chdir="$dir" plan -input=false ${nocolor:+"$nocolor"} -state="$state" -var-file="$vars" -out="$planfile"
}

cmd_plan() {
	setup
	plan_tofu
	inspect
	jq --arg digest "$digest" '
		def action:
			if . == ["create"] then "create"
			elif . == ["delete"] then "delete"
			elif length > 1 then "replace"
			else "update" end;
		{
			changes: ([.resources[] | {resource: .address, action: (.actions | action)}]
				+ [.outputs[] | {resource: ("output." + .name), action: (.actions | action)}]),
			outputs: [.outputs[].name],
			digest: $digest,
			exact: true
		}' "$tmp/changes.json" >"$OPSTRUSS_PLAN"
}

cmd_up() {
	setup
	[ -f "$planfile" ] || plan_tofu
	inspect
	if [ -n "${OPSTRUSS_DIGEST:-}" ] && [ "$digest" != "$OPSTRUSS_DIGEST" ]; then
		rm -f "$planfile"
		fail "the plan of the module changed since it was approved; plan again"
	fi
	tofu -chdir="$dir" apply -input=false ${nocolor:+"$nocolor"} -state="$state" "$planfile"
	rm -f "$planfile"
	tofu -chdir="$dir" output -json -no-color -state="$state" >"$tmp/outputs.json"
	jq 'map_values(.value)' "$tmp/outputs.json" >"$OPSTRUSS_OUTPUT"
	jq --slurpfile changes "$tmp/changes.json" '{
		changed: ($changes[0] | (.resources + .outputs) | length > 0),
		sensitive: [to_entries[] | select(.value.sensitive) | .key]
	}' "$tmp/outputs.json" >"$OPSTRUSS_RESULT"
}

cmd_down() {
	setup
	tofu -chdir="$dir" destroy -auto-approve -input=false ${nocolor:+"$nocolor"} -state="$state" -var-file="$vars"
}

cmd_status() {
	setup
	if [ -f "$state" ]; then
		tofu -chdir="$dir" state list -state="$state"
	else
		echo "no state yet"
	fi
}

# exec runs the program of opstruss exec in the module, with tofu set up
# for the unit: the data of its init, and its state and variables through
# TF_CLI_ARGS_<command> for the commands that take them. tofu show and
# tofu state pull take no -state; the state of the unit is
# tofu show "$OPSTRUSS_STATE_DIR/terraform.tfstate".
cmd_exec() {
	[ $# -gt 0 ] || fail "usage: opstruss exec <unit> -- <program> [argument...]"
	setup
	case $state$vars in
	*\'*) fail "tofu cannot read a path with ' in TF_CLI_ARGS: $state, $vars" ;;
	esac
	for c in plan apply destroy refresh import console; do
		export "TF_CLI_ARGS_$c=-state='$state' -var-file='$vars'"
	done
	for c in output taint untaint state_list state_show state_mv state_rm; do
		export "TF_CLI_ARGS_$c=-state='$state'"
	done
	unset TF_IN_AUTOMATION
	cd "$dir" || exit
	exec "$@"
}

main "$@"
