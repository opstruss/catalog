#!/bin/sh
# OpenTofu root modules as units. plan saves a plan file that up applies
# as approved.
#
# The module says where its state lives. Without a backend block, or with
# backend "local" {} that names no path, the state is terraform.tfstate in
# the tool directory of the unit, which the local backend of OpsTruss
# gives. A backend that names its place, as a path or a bucket, keeps the
# state there, and OpsTruss leaves that state alone.
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

# setup reads the inputs and runs tofu init with its data in the work
# directory of the unit, so the module stays as it is. It sets dir, the
# module; state, the state file in the tool directory; owner and
# stateargs, through backend; planfile, the plan file that the plan and
# the up of the same run share; and, in $tmp, var-files, the files of the
# variables of the unit in the order that tofu reads them, and vars.args,
# the same as arguments of tofu.
setup() {
	dir=$(input dir)
	[ -d "$dir" ] || fail "the module directory $dir does not exist"
	[ -n "${OPSTRUSS_STATE_DIR:-}" ] || fail "a module keeps its state only with the local backend of OpsTruss yet"
	known_keys args init plan apply
	scratch
	printf '%s' "$OPSTRUSS_ADDRESS" >"$tmp/address"
	key=$(sha256 "$tmp/address")
	plans=$OPSTRUSS_TEMP/tofu-plan-$(printf '%.16s' "$key")
	mkdir -p "$plans"
	planfile=$plans/plan.tfplan
	state=$OPSTRUSS_STATE_DIR/terraform.tfstate
	# tofu reads var_files, then vars, so a value in vars wins. vars: null
	# gives no file, and tofu reads an empty one as no JSON.
	input_file vars "$tmp/vars.tfvars.json"
	[ -s "$tmp/vars.tfvars.json" ] || echo '{}' >"$tmp/vars.tfvars.json"
	paths var_files >"$tmp/var-files"
	printf '%s\n' "$tmp/vars.tfvars.json" >>"$tmp/var-files"
	sed 's/^/-var-file=/' "$tmp/var-files" >"$tmp/vars.args"
	parallelism=$(input parallelism)
	# tofu prints color unless OpsTruss shows the output of the run without.
	nocolor=
	color || nocolor=-no-color
	TF_DATA_DIR=${OPSTRUSS_WORKDIR:-$tmp}/data
	TF_IN_AUTOMATION=1
	export TF_DATA_DIR TF_IN_AUTOMATION
	lockfile=
	[ -w "$dir" ] || lockfile=-lockfile=readonly
	words args.init >"$tmp/init.args"
	# init writes the backend of the module in TF_DATA_DIR and keeps one
	# that the module no longer has, so each run starts without it.
	rm -f "$TF_DATA_DIR/terraform.tfstate"
	init_tofu
	backend
}

# init_tofu runs tofu init with "$@" after the arguments of the plugin,
# and the args of the unit for init last.
init_tofu() {
	if ! run_with "$tmp/init.args" tofu -chdir="$dir" init -input=false -no-color -reconfigure \
		${lockfile:+"$lockfile"} "$@" >"$tmp/init.log" 2>&1; then
		cat "$tmp/init.log" >&2
		[ -z "$lockfile" ] || fail "the module in $dir has no .terraform.lock.hcl that covers its providers; its author commits one, made with tofu providers lock"
		fail "tofu init failed"
	fi
}

# backend reads the backend of the module from what init wrote in
# TF_DATA_DIR. Without one, the state goes to the tool directory through
# -state; backend "local" {} without a path gets the tool directory as its
# path from a second init.
# A backend that names its place owns the state: owner becomes module.
backend() {
	owner=opstruss
	stateargs=
	if [ ! -f "$TF_DATA_DIR/terraform.tfstate" ]; then
		stateargs=-state=$state
		return
	fi
	kind=$(jq -r '.backend.type // ""' "$TF_DATA_DIR/terraform.tfstate")
	path=$(jq -r '.backend.config.path // ""' "$TF_DATA_DIR/terraform.tfstate")
	if [ "$kind" = local ] && [ -z "$path" ]; then
		init_tofu "-backend-config=path=$state"
		return
	fi
	owner=module
	place="backend \"$kind\"${path:+ with the path $path}"
}

