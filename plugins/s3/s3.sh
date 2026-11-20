#!/bin/sh
# s3.sh serves the backend protocol of OpsTruss on its stdin and stdout,
# one JSON-RPC message a line, over a bucket of S3: each key is an object
# under the prefix, written with If-Match or If-None-Match, and a lock is
# an object that holds its holder, made with If-None-Match: *, whose ETag
# is its token. Each operation runs one aws s3api, with its data in a
# file rather than an argument, which ps shows.
#
# It answers until its stdin ends; what aws says of an operation that
# fails is the message of the answer.

# shellcheck source-path=SCRIPTDIR source=../../lib/opstruss.sh
. "$OPSTRUSS_PLUGIN_DIR/../../lib/opstruss.sh"

# aws 2.22.5 is the first with --if-match for put-object and delete-object.
aws_version=$(aws --version 2>&1)
aws_version=${aws_version#aws-cli/}
aws_version=${aws_version%% *}
at_least "$aws_version" 2.22.5 || fail "s3 needs aws 2.22.5 or later, which has --if-match for put-object and delete-object; this is $aws_version"

tmp=$(mktemp -d "${TMPDIR:-/tmp}/opstruss-s3.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

bucket=$(input bucket)
prefix=$(input prefix)
endpoint=$(input endpoint)
[ -n "$bucket" ] || fail "s3: the input bucket is empty"
region=$(input region)
[ -z "$region" ] || export AWS_REGION="$region"
key_id=$(input access_key_id)
if [ -n "$key_id" ]; then
	AWS_ACCESS_KEY_ID=$key_id
	AWS_SECRET_ACCESS_KEY=$(input secret_access_key)
	export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
fi
session_token=$(input session_token)
[ -z "$session_token" ] || export AWS_SESSION_TOKEN="$session_token"
export AWS_PAGER=""

# The location names the endpoint by its host, port, and path: without its
# scheme, as either reaches the same storage, its userinfo, which may hold
# a credential, or a last /.
location="s3://$bucket/$prefix"
if [ -n "$endpoint" ]; then
	where=${endpoint#*://}
	host=${where%%/*}
	path=${where#"$host"}
	location="$location?endpoint=${host##*@}${path%/}"
fi

# s3 runs aws s3api with the endpoint, its stdout the result, and what it
# says of an error in $tmp/err.
s3() {
	aws s3api "$@" ${endpoint:+--endpoint-url "$endpoint"} --output json 2>"$tmp/err"
}

# answer writes the result in $tmp/result, a JSON value, as the answer of
# the request.
answer() {
	jq -c --argjson id "$id" '{jsonrpc: "2.0", id: $id, result: .}' "$tmp/result"
}

# refuse writes an error of the contract, with the code $1 and the data in
# $tmp/data, or one of aws without $1, its message the last line that aws
# wrote to stderr.
refuse() {
	msg=$(grep . "$tmp/err" | tail -n 1)
	[ -s "$tmp/data" ] || echo '{}' >"$tmp/data"
	jq -c --argjson id "$id" --arg code "$1" --arg msg "${msg:-aws s3api failed}" \
		'{jsonrpc: "2.0", id: $id, error: ({code: -32000, message: $msg} + if $code == "" then {} else {data: ({code: $code} + .)} end)}' "$tmp/data"
}

# failed names the error of the contract that aws reported, or nothing.
failed() {
	if grep -q -e '(PreconditionFailed)' -e '(ConditionalRequestConflict)' "$tmp/err"; then
		echo conflict
	elif grep -q -e '(NoSuchKey)' -e '(404)' -e 'Not Found' "$tmp/err"; then
		echo not_found
	fi
}

# put writes $tmp/body at the key $1 when its ETag is $2, or, with an empty
# $2, when there is none, and keeps the new ETag in $tmp/etag.
put() {
	if [ -n "$2" ]; then
		set -- "$1" --if-match "$2"
	else
		set -- "$1" --if-none-match '*'
	fi
	key=$1
	shift
	s3 put-object --bucket "$bucket" --key "$prefix$key" --body "$tmp/body" --content-type application/json "$@" >"$tmp/meta" &&
		jq -r .ETag "$tmp/meta" >"$tmp/etag"
}

op_initialize() {
	protocol=$(jq -r '.params.protocol' "$tmp/request")
	if [ "$protocol" != 1 ]; then
		echo "s3 speaks protocol 1, not $protocol" >"$tmp/err"
		refuse ""
		return
	fi
	jq -nc --arg location "$location" '{protocol: 1, location: $location, capabilities: {}}' >"$tmp/result"
	answer
}

op_get() {
	if ! s3 get-object --bucket "$bucket" --key "$prefix$key" "$tmp/body" >"$tmp/meta"; then
		code=$(failed)
		refuse "$code"
		return
	fi
	jq -c --rawfile data "$tmp/body" '{data: $data, etag: .ETag}' "$tmp/meta" >"$tmp/result"
	answer
}

op_put() {
	jq -j '.params.data' "$tmp/request" >"$tmp/body"
	match=$(jq -r '.params.if_match // ""' "$tmp/request")
	if ! put "$key" "$match"; then
		code=$(failed)
		refuse "$code"
		return
	fi
	jq -Rc '{etag: .}' "$tmp/etag" >"$tmp/result"
	answer
}

op_delete() {
	match=$(jq -r '.params.if_match // ""' "$tmp/request")
	if ! s3 delete-object --bucket "$bucket" --key "$prefix$key" --if-match "$match" >/dev/null; then
		code=$(failed)
		refuse "$code"
		return
	fi
	echo '{}' >"$tmp/result"
	answer
}

op_list() {
	from=$(jq -r '.params.prefix' "$tmp/request")
	if ! s3 list-objects-v2 --bucket "$bucket" --prefix "$prefix$from" --query 'Contents[].Key' >"$tmp/keys"; then
		refuse ""
		return
	fi
	jq -c --arg prefix "$prefix" '{keys: [(. // [])[] | ltrimstr($prefix)]}' "$tmp/keys" >"$tmp/result"
	answer
}

# A lock that went between the put that found it and the get of its holder
# is taken again, a few times.
op_lock() {
	# A value of its own gives each lock an ETag, its token, of its own, also
	# when the same holder takes it again.
	nonce=$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')
	jq -c --arg nonce "$nonce" '{holder: .params.holder, nonce: $nonce}' "$tmp/request" >"$tmp/lock"
	for _ in 1 2 3; do
		cp "$tmp/lock" "$tmp/body"
		if put "$key" ""; then
			jq -Rc '{token: .}' "$tmp/etag" >"$tmp/result"
			answer
			return
		fi
		code=$(failed)
		if [ "$code" != conflict ]; then
			refuse ""
			return
		fi
		if s3 get-object --bucket "$bucket" --key "$prefix$key" "$tmp/held" >"$tmp/meta"; then
			echo "$key is locked" >"$tmp/err"
			jq -c --slurpfile held "$tmp/held" '{holder: $held[0].holder, token: .ETag}' "$tmp/meta" >"$tmp/data"
			refuse locked
			return
		fi
		code=$(failed)
		if [ "$code" != not_found ]; then
			refuse ""
			return
		fi
	done
	refuse ""
}

op_unlock() {
	match=$(jq -r '.params.token' "$tmp/request")
	if ! s3 delete-object --bucket "$bucket" --key "$prefix$key" --if-match "$match" >/dev/null; then
		code=$(failed)
		refuse "$code"
		return
	fi
	echo '{}' >"$tmp/result"
	answer
}

id=null
method=
key=
while IFS= read -r line; do
	printf '%s\n' "$line" >"$tmp/request"
	fields=$(jq -r '@sh "id=\(.id | tojson) method=\(.method) key=\(.params.key // "")"' "$tmp/request")
	eval "$fields"
	: >"$tmp/err"
	: >"$tmp/data"
	case $method in
	initialize | get | put | delete | list | lock | unlock) "op_$method" ;;
	*)
		echo "s3 has no method $method" >"$tmp/err"
		msg=$(cat "$tmp/err")
		jq -nc --argjson id "$id" --arg msg "$msg" '{jsonrpc: "2.0", id: $id, error: {code: -32601, message: $msg}}'
		;;
	esac
done
