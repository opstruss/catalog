#!/bin/sh
# restic repositories as units, and backups into them as tasks. The unit
# makes the repository with restic init, so its plan shows a repository
# that does not exist yet, and a typo in the input repository never makes
# a new one: the tasks need one that exists.
#
# The repository and its password reach restic as RESTIC_REPOSITORY and
# RESTIC_PASSWORD, and the credentials of its backend as variables, never
# as arguments, which other users of the machine can read.
#
# The unit has no destroy: snapshots cannot be made again, so destroy
# forgets the unit and leaves the repository.
#
# restic writes its output to files, never to a pipe: a signal that stops
# the run reaches the other end of a pipe too, and restic would die on the
# closed pipe before it removes its lock from the repository.
#
# shellcheck source-path=SCRIPTDIR source=../../lib/opstruss.sh
. "$OPSTRUSS_PLUGIN_DIR/../../lib/opstruss.sh"

# restic 0.17 is the first release that ends with 10 where the repository
# does not exist, and 0.17.1 the first whose errors in JSON hold their
# message.
restic_version=$(restic version)
restic_version=$(printf '%s\n' "$restic_version" | awk '{ print $2; exit }')
at_least "$restic_version" 0.17.1 ||
	fail "restic needs restic 0.17.1 or later; this is ${restic_version:-unknown}"

# setup reads the inputs of the plugin into the environment of restic.
setup() {
	known_keys args init backup forget check restore
	scratch
	RESTIC_REPOSITORY=$(input repository)
	RESTIC_PASSWORD=$(input password)
	export RESTIC_REPOSITORY RESTIC_PASSWORD
	# jq checks the names: a range as [A-Z] in sh follows the collation of
	# the locale, where it can take small letters too.
	bad=$(jq -r '.credentials // {} | [keys[] | select(test("^[A-Z][A-Z0-9_]*$") | not)] | join(", ")' "$OPSTRUSS_INPUTS")
	[ -z "$bad" ] || fail "the input credentials has $bad, which is not the name of a variable: capital letters, digits, and _"
	bad=$(jq -r '.credentials // {} | [to_entries[] | select(.value | type != "string") | .key] | join(", ")' "$OPSTRUSS_INPUTS")
	[ -z "$bad" ] || fail "the input credentials has $bad, which is not a string"
	jq -r '.credentials // {} | keys[]' "$OPSTRUSS_INPUTS" >"$tmp/credentials"
	while IFS= read -r name; do
		case $name in
		OPSTRUSS_* | INPUT_* | RESTIC_REPOSITORY* | RESTIC_PASSWORD*)
			fail "the input credentials cannot set $name; the inputs repository and password give the repository"
			;;
		esac
		value=$(jq -r --arg name "$name" '.credentials[$name]' "$OPSTRUSS_INPUTS")
		export "$name=$value"
	done <"$tmp/credentials"
}

# missing ends the script where the repository does not exist.
missing() {
	fail "the repository does not exist; a unit that uses the plugin makes it, as restic init does"
}

# ended ends the script as restic did, with the code $1.
ended() {
	[ "$1" != 10 ] || missing
	exit "$1"
}

# exists reports whether the repository exists, with its config in
# $tmp/config. Another failure, as a wrong password, ends the script.
exists() {
	rc=0
	restic cat config >"$tmp/config" 2>"$tmp/config.err" || rc=$?
	case $rc in
	0) return 0 ;;
	10) return 1 ;;
	esac
	cat "$tmp/config.err" >&2
	exit "$rc"
}

# messages prints what restic --json wrote to stderr, a JSON object a
# line, as text.
messages() {
	jq -Rr '(fromjson? // .)
		| if type != "object" then tostring
		elif .message_type == "error" then (if .item then "\(.item): " else "" end) + .error.message
		elif .message_type == "exit_error" then .message
		else tojson end' "$1" >&2
}

# create_digest sets digest to that of making the repository, the one
# change of the unit.
create_digest() {
	printf 'create %s' "$RESTIC_REPOSITORY" >"$tmp/create"
	digest="sha256:$(sha256 "$tmp/create")"
}

