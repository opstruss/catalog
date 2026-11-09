# restic

[restic](https://restic.net/) repositories as units, and backups into
them as tasks. A unit makes the repository, so its plan shows one that
does not exist yet; the tasks `backup`, `forget`, `check`, and `restore`
work in a repository that exists, and give what restic did as outputs
that later steps read.

Needs `restic` 0.17.1 or later and `jq` 1.6 or later in `PATH`.

## Use

```yaml
uses:
  ops: github.com/opstruss/catalog@v1
  nas:
    source: ops.restic
    with:
      repository: sftp:backup@nas:/srv/restic
      password: ${{ secrets.restic }}

secrets:
  restic: {env: RESTIC_PASSWORD}

units:
  backups:
    uses: nas                    # plan: create repository; up: restic init

tasks:
  nightly:
    on: {schedule: "0 2 * * *"}
    steps:
      - id: push
        nas.backup:
          paths: [/var/backups/app.dump]
          tags: [nightly]
      - nas.forget:
          keep: {daily: 7, weekly: 4, monthly: 6}
      - nas.check: {}
```

The inputs of the plugin, in `with:` of its declaration, reach the unit
and every task. A step may give its own, as another `repository`, for one
call.

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `repository` | string | required | The repository, as `restic -r` takes it, such as `/srv/restic` or `sftp:backup@nas:/srv/restic`; a local path is relative to the file of the unit or step |
| `password` | string, sensitive | required | The password of the repository |
| `credentials` | object, sensitive | `{}` | Variables of the backend of the repository, by name, such as `AWS_ACCESS_KEY_ID`; each value is a string |
| `args` | object | `{}` | Arguments that restic gets after those of the plugin, by command: `init`, `backup`, `forget`, `check`, and `restore`, each a list of strings |

The repository, the password, and the credentials reach restic as
`RESTIC_REPOSITORY`, `RESTIC_PASSWORD`, and variables of their own, never
as arguments, which other users of the machine can read in the list of
processes.

## Arguments

`args` reaches each command after the arguments of the plugin:

```yaml
uses:
  nas:
    source: ops.restic
    with:
      repository: ./repo
      password: ${{ secrets.restic }}
      args:
        init: [--repository-version=2]
        backup: [--one-file-system]
        forget: [--group-by=host]
        check: [--read-data-subset=5%]
```

- Each item is one argument, as written: no shell reads it.
- The plugin gives `--json` to `backup` and `forget`, the flags of the
  inputs of each task, and `--target` to `restore`; the paths of `backup`
  and the snapshot of `restore` come last, after `--`.
- A key of `args` that the plugin does not take, as a typo, stops
  `validate`.

## Outputs

| Name | Type | Description |
|---|---|---|
| `id` | string | The id of the repository |

## Tasks

| Task | What it does |
|---|---|
| `plan` | `create repository` where `restic cat config` finds none, nothing where it finds one |
| `up` | `restic init` where the repository does not exist |
| `status` | the latest snapshot of each host and set of paths, from `restic snapshots --latest 1` |
| `backup` | `restic backup` of `paths` into a new snapshot |
| `forget` | `restic forget` of the snapshots that `keep` does not keep, with `--prune` |
| `check` | `restic check` |
| `restore` | `restic restore` of a snapshot into a directory |

The unit has no `destroy`: snapshots cannot be made again, so `opstruss
destroy` forgets the unit and leaves the repository. Remove one that is
no longer needed with the tools of its backend, as `rm -rf` of a local
directory.

### backup

| Input | Type | Default | Description |
|---|---|---|---|
| `paths` | list of strings | required | The files and directories to back up, relative to the file of the step |
| `tags` | list of strings | `[]` | Tags of the snapshot |
| `exclude` | list of strings | `[]` | Patterns of what to leave out, as `restic backup --exclude` takes them |

| Output | Type | Description |
|---|---|---|
| `snapshot` | string | The id of the new snapshot |
| `added_bytes` | integer | How many bytes of new data the snapshot added to the repository, before compression |
| `processed_bytes` | integer | How many bytes the backup read |

A file that restic cannot read, as one without permission, leaves the
snapshot without it: the task gives the snapshot and fails, so a backup
with a gap never passes as a whole one. `continue_on_error: true` on the
step lets the next steps run and read the snapshot.

A repository that does not exist fails the task, and the task never
makes one, so a typo in `repository` cannot start an empty repository
beside the real one.

### forget

| Input | Type | Default | Description |
|---|---|---|---|
| `keep` | object | required | How many snapshots to keep, by the keys `last`, `hourly`, `daily`, `weekly`, `monthly`, and `yearly`, as the `--keep-<key>` flags of `restic forget`; `-1` keeps all |
| `prune` | boolean | `true` | Remove the data that only the forgotten snapshots use |

| Output | Type | Description |
|---|---|---|
| `removed` | integer | How many snapshots forget removed |

Another key in `keep`, as a typo, stops `validate`.

### check

No inputs of its own; `args.check` gives the others, as
`--read-data-subset`. The task fails where restic finds an error.

### restore

| Input | Type | Default | Description |
|---|---|---|---|
| `snapshot` | string | `latest` | The snapshot, by id or as `latest` |
| `target` | string | the artifacts of the run | The directory to restore into, relative to the file of the step |
| `include` | list of strings | `[]` | Patterns of what to restore, as `restic restore --include` takes them; everything without one |

| Output | Type | Description |
|---|---|---|
| `dir` | string | The directory that holds what was restored |

restic writes the paths of the snapshot as they were, from the root:
`/srv/app` becomes `<target>/srv/app`.

## Credentials

A backend reads its credentials from variables, as `AWS_ACCESS_KEY_ID` and
`AWS_SECRET_ACCESS_KEY` for S3, or `B2_ACCOUNT_ID` and `B2_ACCOUNT_KEY` for
B2. `credentials` gives them to restic alone, and to each call its own,
so one step with `for_each` reaches repositories on different backends:

```yaml
secrets:
  backup: {sops: secrets/backup.yaml}   # password and credentials, by place
tasks:
  offsite:
    steps:
      - for_each:
          s3: s3:s3.amazonaws.com/acme-backup
          b2: b2:acme-backup:app
        nas.backup:
          repository: ${{ each.value }}
          password: ${{ secrets.backup[each.key].password }}
          credentials: ${{ secrets.backup[each.key].credentials }}
          paths: [/var/backups]
```

A name in `credentials` is capital letters, digits, and `_`; one of
`RESTIC_REPOSITORY…` or `RESTIC_PASSWORD…` stops the call, since the
inputs `repository` and `password` give them. A variable of the operator,
as `AWS_PROFILE` with `~/.aws/credentials`, reaches restic through `pass:`
of the declaration instead.

restic keeps its cache under `HOME`, as `~/.cache/restic` on Linux.
