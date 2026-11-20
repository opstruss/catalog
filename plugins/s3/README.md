# s3

The state of OpsTruss in a bucket of Amazon S3, or of a storage that
speaks S3 with conditional writes and conditional deletes, so a team and
CI share the records and the locks of a stack. The plugin is a backend:
`backend:` uses it, not a unit.

Needs OpsTruss 1.1 or later, `aws` 2.22.5 or later, the first with
`--if-match` for `put-object` and `delete-object`, and `jq` 1.6 or later
in `PATH`.

## Use

```yaml
opstruss: "1.1"
name: platform

uses:
  ops: github.com/opstruss/catalog@v1

backend:
  uses: ops.s3
  with:
    bucket: acme-opstruss
    prefix: platform/
    region: ap-southeast-1
  pass: [AWS_PROFILE]
```

Then `opstruss init --stack <stack>` checks the bucket and starts the
state of the stack there; a run before it stops, so a bucket or a prefix
that is wrong never starts a second, empty copy of a stack. A project
with global units also needs `opstruss init`, for the global scope.
Another checkout of the project needs no `init`: its first command finds
the state there.

In CI, give the credentials through secrets rather than `pass:`, as they
change each session:

```yaml
secrets:
  key: {env: AWS_ACCESS_KEY_ID}
  secret: {env: AWS_SECRET_ACCESS_KEY}
  session: {env: AWS_SESSION_TOKEN}

backend:
  uses: ops.s3
  with:
    bucket: acme-opstruss
    prefix: platform/
    region: ap-southeast-1
    access_key_id: ${{ secrets.key }}
    secret_access_key: ${{ secrets.secret }}
    session_token: ${{ secrets.session }}
```

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `bucket` | string | required | The bucket that keeps the state |
| `prefix` | string | `""` | The prefix of the keys of the project in the bucket, such as `platform/`; each project has a prefix of its own |
| `region` | string | | The region of the bucket; without it, that of the profile or of `AWS_REGION` |
| `endpoint` | string | | The URL of a storage that speaks S3, in place of AWS, such as `https://s3.example.internal` |
| `access_key_id` | string, sensitive | | The access key, from a secret; without it, the credentials of the profile or of the environment of `aws` |
| `secret_access_key` | string, sensitive | | The secret of the access key, from a secret |
| `session_token` | string, sensitive | | The session token of temporary credentials, from a secret |

The plugin asks for `AWS_PROFILE` and `AWS_REGION`, which reach it when
`pass:` of the backend names them. The credentials reach `aws` as its
variables, never as arguments, and each record reaches it through a
file.

## The bucket

- Each key of the state is an object under the prefix:
  `platform/prod/web/state.json` for the unit `web` of stack `prod`.
  `opstruss state pull` reads one as it is stored.
- A record is written with `If-Match` its ETag, or `If-None-Match: *`
  when it is new, so a writer that lost its lock fails rather than
  writing over what another wrote.
- A lock is the object `state.lock` beside the record, made with
  `If-None-Match: *` and holding who holds it and a random value, so
  that its ETag, the token that lets it go through a delete with
  `If-Match`, is of that lock alone. A lock does
  not go away when its holder dies: OpsTruss takes over one whose holder
  died on the same machine, and `opstruss unlock <unit>` lets go of one
  of another machine.
- The location is `s3://<bucket>/<prefix>`, with
  `?endpoint=<host>[:<port>][/<path>]` for another storage, without the
  scheme, the userinfo, or a last `/` of `endpoint`; with the plugin, it
  names the place of the state, and a project that moves to another one
  runs `opstruss state migrate`.
- Turn on versioning in the bucket, so an earlier record can be got back.

The role of OpsTruss needs `s3:GetObject`, `s3:PutObject`, and
`s3:DeleteObject` on the objects under the prefix, and `s3:ListBucket`
on the bucket with that prefix.

## Another storage

A storage that speaks S3 needs conditional writes (`If-None-Match` and
`If-Match` on `PutObject`) and conditional deletes (`If-Match` on
`DeleteObject`). `opstruss init` and `opstruss doctor` check that with a
probe, and refuse a storage that fails one step, such as one that deletes
an object whose ETag does not match. The tests of the catalog run against
SeaweedFS 4.50.

`aws` reaches a bucket of another storage at `<bucket>.<host>` unless the
endpoint is an IP address; for one that serves buckets as paths, set
`addressing_style = path` under `s3` in the AWS profile that `AWS_PROFILE`
names.

## Speed

The plugin runs one `aws` for each operation, so a plan reads each record
in about the time that `aws` takes to start. A compiled plugin replaces
the script, with the same inputs and location, if that is too slow for a
stack of many units.
