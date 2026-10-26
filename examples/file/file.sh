#!/bin/sh
# A text file as a unit: plan compares the file with the content of the
# unit, up writes it, and destroy removes it. CONTRIBUTING.md, at the root
# of the catalog, walks through this plugin.
#
# shellcheck source-path=SCRIPTDIR source=../../lib/opstruss.sh
. "$OPSTRUSS_PLUGIN_DIR/../../lib/opstruss.sh"

# setup reads the inputs and sets path; want, a file with the content that
# the unit asks for, in $tmp, which ends with the call; action, what up
# would do; and digest, the hash of that.
setup() {
	path=$(input path)
	scratch
	want=$tmp/want
	input_file content "$want"
	if [ ! -f "$path" ]; then
		action=create
	elif cmp -s "$want" "$path"; then
		action=
	else
		action=update
	fi
	jq -nS --arg action "$action" --arg path "$path" --rawfile content "$want" \
		'{$action, $path, $content}' >"$tmp/apply.json"
	digest=sha256:$(sha256 "$tmp/apply.json")
}

cmd_plan() {
	setup
	jq -n --arg action "$action" --arg path "$path" --arg digest "$digest" '{
		changes: (if $action == "" then [] else [{action: $action, resource: $path}] end),
		outputs: (if $action == "" then [] else ["sha256"] end),
		digest: $digest,
		exact: true
	}' >"$OPSTRUSS_PLAN"
}

cmd_up() {
	setup
	approved "$digest" || fail "$path changed since its plan was approved; plan again"
	[ -z "$action" ] || cp "$want" "$path"
	sum=$(sha256 "$path")
	output sha256 "$sum"
	[ -n "$action" ] || unchanged
}

cmd_destroy() {
	path=$(input path)
	rm -f "$path"
}

cmd_status() {
	path=$(input path)
	if [ -f "$path" ]; then
		wc -c "$path"
	else
		echo "no file yet"
	fi
}

main "$@"
