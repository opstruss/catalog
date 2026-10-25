#!/bin/sh
# Docker Compose projects as units. The project of a unit is named after
# its state key, so it stays when the unit moves, and down needs only that
# name, not the Compose file.
#
# shellcheck source-path=SCRIPTDIR source=../../lib/opstruss.sh
. "$OPSTRUSS_PLUGIN_DIR/../../lib/opstruss.sh"

# Compose prints color unless OpsTruss shows the output of the run without.
ansi=always
[ -z "${NO_COLOR:-}" ] || ansi=never

# workdir sets work, where a call keeps its files.
workdir() {
	if [ -n "${OPSTRUSS_WORKDIR:-}" ]; then
		work=$OPSTRUSS_WORKDIR
	else
		work=$(mktemp -d "$OPSTRUSS_TEMP/compose.XXXXXX")
	fi
}

# project prints the Compose project of the unit: its state key in the
# letters that Compose takes. A unit without a record has no state key yet.
project() {
	[ -n "${OPSTRUSS_STATE_KEY:-}" ] || return 1
	printf '%s' "$OPSTRUSS_STATE_KEY" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9_-' '-'
}

# inspect compares the services of the Compose file with the containers of
# the project, by the config hash that Compose labels each with, into
# $work/plan.json, and sets its digest.
inspect() {
	file=$(input file)
	docker compose -f "$file" config --hash '*' >"$work/want"
	: >"$work/have"
	if p=$(project); then
		docker ps -a --filter "label=com.docker.compose.project=$p" \
			--format '{{.Label "com.docker.compose.service"}} {{.Label "com.docker.compose.config-hash"}}' >"$work/have"
	fi
	jq -nS --rawfile want "$work/want" --rawfile have "$work/have" '
		def table: split("\n") | map(select(. != "") | split(" ") | {key: .[0], value: .[1]}) | from_entries;
		($want | table) as $w | ($have | table) as $h | {
			want: $w,
			changes: ([$w | keys[] | select($h[.] == null) | {action: "create", resource: .}]
				+ [$w | keys[] | select($h[.] != null and $h[.] != $w[.]) | {action: "replace", resource: .}]
				+ [$h | keys[] | select($w[.] == null) | {action: "delete", resource: .}])
		}' >"$work/plan.json"
	digest="sha256:$(sha256 "$work/plan.json")"
}

cmd_plan() {
	workdir
	inspect
	jq --arg digest "$digest" '{
		changes,
		outputs: (if any(.changes[]; .action != "replace") then ["services"] else [] end),
		digest: $digest,
		exact: false
	}' "$work/plan.json" >"$OPSTRUSS_PLAN"
}

# Without a TTY Compose prints the lines of the network twice, also with
# --progress plain; the plugin leaves the output of Compose as it is, and
# --ansi always keeps that output in lines.
cmd_up() {
	workdir
	inspect
	if [ -n "${OPSTRUSS_DIGEST:-}" ] && [ "$digest" != "$OPSTRUSS_DIGEST" ]; then
		fail "the Compose project changed since its plan was approved; plan again"
	fi
	p=$(project) || fail "the unit has no state key"
	docker compose --ansi "$ansi" -p "$p" -f "$file" up -d --wait --remove-orphans
	docker compose -p "$p" -f "$file" config --services >"$work/services"
	jq -Rn '{services: [inputs | select(. != "")]}' "$work/services" >"$OPSTRUSS_OUTPUT"
	jq '{changed: (.changes | length > 0)}' "$work/plan.json" >"$OPSTRUSS_RESULT"
}

# down takes the project down by its name, from the work directory, so the
# Compose file may be gone.
cmd_down() {
	workdir
	p=$(project) || fail "the unit has no state key"
	cd "$work" || exit
	docker compose --ansi "$ansi" -p "$p" down --remove-orphans
}

cmd_status() {
	workdir
	if p=$(project); then
		cd "$work" || exit
		docker compose --ansi "$ansi" -p "$p" ps -a
	else
		echo "no project yet"
	fi
}

cmd_logs() {
	workdir
	p=$(project) || fail "the unit has no state key"
	follow=$(input follow)
	cd "$work" || exit
	if [ "$follow" = true ]; then
		exec docker compose --ansi "$ansi" -p "$p" logs --follow
	fi
	exec docker compose --ansi "$ansi" -p "$p" logs
}

cmd_config() {
	file=$(input file)
	exec docker compose --ansi "$ansi" -f "$file" config
}

# exec runs the program of opstruss exec with Compose set to the file and
# the project of the unit, as docker compose ps. A unit without a record
# has no project yet, so Compose names it after the directory.
cmd_exec() {
	[ $# -gt 0 ] || fail "usage: opstruss exec <unit> -- <program> [argument...]"
	file=$(input file)
	case $file in
	/*) COMPOSE_FILE=$file ;;
	*) COMPOSE_FILE=$PWD/$file ;;
	esac
	export COMPOSE_FILE
	if p=$(project); then
		COMPOSE_PROJECT_NAME=$p
		export COMPOSE_PROJECT_NAME
	else
		echo "the unit has no record yet, so Compose names its project after the directory" >&2
	fi
	exec "$@"
}

main "$@"
