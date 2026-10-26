# Contributing

How a plugin of this catalog is made, checked, and tested. The plugin in
[`examples/file`](examples/file) shows each part: to start, copy it to
`plugins/<name>/`, and its test to `tests/<name>/`, with the path of the
plugin in the test changed.

## Kinds of plugins

Start with the smallest kind that does the work:

| Kind | What it is | Example |
|---|---|---|
| Without a script | tasks run a program as argv, with `${{ inputs.<name> }}` in its items; an output reads its stdout | below |
| A script | `run: [./<name>.sh, <task>]`, a POSIX sh script that loads `lib/opstruss.sh` | [`examples/file`](examples/file), [`plugins/compose`](plugins/compose) |
| A script with an exact plan | its plan gives a digest of what `up` would apply, and `up` checks it | [`examples/file`](examples/file), [`plugins/tofu`](plugins/tofu) |
| Compiled | a Go program that the plugin ships through `bin:`, once a script is not enough | none yet |

A plugin without a script:

```yaml
name: greet
inputs:
  name: {type: string, default: world}
outputs:
  greeting: {type: string, from: stdout}
tasks:
  up:
    run: [printf, "hello, %s", "${{ inputs.name }}"]
```

Each item of `run` is one argument, and no shell reads it, so an input
with `;` or `$(…)` stays text.

## How OpsTruss runs a plugin

```text
opstruss.plugin.yaml  tasks.up.run: [./file.sh, up], relative to the directory of the plugin
OpsTruss              starts it in a clean environment, in its own process group, with the contract files
file.sh               loads lib/opstruss.sh; main up calls cmd_up
cmd_up                reads the inputs, runs the tool, writes the outputs and the result
OpsTruss              reads the files back; an exit code other than 0 fails the task
```

The working directory is the directory of the file that holds the unit,
so a path in an input is relative to it. The variables and files that a
plugin uses:

| Name | What it is | Where |
|---|---|---|
| `OPSTRUSS_INPUTS` | file: the inputs as JSON, with their types; `input` reads it | every task in a run |
| `INPUT_<NAME>` | each input as text, with `-` as `_` | every task, and the only way outside a run, as in a watch hook |
| `OPSTRUSS_PLAN` | file to write: `{"changes": [{"action": "create", "resource": "web"}], "outputs": ["services"], "digest": "sha256:…", "exact": true}` | `plan` |
| `OPSTRUSS_DIGEST` | the digest of the plan that was approved | `up` |
| `OPSTRUSS_OUTPUT` | file to write: the outputs, with `output`, or as one JSON object | `up` and other tasks |
| `OPSTRUSS_RESULT` | file to write: `{"changed": false}` with `unchanged`, and `"sensitive": ["<output>"]` for outputs that the tool keeps secret | `up` and other tasks |
| `OPSTRUSS_TEMP` | the directory of the run, which goes at its end; `scratch` makes one for the call in it | every task in a run |
| `OPSTRUSS_WORKDIR` | the work directory of the unit, a cache that may be empty at any call | `plan`, `up`, `destroy`, and `exec` |
| `OPSTRUSS_STATE_KEY` | the lasting id of the unit, to name or tag what it makes, so that an `up` after a failed one finds it | every task of a unit; empty in the plan of a new unit |
| `OPSTRUSS_STATE_DIR` | where the tool keeps its own state, for `state: tool` | tasks of a unit, with the local backend |
| `OPSTRUSS_PLUGIN_DIR` | the directory of the plugin | every program of a plugin |
| `NO_COLOR` | set when the run shows no color; `color` reads it | every program |
| file descriptors 3 and up | the lock of the run and the leases, which the programs of the tool inherit | every program in a run |

And what OpsTruss makes of them:

- An empty `$OPSTRUSS_PLAN` says that the unit will run; `"changes": []`
  says that nothing changes.
- `action` is `create`, `update`, `delete`, `replace`, or `run`.
- The digest hashes what `up` would apply, not a plan file, so the same
  state and inputs give the same digest in every run.
- `"exact": true` promises that `up` applies the changes of that digest:
  `up` works them out again and fails when `approved` says no.
- A result without `changed` says that the call changed something.
- A signal ends the program with 128 and its number, as 130 for SIGINT.

## A script

[`examples/file/file.sh`](examples/file/file.sh) keeps a text file as a
unit. Every script of the catalog has the same parts, in this order:

1. A comment that says what a unit of the plugin is.
2. `. "$OPSTRUSS_PLUGIN_DIR/../../lib/opstruss.sh"`, with its `shellcheck`
   line.
3. The functions of the tool, each with a comment, such as `setup`, which
   reads the inputs and works out what `up` would do.
4. One `cmd_<task>` for each task of the manifest, in the same order.
5. `main "$@"`.

`cmd_up` of the example reads as what it does:

```sh
cmd_up() {
	setup
	approved "$digest" || fail "$path changed since its plan was approved; plan again"
	[ -z "$action" ] || cp "$want" "$path"
	sum=$(sha256 "$path")
	output sha256 "$sum"
	[ -n "$action" ] || unchanged
}
```

## Helpers

`lib/opstruss.sh` gives each part of the contract a name, and covers what
POSIX sh does poorly, as a list of arguments. Loading it sets `-eu` and
`umask 077`, and traps SIGINT and SIGTERM, so the script waits for the
tool to stop as the tool does, then ends with 130 or 143.

