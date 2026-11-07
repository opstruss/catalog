# apt

Debian and Ubuntu packages as units, through `apt-get`. `opstruss up`
installs what the unit lists and dpkg lacks, and `destroy` removes only
what the unit installed itself: a package that was there before the unit
stays when the unit goes.

`up` and `destroy` run as root through sudo, which the unit allows with
`sudo: true`; `plan` and `status` read what dpkg has as the operator, so
`opstruss plan` asks for no password. At a terminal, `up` and `destroy`
show the progress of apt-get as it draws it there.

Needs `apt-get`, `dpkg-query`, and `jq` 1.6 or later in `PATH`, and
`sudo` unless OpsTruss runs as root.

## Use

```yaml
uses:
  ops: github.com/opstruss/catalog@v1

units:
  tools:
    uses: ops.apt
    sudo: true
    with:
      packages: [git, curl, fd-find]
```

Without `sudo: true` on the unit, `validate` stops with what asks for it.
OpsTruss asks for the password of sudo once a run, when the first program
that needs it starts, unless sudo needs none; a run without a terminal,
as in CI, needs sudo without a password for `opstruss __sudo`. See
[Run as root](https://opstruss.github.io/v1.0/guides/run-as-root).

For packages that have other names in brew or dnf, the component
[`packages`](../../components/packages) picks the package manager of the
machine.

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `packages` | list of strings | `[]` | The packages of the unit, by name, as `name:arch` for another architecture |
| `args` | object | `{}` | Arguments that `apt-get` gets after those of the plugin, by command: `install` and `remove`, each a list of strings |

A name is a Debian package name, as `dpkg-query -W` prints it: lowercase
letters, digits, `+`, `-`, and `.`. A virtual package, a version, and a
release, as `foo=1.2` or `foo/bookworm-backports`, are not names, since
dpkg never has them; `args` gives apt-get `-t <release>` instead.

## Arguments

`args` reaches `apt-get install` and `apt-get remove` after the arguments
of the plugin and before the names:

```yaml
units:
  tools:
    uses: ops.apt
    sudo: true
    with:
      packages: [git]
      args:
        install: [--no-install-recommends]
```

- Each item is one argument, as written: no shell reads it.
- The plugin gives `-y`, `-o DPkg::Lock::Timeout=300`, which waits up to
  five minutes for unattended-upgrades to let go of dpkg, and
  `-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold`,
  so dpkg keeps a config file that was changed without asking, with
  `DEBIAN_FRONTEND=noninteractive`.
- apt-get installs the packages that a package recommends, as it does
  without OpsTruss; `--no-install-recommends` above leaves them out.
- A key of `args` that the plugin does not take, as a typo, stops
  `validate`.

## Outputs

| Name | Type | Description |
|---|---|---|
| `installed` | object | What the unit installed itself, as the list `packages`; `destroy` removes only these |
| `versions` | object | The version of each package of the unit that dpkg has, `null` for one that it lacks |

## Tasks

| Task | What it does |
|---|---|
| `plan` | `create package.<name>` for each one that dpkg lacks, and `delete` for each one that the unit installed and no longer lists |
| `up` | `apt-get update` and `apt-get install` when there is something to install, then `apt-get remove` for what the unit no longer lists |
| `destroy` | `apt-get remove` for what the unit installed and dpkg still has |
| `status` | the version of each package of the unit, and whether the unit installed it |

The plan is not exact: apt-get installs the dependencies of a package
too, and the version that it installs is known only then. A package
removed outside OpsTruss is a `create` in the next plan. A package that a
dpkg cut short left unpacked counts as missing; `apt-get install` then
says to run `dpkg --configure -a` first.

## What the unit owns

The output `installed` is the list of what the unit owns. `up` adds to it
what it is about to install before apt-get starts, so what an `up` that
fails or stops part way installed stays the unit's own: the next `up`
takes it over, and `destroy` removes it. A name dropped from the list is
removed only when the unit installed it.

`destroy` removes without purging, so the config files of a package stay,
and leaves the dependencies that came with it, which `apt-get autoremove`
removes. A Ctrl-C gives apt-get five minutes to stop before OpsTruss
kills it, since a dpkg cut short leaves packages half configured.

The state of a unit belongs to the machine that it ran on: `up` of the
same stack from another machine installs what that machine lacks, under
the same record, so a stack of packages is meant for one machine.
