#!/bin/sh
# Homebrew formulae and casks as units. up installs what the unit lists and
# Homebrew lacks. The output installed keeps what the unit installed
# itself, which is all that destroy uninstalls, so a formula or a cask
# that was there before the unit, as one that the user or another unit
# installed, stays when the unit goes.
#
# The plugin reads what Homebrew has from its own directories, the Cellar
# and the Caskroom, by the name of each formula and cask: an alias, as
# python for python@3.13, never matches one, so a unit lists the names
# that brew list prints. A name may carry its tap, as owner/tap/name.
#
# shellcheck source-path=SCRIPTDIR source=../../lib/opstruss.sh
. "$OPSTRUSS_PLUGIN_DIR/../../lib/opstruss.sh"

tab=$(printf '\t')

# homebrew sets where Homebrew keeps what it installed.
homebrew() {
	prefix=$(brew --prefix)
	cellar=$(brew --cellar)
	caskroom=$(brew --caskroom)
}

# version prints the version that Homebrew has of the formula or the cask
# $2, by its kind $1, package or cask, or nothing without one: for a
# formula the one that opt links, as brew uses it, and otherwise the last
# in its directory.
version() {
	if [ "$1" = package ] && [ -L "$prefix/opt/$2" ]; then
		v=$(readlink "$prefix/opt/$2")
		printf '%s\n' "${v##*/}"
		return
	fi
	dir=$cellar/$2
	[ "$1" = package ] || dir=$caskroom/$2
	v=
	for f in "$dir"/*; do
		[ ! -e "$f" ] || v=${f##*/}
	done
	printf '%s\n' "$v"
}

# inspect writes the kind, the name, and the version that Homebrew has, or
# nothing, of each formula and cask of $tmp/names to $tmp/have, a line
# each.
inspect() {
	while IFS=$tab read -r kind name; do
		v=$(version "$kind" "$name")
		printf '%s\t%s\t%s\n' "$kind" "$name" "$v"
	done <"$tmp/names" >"$tmp/have"
}