cmd_plan() {
	setup
	if exists; then
		echo '{"changes": [], "outputs": [], "exact": true}' >"$OPSTRUSS_PLAN"
		return
	fi
	create_digest
	jq -n --arg digest "$digest" '{
		changes: [{resource: "repository", action: "create"}],
		outputs: ["id"],
		digest: $digest,
		exact: true
	}' >"$OPSTRUSS_PLAN"
}

# up makes the repository that the plan found missing; one that exists by
# then needs nothing.
cmd_up() {
	setup
	if ! exists; then
		create_digest
		approved "$digest" || fail "the repository of the unit changed since its plan was approved; plan again"
		words args.init >"$tmp/init.args"
		run_with "$tmp/init.args" restic init
		exists || missing
	else
		unchanged
	fi
	id=$(jq -r .id "$tmp/config")
	output id "$id"
}

cmd_status() {
	setup
	if exists; then
		restic snapshots --compact --latest 1
	else
		echo "no repository yet"
	fi
}

# backup gives the snapshot that restic made also where it could not read
# every file, with 3, and then fails: continue_on_error or if on the next
# step can take it.
cmd_backup() {
	setup
	{
		words tags --tag=
		words exclude --exclude=
		words args.backup
		echo --
		paths paths
	} >"$tmp/backup.args"
	rc=0
	run_with "$tmp/backup.args" restic backup --json >"$tmp/backup.json" 2>"$tmp/backup.err" || rc=$?
	messages "$tmp/backup.err"
	jq -c 'select(.message_type == "summary")' "$tmp/backup.json" >"$tmp/summary.json"
	if [ -s "$tmp/summary.json" ]; then
		snapshot=$(jq -r .snapshot_id "$tmp/summary.json")
		added=$(jq -r .data_added "$tmp/summary.json")
		processed=$(jq -r .total_bytes_processed "$tmp/summary.json")
		output snapshot "$snapshot"
		output added_bytes "$added"
		output processed_bytes "$processed"
		jq -r '"snapshot \(.snapshot_id[:8]) saved: \(.files_new) new, \(.files_changed) changed, and \(.files_unmodified) unmodified files; \(.data_added) bytes added"' "$tmp/summary.json"
	fi
	case $rc in
	0) ;;
	3) fail "restic could not read every file, so the snapshot lacks them" ;;
	*) ended "$rc" ;;
	esac
}

cmd_forget() {
	setup
	jq -r '.keep | to_entries[] | "--keep-\(.key)=\(.value)"' "$OPSTRUSS_INPUTS" >"$tmp/forget.args"
	prune=$(input prune)
	[ "$prune" = false ] || echo --prune >>"$tmp/forget.args"
	words args.forget >>"$tmp/forget.args"
	rc=0
	run_with "$tmp/forget.args" restic forget --json >"$tmp/forget.out" 2>"$tmp/forget.err" || rc=$?
	messages "$tmp/forget.err"
	[ "$rc" = 0 ] || ended "$rc"
	# The JSON of forget is its first line; older releases of restic print
	# what prune did after it, as text.
	sed -n 1p "$tmp/forget.out" >"$tmp/forget.json"
	sed 1d "$tmp/forget.out"
	removed=$(jq -s '[.[0][]? | (.remove // []) | length] | add // 0' "$tmp/forget.json")
	kept=$(jq -s '[.[0][]? | (.keep // []) | length] | add // 0' "$tmp/forget.json")
	output removed "$removed"
	echo "snapshots kept: $kept, removed: $removed"
}

cmd_check() {
	setup
	words args.check >"$tmp/check.args"
	run_with "$tmp/check.args" restic check || ended $?
}

# restore writes into the directory target the paths of the snapshot as
# they were, from the root: /srv/app becomes <target>/srv/app.
cmd_restore() {
	setup
	target=$(input target)
	[ -n "$target" ] || target=${OPSTRUSS_ARTIFACTS:?}/restore
	case $target in
	/*) ;;
	*) target=$PWD/${target#./} ;;
	esac
	snapshot=$(input snapshot)
	words include --include= >"$tmp/restore.args"
	words args.restore >>"$tmp/restore.args"
	printf '%s\n' -- "$snapshot" >>"$tmp/restore.args"
	run_with "$tmp/restore.args" restic restore --target "$target" || ended $?
	output dir "$target"
}

main "$@"
