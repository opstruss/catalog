#!/bin/sh
# Fedora, RHEL, and other RPM packages as units, through dnf. up installs
# what the unit lists and rpm lacks. The output installed keeps what the unit
# installed itself, which is all that destroy removes, so a package that
# was there before the unit, as one that the system or another unit
# installed, stays when the unit goes.
#
# up and destroy run as root, through the sudo that the manifest asks for;
# plan and status read what rpm has as the operator.
#
# shellcheck source-path=SCRIPTDIR source=../../lib/opstruss.sh
. "$OPSTRUSS_PLUGIN_DIR/../../lib/opstruss.sh"

tab=$(printf '\t')

# inspect writes the name and the version that rpm has installed, or
# nothing, of each package of $tmp/names to $tmp/have, a line each. A name
# with an architecture, as name.arch, matches only that one.
inspect() {
	rpm -qa --qf '%{NAME}\t%{ARCH}\t%{VERSION}-%{RELEASE}\n' >"$tmp/rpm"
	jq -rn --rawfile names "$tmp/names" --rawfile rpm "$tmp/rpm" '
		[$rpm | split("\n")[] | split("\t") | select(length == 3)] as $have
		| $names | split("\n")[] | select(. != "") as $name
		| ([$have[] | select(.[0] == $name or "\(.[0]).\(.[1])" == $name) | .[2]] | first // "") as $version
		| "\($name)\t\($version)"' >"$tmp/have"
}

# setup checks the inputs, makes $tmp, and writes what up would do to
# $tmp/plan.json: the packages to install, which rpm lacks, and those to
# remove, which the unit installed and no longer lists, with the changes,
# whose digest it sets.
setup() {
	known_keys args install remove
	scratch
	last installed >"$tmp/owned.json"
	jq -r --slurpfile owned "$tmp/owned.json" '
		($owned[0] | if type == "object" then . else {} end) as $o
		| [.packages[], $o.packages[]?] | unique[]' "$OPSTRUSS_INPUTS" >"$tmp/names"
	inspect
	jq --slurpfile owned "$tmp/owned.json" --rawfile have "$tmp/have" '
		($owned[0] | if type == "object" then . else {} end) as $o
		| (reduce ($have | split("\n")[] | select(. != "") | split("\t")) as $l
			({}; .[$l[0]] = ($l[1] // ""))) as $h
		| (.packages | unique) as $want
		| ($want | map({(.): true}) | add // {}) as $w
		| {install: [$want[] | select(($h[.] // "") == "")],
			remove: [$o.packages[]? | select(($w[.] | not) and ($h[.] // "") != "")]}
		| .changes = [(.install[] | {action: "create", resource: "package.\(.)"}),
			(.remove[] | {action: "delete", resource: "package.\(.)"})]' \
		"$OPSTRUSS_INPUTS" >"$tmp/plan.json"
	jq -c .changes "$tmp/plan.json" >"$tmp/changes.json"
	digest="sha256:$(sha256 "$tmp/changes.json")"
}

# each runs dnf $1 -y with args.$1 and then the names in the file $2,
# unless it holds none.
each() {
	[ -s "$2" ] || return 0
	words "args.$1" >"$tmp/argv"
	cat "$2" >>"$tmp/argv"
	run_with "$tmp/argv" dnf "$1" -y
}

# record writes the outputs from what rpm has now: installed, what the
# unit installed itself and rpm still has, and the version of each
# package of the unit, null for one that rpm lacks.
record() {
	inspect
	jq --slurpfile owned "$tmp/owned.json" --rawfile have "$tmp/have" --slurpfile plan "$tmp/plan.json" '
		($owned[0] | if type == "object" then . else {} end) as $o
		| (reduce ($have | split("\n")[] | select(. != "") | split("\t")) as $l
			({}; .[$l[0]] = ($l[1] // ""))) as $h
		| {installed: {packages: ([$o.packages[]?, $plan[0].install[]] | unique | map(select(($h[.] // "") != "")))},
			versions: (.packages | map({(.): ($h[.] // "" | if . == "" then null else . end)}) | add // {})}' \
		"$OPSTRUSS_INPUTS" >"$tmp/outputs.json"
	for name in installed versions; do
		value=$(jq -c --arg name "$name" '.[$name]' "$tmp/outputs.json")
		output "$name" "$value"
	done
}

cmd_plan() {
	setup
	jq --arg digest "$digest" '{
		changes,
		outputs: (if (.changes | length) > 0 then ["installed", "versions"] else [] end),
		digest: $digest,
		exact: false
	}' "$tmp/plan.json" >"$OPSTRUSS_PLAN"
}

# up has tty: true, so at a terminal dnf draws its progress there. The
# output installed claims what up is about to install before dnf starts,
# so what an up that fails or stops part way installed stays the unit's
# own; the outputs at the end keep only what rpm has then. dnf refreshes
# its metadata itself.
cmd_up() {
	setup
	approved "$digest" || fail "what the unit installs changed since its plan was approved; plan again"
	claimed=$(jq -c --slurpfile owned "$tmp/owned.json" '
		($owned[0] | if type == "object" then . else {} end) as $o
		| {packages: ([$o.packages[]?, .install[]] | unique)}' "$tmp/plan.json")
	output installed "$claimed"
	jq -r '.install[]' "$tmp/plan.json" >"$tmp/install"
	jq -r '.remove[]' "$tmp/plan.json" >"$tmp/remove"
	each install "$tmp/install"
	each remove "$tmp/remove"
	record
	jq '{changed: (.changes | length > 0)}' "$tmp/plan.json" >"$OPSTRUSS_RESULT"
}

# destroy removes what the unit installed itself and rpm still has, and
# leaves everything else; dnf also removes the dependencies that only those
# packages needed, as clean_requirements_on_remove says.
cmd_destroy() {
	known_keys args install remove
	scratch
	last installed >"$tmp/owned.json"
	jq -r 'if type == "object" then .packages[]? else empty end' "$tmp/owned.json" >"$tmp/names"
	inspect
	awk -F "$tab" '$2 != "" { print $1 }' "$tmp/have" >"$tmp/remove"
	if [ ! -s "$tmp/remove" ]; then
		echo "the unit installed nothing that rpm still has"
		unchanged
		return
	fi
	each remove "$tmp/remove"
}

cmd_status() {
	scratch
	last installed >"$tmp/owned.json"
	jq -r '.packages[]' "$OPSTRUSS_INPUTS" >"$tmp/names"
	inspect
	jq -rn --slurpfile owned "$tmp/owned.json" --rawfile have "$tmp/have" '
		($owned[0] | if type == "object" then .packages // [] else [] end) as $mine
		| $have | split("\n")[] | select(. != "") | split("\t") | . as [$name, $v]
		| "package \($name): \(if ($v // "") == "" then "not installed"
			elif ($mine | any(. == $name)) then "\($v), installed by this unit" else $v end)"'
}

main "$@"