# setup checks the inputs, makes $tmp, and writes what up would do to
# $tmp/plan.json: the formulae and casks to install, which Homebrew lacks,
# and those to uninstall, which the unit installed and no longer lists,
# with the changes, whose digest it sets.
setup() {
	known_keys args install uninstall
	scratch
	homebrew
	last installed >"$tmp/owned.json"
	jq -r --slurpfile owned "$tmp/owned.json" '
		def short: split("/") | last;
		($owned[0] | if type == "object" then . else {} end) as $o
		| [(.packages[] | "package\t\(short)"), (.casks[] | "cask\t\(short)"),
			($o.packages[]? | "package\t\(.)"), ($o.casks[]? | "cask\t\(.)")]
		| unique[]' "$OPSTRUSS_INPUTS" >"$tmp/names"
	inspect
	jq --slurpfile owned "$tmp/owned.json" --rawfile have "$tmp/have" '
		def short: split("/") | last;
		($owned[0] | if type == "object" then . else {} end) as $o
		| (reduce ($have | split("\n")[] | select(. != "") | split("\t")) as $l
			({}; .[$l[0]][$l[1]] = ($l[2] // ""))) as $h
		| def install($kind; $want): [$want[] | select(($h[$kind][short] // "") == "")];
		def uninstall($kind; $mine; $want):
			($want | map({(short): true}) | add // {}) as $w
			| [$mine[]? | select(($w[.] | not) and ($h[$kind][.] // "") != "")];
		{packages: (.packages | unique), casks: (.casks | unique)} as $want
		| {install: {packages: install("package"; $want.packages), casks: install("cask"; $want.casks)},
			uninstall: {packages: uninstall("package"; $o.packages; $want.packages),
				casks: uninstall("cask"; $o.casks; $want.casks)}}
		| .changes = [(.install.packages[] | short | {action: "create", resource: "package.\(.)"}),
			(.install.casks[] | short | {action: "create", resource: "cask.\(.)"}),
			(.uninstall.packages[] | {action: "delete", resource: "package.\(.)"}),
			(.uninstall.casks[] | {action: "delete", resource: "cask.\(.)"})]' \
		"$OPSTRUSS_INPUTS" >"$tmp/plan.json"
	jq -c .changes "$tmp/plan.json" >"$tmp/changes.json"
	digest="sha256:$(sha256 "$tmp/changes.json")"
}

# each runs brew $1 --$2, for the kind formula or cask, with args.$1 and
# then the names in the file $3, unless it holds none.
each() {
	[ -s "$3" ] || return 0
	words "args.$1" >"$tmp/argv"
	cat "$3" >>"$tmp/argv"
	run_with "$tmp/argv" brew "$1" "--$2"
}

# record writes the outputs from what Homebrew has now: installed, what
# the unit installed itself and Homebrew still has, and the version of each
# formula and cask of the unit, null for one that Homebrew lacks.
record() {
	inspect
	jq --slurpfile owned "$tmp/owned.json" --rawfile have "$tmp/have" --slurpfile plan "$tmp/plan.json" '
		def short: split("/") | last;
		($owned[0] | if type == "object" then . else {} end) as $o
		| (reduce ($have | split("\n")[] | select(. != "") | split("\t")) as $l
			({}; .[$l[0]][$l[1]] = ($l[2] // ""))) as $h
		| def mine($kind; $mine; $new): [$mine[]?, ($new[] | short)] | unique | map(select(($h[$kind][.] // "") != ""));
		def versions($kind; $want): $want | map(short | {(.): ($h[$kind][.] | if . == "" then null else . end)}) | add // {};
		{installed: {packages: mine("package"; $o.packages; $plan[0].install.packages),
			casks: mine("cask"; $o.casks; $plan[0].install.casks)},
			versions: versions("package"; .packages), casks: versions("cask"; .casks)}' \
		"$OPSTRUSS_INPUTS" >"$tmp/outputs.json"
	for name in installed versions casks; do
		value=$(jq -c --arg name "$name" '.[$name]' "$tmp/outputs.json")
		output "$name" "$value"
	done
}

cmd_plan() {
	setup
	jq --arg digest "$digest" '{
		changes,
		outputs: (if (.changes | length) > 0 then ["installed", "versions", "casks"] else [] end),
		digest: $digest,
		exact: false
	}' "$tmp/plan.json" >"$OPSTRUSS_PLAN"
}

# up has tty: true, so at a terminal Homebrew draws its progress there.
# The output installed claims what up is about to install before brew
# starts, so what an up that fails or stops part way installed stays the
# unit's own; the outputs at the end keep only what Homebrew has then.
cmd_up() {
	setup
	approved "$digest" || fail "what the unit installs changed since its plan was approved; plan again"
	claimed=$(jq -c --slurpfile owned "$tmp/owned.json" '
		def short: split("/") | last;
		($owned[0] | if type == "object" then . else {} end) as $o
		| {packages: ([$o.packages[]?, (.install.packages[] | short)] | unique),
			casks: ([$o.casks[]?, (.install.casks[] | short)] | unique)}' "$tmp/plan.json")
	output installed "$claimed"
	for kind in packages casks; do
		jq -r --arg kind "$kind" '.install[$kind][]' "$tmp/plan.json" >"$tmp/install-$kind"
		jq -r --arg kind "$kind" '.uninstall[$kind][]' "$tmp/plan.json" >"$tmp/uninstall-$kind"
	done
	each install formula "$tmp/install-packages"
	each install cask "$tmp/install-casks"
	each uninstall formula "$tmp/uninstall-packages"
	each uninstall cask "$tmp/uninstall-casks"
	record
	jq '{changed: (.changes | length > 0)}' "$tmp/plan.json" >"$OPSTRUSS_RESULT"
}

# destroy uninstalls what the unit installed itself and Homebrew still
# has, and leaves everything else.
cmd_destroy() {
	known_keys args install uninstall
	scratch
	homebrew
	last installed >"$tmp/owned.json"
	jq -r 'if type == "object" then . else {} end
		| (.packages[]? | "package\t\(.)"), (.casks[]? | "cask\t\(.)")' "$tmp/owned.json" >"$tmp/names"
	inspect
	awk -F "$tab" '$1 == "package" && $3 != "" { print $2 }' "$tmp/have" >"$tmp/uninstall-packages"
	awk -F "$tab" '$1 == "cask" && $3 != "" { print $2 }' "$tmp/have" >"$tmp/uninstall-casks"
	if [ ! -s "$tmp/uninstall-packages" ] && [ ! -s "$tmp/uninstall-casks" ]; then
		echo "the unit installed nothing that Homebrew still has"
		unchanged
		return
	fi
	each uninstall formula "$tmp/uninstall-packages"
	each uninstall cask "$tmp/uninstall-casks"
}

cmd_status() {
	scratch
	homebrew
	last installed >"$tmp/owned.json"
	jq -r 'def short: split("/") | last; (.packages[] | "package\t\(short)"), (.casks[] | "cask\t\(short)")' \
		"$OPSTRUSS_INPUTS" >"$tmp/names"
	inspect
	jq -rn --slurpfile owned "$tmp/owned.json" --rawfile have "$tmp/have" '
		($owned[0] | if type == "object" then . else {} end) as $o
		| $have | split("\n")[] | select(. != "") | split("\t") | . as [$kind, $name, $v]
		| ($o[if $kind == "package" then "packages" else "casks" end] // []) as $mine
		| "\($kind) \($name): \(if ($v // "") == "" then "not installed"
			elif ($mine | any(. == $name)) then "\($v), installed by this unit" else $v end)"'
}

main "$@"
