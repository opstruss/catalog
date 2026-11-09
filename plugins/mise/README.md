# mise

The tools of a [mise](https://mise.jdx.dev/) configuration as a unit.
`opstruss plan` asks mise which tools of the configuration the machine
lacks, so a tool removed by hand shows up again, and `opstruss up`
installs them.

Needs `mise` 2025.11 or later and `jq` 1.6 or later in `PATH`.

## Use

```yaml
uses:
  ops: github.com/opstruss/catalog@v1

units:
  tools:
    uses: ops.mise
    with:
      dir: ~/.config/mise         # the global configuration, which dotfiles hold
```

The unit names no tool: the configuration does, as `mise use` writes it,
so one file stays the list of the tools.

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `dir` | string | `.` | The directory whose mise configuration names the tools, relative to the file of the unit, or under `~`; mise reads the global configuration too |
| `args` | object | `{}` | Arguments that mise gets after those of the plugin, by command: `install`, a list of strings |

## Arguments

```yaml
units:
  tools:
    uses: ops.mise
    with:
      args:
        install: [--jobs=2]
```

- Each item is one argument, as written: no shell reads it.
- A key of `args` that the plugin does not take, as a typo, stops
  `validate`.

## Outputs

| Name | Type | Description |
|---|---|---|
| `tools` | object | The version of each tool of the configuration that mise uses, by name; versions of one tool are separated by spaces |

## Tasks

| Task | What it does |
|---|---|
| `plan` | `mise ls --current --missing`; `create tool.<name>@<version>` for each tool that the machine lacks |
| `up` | `mise install` |

- The plan is not exact: `up` runs `mise install`, which installs what
  the configuration names when it runs.
- The unit has no `destroy`: every project on the machine shares the
  tools of mise, so `opstruss destroy` forgets the unit and leaves them.
  `mise uninstall` removes one.

## Trust

mise runs what a configuration holds, as its `[env]`, only once the
operator trusts it with `mise trust`. The plugin never does: the plan of
a configuration that mise does not trust stops with what mise says, so
`up`, whose `mise install` would trust it, never runs.

## Variables

The plugin asks for `MISE_*`, as `opstruss doctor` lists, and `pass:`
says which of them reach mise, as `MISE_DATA_DIR` where the tools live
elsewhere. A token for the API of GitHub, `GITHUB_TOKEN`, raises the
limit of its downloads through `pass:` too.
