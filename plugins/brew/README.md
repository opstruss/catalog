# brew

[Homebrew](https://brew.sh/) formulae and casks as units. `opstruss up`
installs what the unit lists and Homebrew lacks, and `destroy` uninstalls
only what the unit installed itself: a formula or a cask that was there
before the unit stays when the unit goes.

At a terminal, `up` and `destroy` show the progress of Homebrew as it
draws it there. Homebrew runs as the operator, never as root.

Needs `brew` and `jq` 1.6 or later in `PATH`.

## Use

```yaml
uses:
  ops: github.com/opstruss/catalog@v1

units:
  tools:
    uses: ops.brew
    with:
      packages: [git, jq, hashicorp/tap/terraform]
      casks: [firefox]
```

For packages that have other names in apt or dnf, the component
[`packages`](../../components/packages) picks the package manager of the
machine.

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `packages` | list of strings | `[]` | The formulae of the unit, by the names that `brew list` prints; `owner/tap/name` installs one from a tap |
| `casks` | list of strings | `[]` | The casks of the unit, by the names that `brew list --cask` prints |
| `args` | object | `{}` | Arguments that `brew` gets after those of the plugin, by command: `install` and `uninstall`, each a list of strings |

The plugin reads what Homebrew has from its own directories, the Cellar
and the Caskroom, by name, so an alias never matches: list `python@3.13`,
as `brew list` prints it, not `python`. A name starts with a letter or a
digit, so none reads as an option of `brew`.

## Arguments

`args` reaches `brew install` and `brew uninstall` after `--formula` or
`--cask`, the arguments of the plugin, and before the names:

```yaml
units:
  tools:
    uses: ops.brew
    with:
      packages: [hello]
      args:
        install: [--build-from-source]
```

- Each item is one argument, as written: no shell reads it.
- `install` and `uninstall` reach the formulae and the casks alike, so an
  argument that only one takes goes in a unit of its own.
- A key of `args` that the plugin does not take, as a typo, stops
  `validate`.

## Outputs

| Name | Type | Description |
|---|---|---|
| `installed` | object | What the unit installed itself, as the lists `packages` and `casks`; `destroy` uninstalls only these |
| `versions` | object | The version of each formula of the unit that Homebrew has, `null` for one that it lacks |
| `casks` | object | The version of each cask of the unit that Homebrew has, `null` for one that it lacks |

## Tasks

| Task | What it does |
|---|---|
| `plan` | `create package.<name>` or `create cask.<name>` for each one that Homebrew lacks, and `delete` for each one that the unit installed and no longer lists |
| `up` | `brew install`, then `brew uninstall` for what the unit no longer lists |
| `destroy` | `brew uninstall` for what the unit installed and Homebrew still has |
| `status` | the version of each formula and cask of the unit, and whether the unit installed it |

The plan is not exact: Homebrew installs the dependencies of a formula
too, and the version that it installs is known only then. A formula
uninstalled outside OpsTruss is a `create` in the next plan.

## What the unit owns

The output `installed` is the list of what the unit owns. `up` adds to it
what it is about to install before Homebrew starts, so what an `up` that
fails or stops part way installed stays the unit's own: the next `up`
takes it over, and `destroy` uninstalls it. A name dropped from the list
is uninstalled only when the unit installed it.

`brew uninstall` refuses a formula that another formula needs, so
`destroy` fails until that one goes, and leaves the dependencies of what
it uninstalls, as `brew autoremove` would remove them.

The state of a unit belongs to the machine that it ran on: `up` of the
same stack from another machine installs what that machine lacks, under
the same record, so a stack of packages is meant for one machine.
