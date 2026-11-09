#!/bin/sh
# The tools of a mise configuration as a unit. plan asks mise which tools
# of the configuration are missing, so a tool removed by hand shows up;
# up installs them.
#
# The plugin never trusts a configuration, since trust lets mise run what
# the configuration holds. mise ls refuses one that is not trusted, so the
# plan stops with what mise says, before up, whose mise install would
# trust it.
#
# The unit has no destroy: the tools of mise are shared by every project
# on the machine, so destroy forgets the unit and leaves them.
#
# shellcheck source-path=SCRIPTDIR source=../../lib/opstruss.sh
. "$OPSTRUSS_PLUGIN_DIR/../../lib/opstruss.sh"

# mise 2025.11 is the oldest release that the tests of the plugin run
# with: mise 2025.6 only warns of a configuration that is not trusted and
# reads none of it, so the plan would miss its tools. MISE_OFFLINE keeps
# mise --version from asking for the latest release of mise.
mise_version=$(MISE_OFFLINE=1 mise --version)
mise_version=$(printf '%s\n' "$mise_version" | awk '{ print $1; exit }')
at_least "$mise_version" 2025.11 ||
	fail "mise needs mise 2025.11 or later; this is ${mise_version:-unknown}"

# setup moves to the directory of the configuration.
setup() {
	known_keys args install
	scratch
	dir=$(input dir)
	# A leading ~ is the home directory, as a shell reads it.
	case $dir in
	\~) dir=$HOME ;;
	\~/*) dir=$HOME/${dir#\~/} ;;
	esac
	[ -d "$dir" ] || fail "the directory $dir does not exist"
	cd "$dir" || exit
}

cmd_plan() {
	setup
	mise ls --current --missing --json >"$tmp/missing.json"
	jq '{
		changes: [to_entries[] | .key as $tool | .value[]
			| {resource: "tool.\($tool)@\(.version)", action: "create"}],
		outputs: (if length > 0 then ["tools"] else [] end),
		exact: false
	}' "$tmp/missing.json" >"$OPSTRUSS_PLAN"
}

cmd_up() {
	setup
	mise ls --current --missing --json >"$tmp/missing.json"
	missing=$(jq length "$tmp/missing.json")
	[ "$missing" != 0 ] || unchanged
	words args.install >"$tmp/install.args"
	run_with "$tmp/install.args" mise install
	mise ls --current --json >"$tmp/current.json"
	jq -c 'map_values(map(.version) | join(" "))' "$tmp/current.json" >"$tmp/tools.json"
	tools=$(cat "$tmp/tools.json")
	output tools "$tools"
}

main "$@"
