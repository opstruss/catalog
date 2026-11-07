# packages

System packages through the package manager of the machine: one unit
installs the same tools on macOS with [brew](../../plugins/brew), on
Debian and Ubuntu with [apt](../../plugins/apt), and on Fedora, RHEL, and
their kin with [dnf](../../plugins/dnf). What each plugin promises holds:
`destroy` removes only what the unit installed itself.

## Use

```yaml
uses:
  ops: github.com/opstruss/catalog@v1

units:
  tools:
    uses: ops.packages
    sudo: true
    with:
      packages: [git, curl, jq]
      brew: [fd]
      apt: [fd-find]
      dnf: [fd-find]
      casks: [firefox]
```

`sudo: true` lets apt and dnf run as root, as their plugins ask; brew runs
as the operator, since Homebrew refuses root. The component asks for it on
every machine, macOS too, since `validate` reads the files, not the
machine.

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `packages` | list of strings | `[]` | Packages that have the same name in every package manager |
| `brew` | list of strings | `[]` | More formulae, for Homebrew only |
| `casks` | list of strings | `[]` | Casks, for Homebrew only |
| `apt` | list of strings | `[]` | More packages, for apt only |
| `dnf` | list of strings | `[]` | More packages, for dnf only |
| `manager` | `brew`, `apt`, or `dnf` | the one of the machine | The package manager |
| `args` | object | `{}` | The input `args` of the plugin of each package manager, by its name |

The plugins take the names as they read them: brew from its Cellar and
Caskroom, apt from dpkg, and dnf from rpm. A name that the package manager
does not take stops `plan` of its unit.

`args` reaches the plugin of the package manager by its name:

```yaml
    with:
      packages: [git]
      args:
        apt: {install: [--no-install-recommends]}
        dnf: {install: [--setopt=install_weak_deps=False]}
```

## The package manager

Without `manager`, the component picks brew on macOS, and on Linux reads
`ID` and `ID_LIKE` in `/etc/os-release`: apt for Debian, Ubuntu, and what
names them, as Mint; dnf for Fedora, RHEL, and CentOS, and what names
them, as Rocky, Alma, and Amazon Linux 2023. On another machine, as
Alpine or Arch, `up` stops with `no package manager known for this
machine; set manager to brew, apt, or dnf`.

`manager: brew` on Linux uses Homebrew there.

## Outputs

| Name | Type | Description |
|---|---|---|
| `manager` | string | The package manager of the units |
| `installed` | object | What the unit installed itself, as the list `packages`, and `casks` for brew; `destroy` removes only these |
| `versions` | object | The version of each package of the unit that the package manager has, `null` for one that it lacks |

## One machine

The record of a unit names what it installed on the machine that ran it,
and the component picks its unit by that machine. Run from a machine with
another package manager, the same stack plans to destroy the unit of the
first, as it does when `manager` changes. A stack per machine, as `laptop`
and `server`, keeps their packages apart.
