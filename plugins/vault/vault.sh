#!/bin/sh
# Secrets from the key/value secrets engine of Vault, as a source of
# secrets: in a project. The address and the token of Vault come from the
# variables that pass: lets through, as VAULT_ADDR and VAULT_TOKEN, or
# from the file of vault login under HOME, never from an input, which the
# project would write down.
#
# The secret goes from vault to a file of the call and from there to the
# output, never to stdout, which the log of the run keeps.
#
# shellcheck source-path=SCRIPTDIR source=../../lib/opstruss.sh
. "$OPSTRUSS_PLUGIN_DIR/../../lib/opstruss.sh"

# Vault 1.10 is the oldest release that the tests of the plugin run with.
vault_version=$(vault version)
vault_version=$(printf '%s\n' "$vault_version" | awk '{ print $2; exit }')
at_least "$vault_version" 1.10 ||
	fail "vault needs Vault 1.10 or later; this is ${vault_version:-unknown}"

# read writes the secret at path, or its field, as the output value. vault
# kv get reads both versions of the engine: version 2 answers with the
# secret under data.data, beside data.metadata, and with null for a
# version that was deleted; version 1 with the secret as data.
cmd_read() {
	scratch
	path=$(input path)
	field=$(input field)
	version=$(input version)
	set --
	[ -z "$version" ] || set -- "-version=$version"
	vault kv get -format=json "$@" -- "$path" >"$tmp/answer.json"
	jq '.data | if type == "object" and (keys == ["data", "metadata"]) then .data else . end' \
		"$tmp/answer.json" >"$tmp/secret.json"
	kind=$(jq -r type "$tmp/secret.json")
	[ "$kind" = object ] || fail "the secret $path has no data at that version; it was deleted or destroyed"
	if [ -z "$field" ]; then
		jq -c '{value: .}' "$tmp/secret.json" >"$OPSTRUSS_OUTPUT"
		return
	fi
	has=$(jq --arg field "$field" 'has($field)' "$tmp/secret.json")
	if [ "$has" != true ]; then
		fields=$(jq -r 'keys | join(", ")' "$tmp/secret.json")
		fail "the secret $path has no field $field; it has: $fields"
	fi
	jq -c --arg field "$field" '{value: .[$field]}' "$tmp/secret.json" >"$OPSTRUSS_OUTPUT"
}

main "$@"
