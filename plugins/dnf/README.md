# dnf

Fedora, RHEL, Rocky, Alma, Amazon Linux 2023, and other RPM packages as
units, through `dnf`. `opstruss up` installs what the unit lists and rpm
lacks, and `destroy` removes only
what the unit installed itself: a package that was there before the unit
stays when the unit goes.

`up` and `destroy` run as root through sudo, which the unit allows with
`sudo: true`; `plan` and `status` read what rpm has as the operator, so
`opstruss plan` asks for no password. At a terminal, `up` and `destroy`
show the progress of dnf as it draws it there.

Needs `dnf`, 4 or 5, `rpm`, and `jq` 1.6 or later in `PATH`, and `sudo`
unless OpsTruss runs as root. `dnf` names the `yum` of RHEL 8 and later
too; `microdnf`, as in minimal images, is not `dnf`.

## Use

```yaml
uses:
  ops: github.com/opstruss/catalog@v1

units:
  tools:
    uses: ops.dnf
    sudo: true
    with:
      packages: [git, curl, fd-find]
```

Without `sudo: true` on the unit, `validate` stops with what asks for it.
OpsTruss asks for the password of sudo once a run, when the first program
that needs it starts, unless sudo needs none; a run without a terminal,
as in CI, needs sudo without a password for `opstruss __sudo`. See
[Run as root](https://opstruss.github.io/v1.0/guides/run-as-root).

For packages that have other names in brew or apt, the component
[`packages`](../../components/packages) picks the package manager of the
machine.

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `packages` | list of strings | `[]` | The packages of the unit, by name, as `name.arch` for another architecture |
| `args` | object | `{}` | Arguments that `dnf` gets after those of the plugin, by command: `install` and `remove`, each a list of strings |

A name is the name of a package, as `rpm -qa --qf '%{NAME}'` prints it:
letters, digits, `+`, `-`, `_`, and `.`. A group, a module, a file, and a
version, as `@development-tools` or `/usr/bin/git`, are not names, since
rpm never has them.

## Arguments

`args` reaches `dnf install` and `dnf remove` after the arguments of the
plugin and before the names:

```yaml
units:
  tools:
    uses: ops.dnf
    sudo: true
    with:
      packages: [git]
      args:
        install: [--setopt=install_weak_deps=False]
```

- Each item is one argument, as written: no shell reads it.
- The plugin gives `-y`.
- dnf installs the weak dependencies of a package, as it does without
  OpsTruss; `--setopt=install_weak_deps=False` above leaves them out.
- A key of `args` that the plugin does not take, as a typo, stops
  `validate`.

## Outputs

| Name | Type | Description |
|---|---|---|
| `installed` | object | What the unit installed itself, as the list `packages`; `destroy` removes only these |
| `versions` | object | The version and release of each package of the unit that rpm has, `null` for one that it lacks |

## Tasks

| Task | What it does |
|---|---|
| `plan` | `create package.<name>` for each one that rpm lacks, and `delete` for each one that the unit installed and no longer lists |
| `up` | `dnf install`, then `dnf remove` for what the unit no longer lists; dnf refreshes its metadata as it needs |
| `destroy` | `dnf remove` for what the unit installed and rpm still has |
| `status` | the version of each package of the unit, and whether the unit installed it |

The plan is not exact: dnf installs the dependencies of a package too,
and the version that it installs is known only then. A package removed
outside OpsTruss is a `create` in the next plan.

## What the unit owns

The output `installed` is the list of what the unit owns. `up` adds to it
what it is about to install before dnf starts, so what an `up` that
fails or stops part way installed stays the unit's own: the next `up`
takes it over, and `destroy` removes it. A name dropped from the list is
removed only when the unit installed it.

dnf also removes the dependencies that only the removed packages needed,
as its `clean_requirements_on_remove` says, and keeps a config file that
was changed as `.rpmsave`. A Ctrl-C gives dnf five minutes to stop before
OpsTruss kills it, since an rpm transaction cut short leaves the database
to repair.

The state of a unit belongs to the machine that it ran on: `up` of the
same stack from another machine installs what that machine lacks, under
the same record, so a stack of packages is meant for one machine.