# owned stops plan, up, and destroy where a module that keeps its own
# state would lose or share it: while the unit still has a state in the
# tool directory, which the module no longer reads, and in an instance,
# whose siblings would use the same place, unless args.init gives each
# its own with -backend-config.
owned() {
	[ "$owner" = module ] || return 0
	unit=${OPSTRUSS_ADDRESS#*/}
	stack=${OPSTRUSS_ADDRESS%%/*}
	[ ! -s "$state" ] || fail "the module in $dir keeps its state where its $place says, and the unit still has a state in OpsTruss, which the module does not read; move it there with: opstruss exec '$unit' --stack $stack -- tofu state push '$state', then opstruss state rm '$unit' --stack $stack --tool"
	case $unit in
	*\[*)
		grep -qE '^--?backend-config' "$tmp/init.args" ||
			fail "the module in $dir keeps its state where its $place says, and every instance of the unit would share it; leave the place out of the backend, as backend \"local\" {}, or give each instance its own with -backend-config in args.init"
		;;
	esac
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

# plan_tofu writes a new plan file, with the variables of the unit and its
# args for plan after the arguments of the plugin.
plan_tofu() {
	cp "$tmp/vars.args" "$tmp/plan.args"
	words args.plan >>"$tmp/plan.args"
	run_with "$tmp/plan.args" tofu -chdir="$dir" plan -input=false ${nocolor:+"$nocolor"} \
		${stateargs:+"$stateargs"} ${parallelism:+"-parallelism=$parallelism"} -out="$planfile"
}

cmd_plan() {
	setup
	owned
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
	owned
	[ -f "$planfile" ] || plan_tofu
	inspect
	if ! approved "$digest"; then
		rm -f "$planfile"
		fail "the plan of the module changed since it was approved; plan again"
	fi
	# The plan file comes last, after the args of the unit for apply.
	words args.apply >"$tmp/apply.args"
	printf '%s\n' "$planfile" >>"$tmp/apply.args"
	run_with "$tmp/apply.args" tofu -chdir="$dir" apply -input=false ${nocolor:+"$nocolor"} \
		${stateargs:+"$stateargs"} ${parallelism:+"-parallelism=$parallelism"}
	rm -f "$planfile"
	tofu -chdir="$dir" output -json -no-color ${stateargs:+"$stateargs"} >"$tmp/outputs.json"
	jq 'map_values(.value)' "$tmp/outputs.json" >"$OPSTRUSS_OUTPUT"
	jq --slurpfile changes "$tmp/changes.json" '{
		changed: ($changes[0] | (.resources + .outputs) | length > 0),
		sensitive: [to_entries[] | select(.value.sensitive) | .key]
	}' "$tmp/outputs.json" >"$OPSTRUSS_RESULT"
}

# destroy takes no args of the unit: a destroy that leaves resources, as
# with -target, would lose them once OpsTruss removes the state of the unit.
cmd_destroy() {
	setup
	owned
	run_with "$tmp/vars.args" tofu -chdir="$dir" destroy -auto-approve -input=false ${nocolor:+"$nocolor"} \
		${stateargs:+"$stateargs"} ${parallelism:+"-parallelism=$parallelism"}
}

cmd_status() {
	setup
	if [ "$owner" = opstruss ] && [ ! -f "$state" ]; then
		echo "no state yet"
	else
		tofu -chdir="$dir" state list ${stateargs:+"$stateargs"}
	fi
}

# exec runs the program of opstruss exec in the module, with tofu set up
# for the unit: the data of its init, with the backend of the module, and
# its variables through TF_CLI_ARGS_<command> for the commands that take
# them, which tofu splits as a shell does; without a backend block, the
# state of the unit goes there as -state too. The args of the unit stay
# with its plan and up. tofu show and tofu state pull take no -state;
# without a backend block, the state of the unit is
# tofu show "$OPSTRUSS_STATE_DIR/terraform.tfstate".
cmd_exec() {
	setup
	statearg=
	if [ -n "$stateargs" ]; then
		case $state in
		*\'*) fail "tofu cannot read a path with ' in TF_CLI_ARGS: $state" ;;
		esac
		statearg="-state='$state'"
		for c in output taint untaint state_list state_show state_mv state_rm; do
			export "TF_CLI_ARGS_$c=$statearg"
		done
	fi
	vars=
	while IFS= read -r file; do
		case $file in
		*\'*) fail "tofu cannot read a path with ' in TF_CLI_ARGS: $file" ;;
		esac
		vars="$vars -var-file='$file'"
	done <"$tmp/var-files"
	for c in plan apply destroy refresh import console; do
		export "TF_CLI_ARGS_$c=$statearg$vars"
	done
	unset TF_IN_AUTOMATION
	cd "$dir" || exit
	exec "$@"
}

main "$@"
