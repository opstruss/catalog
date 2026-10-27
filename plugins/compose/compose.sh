#!/bin/sh
# Docker Compose projects as units. The project of a unit is named after
# its state key, so it stays when the unit moves, and destroy needs only that
# name, not the Compose files.
#
# The files, profiles, and env files of the unit reach Compose through its
# own variables, COMPOSE_FILE, COMPOSE_PROFILES, and COMPOSE_ENV_FILES, so
# every docker compose of a call reads the same project, and so does the
# program of opstruss exec.
#
# shellcheck source-path=SCRIPTDIR source=../../lib/opstruss.sh
. "$OPSTRUSS_PLUGIN_DIR/../../lib/opstruss.sh"

# Compose prints color unless OpsTruss shows the output of the run without.
ansi=never
if color; then
	ansi=always
fi

# setup checks the inputs, makes $tmp, and gives Compose the files,
# profiles, and env files of the unit.
setup() {
	known_keys args up down
	scratch
	paths files >"$tmp/files"
	paths env_files >"$tmp/env-files"
	words profiles >"$tmp/profiles"
	COMPOSE_FILE=$(joined "$tmp/files" : files)
	COMPOSE_ENV_FILES=$(joined "$tmp/env-files" , env_files)
	COMPOSE_PROFILES=$(joined "$tmp/profiles" , profiles)
	export COMPOSE_FILE COMPOSE_ENV_FILES COMPOSE_PROFILES
	# Without files, Compose looks for its default file, as without -f.
	[ -n "$COMPOSE_FILE" ] || unset COMPOSE_FILE
}

# joined prints the lines of the file $1 joined by $2, on which Compose
# splits the list of the input $3, so no item may hold it.
joined() {
	while IFS= read -r item; do
		case $item in
		*"$2"*) fail "Compose splits $3 on $2, which $item holds" ;;
		esac
	done <"$1"
	paste -s -d "$2" "$1"
}

# project sets p to the Compose project of the unit: its state key in the
# letters that Compose takes, or nothing for a unit without a record yet.
project() {
	p=$(printf '%s' "${OPSTRUSS_STATE_KEY:-}" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9_-' '-')
}

# inspect compares the services of the Compose files with the containers
# of the project, by the config hash that Compose labels each with, into
# $tmp/plan.json, and sets its digest. A service whose container is
# created, dead, or exited with a code other than 0 is an update, which up
# -d starts again; one that exited with 0 ran as it should, as a migration
# does, and paused or restarting is what up -d leaves as it is. Containers
# of docker compose run are not the services.
inspect() {
	docker compose config --hash '*' >"$tmp/want"
	: >"$tmp/have"
	project
	if [ -n "$p" ]; then
		docker ps -aq --filter "label=com.docker.compose.project=$p" \
			--filter "label=com.docker.compose.oneoff=False" >"$tmp/ids"
		if [ -s "$tmp/ids" ]; then
			xargs docker inspect --format '{{index .Config.Labels "com.docker.compose.service"}} {{index .Config.Labels "com.docker.compose.config-hash"}} {{.State.Status}} {{.State.ExitCode}}' \
				<"$tmp/ids" >"$tmp/have"
		fi
	fi
	jq -nS --rawfile want "$tmp/want" --rawfile have "$tmp/have" '
		def rows: split("\n") | map(select(. != "") | split(" "));
		def table: map({key: .[0], value: .[1]}) | from_entries;
		($want | rows | table) as $w | ($have | rows) as $rows | ($rows | table) as $h
		| ($rows | map(select(.[2] == "created" or .[2] == "dead" or (.[2] == "exited" and .[3] != "0")) | .[0])) as $stopped
		| {
			want: $w,
			changes: ([$w | keys[] | select($h[.] == null) | {action: "create", resource: .}]
				+ [$w | keys[] | select($h[.] != null and $h[.] != $w[.]) | {action: "replace", resource: .}]
				+ [$w | keys[] | select($h[.] == $w[.]) | select(. as $s | $stopped | index($s)) | {action: "update", resource: .}]
				+ [$h | keys[] | select($w[.] == null) | {action: "delete", resource: .}])
		}' >"$tmp/plan.json"
	digest="sha256:$(sha256 "$tmp/plan.json")"
}

cmd_plan() {
	setup
	inspect
	jq --arg digest "$digest" '{
		changes,
		outputs: (if any(.changes[]; .action == "create" or .action == "delete") then ["services"] else [] end),
		digest: $digest,
		exact: false
	}' "$tmp/plan.json" >"$OPSTRUSS_PLAN"
}

# Without a TTY Compose prints the lines of the network twice, also with
# --progress plain; the plugin leaves the output of Compose as it is, and
# --ansi always keeps that output in lines.
cmd_up() {
	setup
	inspect
	approved "$digest" || fail "the Compose project changed since its plan was approved; plan again"
	project
	[ -n "$p" ] || fail "the unit has no state key"
	words args.up >"$tmp/up.args"
	run_with "$tmp/up.args" docker compose --ansi "$ansi" -p "$p" up -d --wait --remove-orphans
	docker compose -p "$p" config --services >"$tmp/services"
	services=$(jq -cRn '[inputs | select(. != "")]' "$tmp/services")
	output services "$services"
	jq '{changed: (.changes | length > 0)}' "$tmp/plan.json" >"$OPSTRUSS_RESULT"
}

# destroy takes the project down by its name, from a directory without the
# Compose files, which may be gone.
cmd_destroy() {
	known_keys args up down
	scratch
	project
	[ -n "$p" ] || fail "the unit has no state key"
	words args.down >"$tmp/down.args"
	cd "$tmp" || exit
	run_with "$tmp/down.args" docker compose --ansi "$ansi" -p "$p" down --remove-orphans
}

cmd_status() {
	scratch
	project
	if [ -z "$p" ]; then
		echo "no project yet"
		return
	fi
	cd "$tmp" || exit
	docker compose --ansi "$ansi" -p "$p" ps -a
}

cmd_logs() {
	scratch
	project
	[ -n "$p" ] || fail "the unit has no state key"
	follow=$(input follow)
	cd "$tmp" || exit
	if [ "$follow" = true ]; then
		exec docker compose --ansi "$ansi" -p "$p" logs --follow
	fi
	exec docker compose --ansi "$ansi" -p "$p" logs
}

cmd_config() {
	setup
	exec docker compose --ansi "$ansi" config
}

# exec runs the program of opstruss exec with Compose set to the files,
# profiles, env files, and project of the unit, as docker compose ps. A unit
# without a record has no project yet, so Compose names it after the
# directory.
cmd_exec() {
	setup
	project
	if [ -n "$p" ]; then
		COMPOSE_PROJECT_NAME=$p
		export COMPOSE_PROJECT_NAME
	else
		echo "the unit has no record yet, so Compose names its project after the directory" >&2
	fi
	exec "$@"
}

main "$@"
