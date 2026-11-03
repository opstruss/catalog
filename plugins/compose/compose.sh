#!/bin/sh
# Docker Compose projects as units. The project of a unit is named after
# its state key, so it stays when the unit moves, and destroy needs only that
# name, not the Compose files. The input project names it instead, as for a
# project that already runs, which the unit then takes over.
#
# The files, profiles, and env files of the unit reach Compose through its
# own variables, COMPOSE_FILE, COMPOSE_PROFILES, and COMPOSE_ENV_FILES, so
# every docker compose of a call reads the same project, and so does the
# program of opstruss exec.
#
# shellcheck source-path=SCRIPTDIR source=../../lib/opstruss.sh
. "$OPSTRUSS_PLUGIN_DIR/../../lib/opstruss.sh"

# docker without its Compose plugin reads the flags of compose as its own,
# such as --hash, so say what is missing before any command. Compose 2.23
# is the first that reads COMPOSE_ENV_FILES.
compose_version=$(docker compose version --short 2>/dev/null) ||
	fail "compose needs Docker Compose 2.23 or later, the command docker compose; install the Compose plugin of Docker, such as the package docker-compose-plugin"
at_least "$compose_version" 2.23 ||
	fail "compose needs Docker Compose 2.23 or later; this is $compose_version"

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
	# Without env files, Compose would read .env of the working directory,
	# which pass: does not cover, so it gets an empty one.
	[ -n "$COMPOSE_ENV_FILES" ] || COMPOSE_ENV_FILES=/dev/null
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

# project sets p to the Compose project of the unit: the input project, or
# its state key in the letters that Compose takes, or nothing for a unit
# with neither, as one without a record yet.
project() {
	p=$(input project)
	[ -z "$p" ] || return 0
	p=$(printf '%s' "${OPSTRUSS_STATE_KEY:-}" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9_-' '-')
}

# others warns when the project of the unit has no container while its
# Compose files run as another project: up would start a second one beside
# it, with volumes of its own, where the unit could take it over. The
# label of Compose holds the absolute paths of the files, joined by commas.
# Without a Docker daemon there is nothing to warn about, and the plan of a
# new unit needs none.
others() {
	[ -s "$tmp/files" ] || return 0
	while IFS= read -r f; do
		(cd "${f%/*}" && printf '%s/%s\n' "$PWD" "${f##*/}")
	done <"$tmp/files" | paste -s -d , - >"$tmp/config-files"
	config_files=$(cat "$tmp/config-files")
	docker ps -a --filter label=com.docker.compose.oneoff=False \
		--filter "label=com.docker.compose.project.config_files=$config_files" \
		--format '{{.Label "com.docker.compose.project"}}' >"$tmp/projects" 2>/dev/null || return 0
	sort -u "$tmp/projects" | grep -vx -e "$p" >"$tmp/others" || true
	[ -s "$tmp/others" ] || return 0
	names=$(paste -s -d , "$tmp/others" | sed 's/,/, /g')
	first=$(head -n 1 "$tmp/others")
	echo "the Compose files of the unit already run as project $names, which up leaves running beside a project of its own; give the unit project: $first to take it over" >&2
}

# inspect compares the services of the Compose files with the containers
# of the project, by the config hash that Compose labels each with, into
# $tmp/plan.json, and sets its digest. A service whose container is
# created, dead, or exited is an update, which up -d starts again, also
# when it exited with 0, as a server does on docker stop. Only a service
# that another one depends on with condition service_completed_successfully,
# as a migration, ran as it should when it exited with 0, which is also
# what up --wait takes. Paused or restarting is what up -d leaves as it is.
# Containers of docker compose run are not the services.
inspect() {
	docker compose config --hash '*' >"$tmp/want"
	docker compose config --format json >"$tmp/config.json"
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
	jq -nS --rawfile want "$tmp/want" --rawfile have "$tmp/have" --slurpfile config "$tmp/config.json" '
		def rows: split("\n") | map(select(. != "") | split(" "));
		def table: map({key: .[0], value: .[1]}) | from_entries;
		($want | rows | table) as $w | ($have | rows) as $rows | ($rows | table) as $h
		| [$config[0].services[] | .depends_on // {} | to_entries[]
			| select(.value.condition == "service_completed_successfully") | .key] as $once
		| ($rows | map(select(.[2] == "created" or .[2] == "dead"
			or (.[2] == "exited" and (.[3] != "0" or (.[0] as $s | $once | index($s) | not)))) | .[0])) as $stopped
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
	[ -s "$tmp/have" ] || others
	jq --arg digest "$digest" '{
		changes,
		outputs: (if any(.changes[]; .action == "create" or .action == "delete") then ["services"] else [] end),
		digest: $digest,
		exact: false
	}' "$tmp/plan.json" >"$OPSTRUSS_PLAN"
}

# up and destroy have tty: true, so at a terminal Compose draws its
# progress there as it does without OpsTruss. Without one it prints a line
# per change, the lines of the network twice, also with --progress plain,
# which the plugin leaves as they are. With a terminal Compose does not
# stop on SIGINT, so the manifest gives it a short stop.grace.
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
# without a record or the input project has no project yet, so Compose
# names it after the directory.
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