| Helper | Use |
|---|---|
| `input NAME` | the text of an input: a string as it is, other values as JSON |
| `input_file NAME FILE` | an input into a file, exactly, as the content of a file |
| `words NAME [PREFIX]` | a list input as lines for `run_with`; `args.plan` names a list in an object input |
| `paths NAME [PREFIX]` | a list of paths as `words` gives it, each made absolute |
| `known_keys NAME KEY…` | stop at a key of an object input that the plugin does not take |
| `run_with FILE COMMAND…` | run a tool with each line of `FILE` as one more argument |
| `scratch` | set `$tmp` to a directory for the files of the call, which goes when the script ends |
| `color` | whether the tool may print in color |
| `output NAME VALUE` | one output, which OpsTruss reads by its declared type |
| `unchanged` | say that the call changed nothing |
| `approved DIGEST` | whether `up` is about to apply the plan that was approved |
| `fail MESSAGE…` | one line to stderr, then exit 1 |
| `sha256 [FILE]` | the SHA-256 of a file, or of stdin |
| `main "$@"` | run `cmd_<task>` |

A helper joins `lib/` when it is one part of the contract, or one thing
that sh does poorly, and a plugin or the example uses it. What a plugin
does with its tool stays in the plugin: a change to `lib/` runs every unit
of every plugin again. `lib/` is not a public API; it changes with the
plugins of the catalog.

## Inputs of a plugin

A user shapes how the tool runs through the inputs of the unit:

- A typed input for what several commands, or `opstruss exec`, must read
  the same way, such as the files of the tool, its profiles, its
  variables, or how many operations run at once.
- One `args` input for anything else that the tool takes: an object with a
  list of strings for each command, which the plugin adds after its own
  arguments, with `words` and `run_with`, and checks with `known_keys`.
- The README of the plugin names the arguments that the plugin gives,
  which `args` does not give, and the commands that take no `args`, as a
  `destroy` that must remove everything.
- A path is relative to the file of the unit; `paths` makes it absolute
  for a tool that runs in another directory.
- A secret never goes in `args`: arguments are in the list of processes,
  which other users of the machine can read. It goes in a file or the
  environment of the tool.

## Rules for a script

1. No `set -x`: it prints the inputs, secrets among them, to the log.
2. A tool writes its output to a file, which jq then reads; not
   `tool | jq`. dash, the sh of Debian and Ubuntu, has no `pipefail`, so
   jq would read nothing from a tool that failed, and the script would go
   on.
3. A function that must stop the script when it fails runs on its own
   line, not in `if`, `||`, or `&&`, where sh turns `set -e` off inside
   it.
4. A `$(…)` goes into a variable before it becomes an argument:
   `cmd "$(f)"` hides the failure of `f`. `make lint` finds it.
5. A fact that is JSON stays in jq: `jq -e … || unchanged` takes an error
   of jq, as a missing file, for a call that changed nothing. Write the
   result with jq, as `plugins/compose` does.
6. Files with values, as variables or a plan file, go in `$tmp` or
   `OPSTRUSS_TEMP`, never in `OPSTRUSS_WORKDIR`, which stays after the
   run.
7. File descriptors 3 and up stay open and unused: `exec 3>&1` would put
   stdout in place of the lock of the run, which the programs of the tool
   inherit.
8. The script sets no trap: the helpers own SIGINT, SIGTERM, and EXIT.
9. The tool asks for color with a flag, when `color` says so, never
   through a variable such as `FORCE_COLOR`, which its own programs would
   get too.

## Errors

The operator sees each line of stderr after the address of the unit,
then `plan exited with 1`. A plan or an output that breaks the contract
names the field, as `$OPSTRUSS_PLAN: change 0 has action "add", not
create, update, delete, replace, or run`, or `output count: "many" is not
a number`. A message of `fail` names the thing and what to do, as `the
plan of the module changed since it was approved; plan again`.

## Tests

The tests of a package are [testscript](https://pkg.go.dev/github.com/rogpeppe/go-internal/testscript)
files in `tests/<name>/`, which run the real tool:

- Through OpsTruss: a project in the file uses the plugin as
  `./catalog/plugins/<name>` and runs `opstruss plan`, `up`, and `destroy`,
  as [`tests/examples/file.txtar`](tests/examples/file.txtar).
- The script alone, with the variables of the contract set by hand, for
  what a project cannot reach, as the stale digest of
  [`tests/tofu/digest.txtar`](tests/tofu/digest.txtar).

```sh
make lint                                  # shellcheck and actionlint
make test                                  # every test
make test TESTS=tests/tofu/digest.txtar   # one test
make test OPSTRUSS=<path>                  # another build of opstruss
```

`opstruss validate`, in a project that uses the plugin, checks its
manifest.

Before a pull request, the tests show that:

- two plans of the same unit give the same digest, and a changed input
  changes the plan;
- `up`, then `plan`, says that the unit is unchanged;
- `destroy` succeeds when the target is gone already;
- the output is plain with `NO_COLOR`;
- a secret input stays out of the log and the records;
- every program that the plugin runs is in `requires:`.

## Changes

A change that a project using the plugin can notice goes in
[`CHANGELOG.md`](CHANGELOG.md), under `[Unreleased]`, in the same commit.
