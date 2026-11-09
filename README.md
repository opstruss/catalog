# OpsTruss catalog

Official plugins and components for
[OpsTruss](https://github.com/opstruss/opstruss).

## Plugins

| Plugin | Units of | Needs in `PATH`, at least |
|---|---|---|
| [tofu](plugins/tofu) | OpenTofu root modules | `tofu` 1.6, `jq` 1.6 |
| [terraform](plugins/terraform) | Terraform root modules | `terraform` 1.5, `jq` 1.6 |
| [compose](plugins/compose) | Docker Compose projects | `docker` with Compose 2.23, `jq` 1.6 |
| [brew](plugins/brew) | Homebrew formulae and casks | `brew`, `jq` 1.6 |
| [apt](plugins/apt) | Debian and Ubuntu packages, as root | `apt-get`, `dpkg-query`, `jq` 1.6, `sudo` |
| [dnf](plugins/dnf) | Fedora, RHEL, and other RPM packages, as root | `dnf`, `rpm`, `jq` 1.6, `sudo` |
| [restic](plugins/restic) | restic repositories, with tasks to back up, forget, check, and restore | `restic` 0.17.1, `jq` 1.6 |
| [vault](plugins/vault) | none: its task `read` gives secrets of Vault | `vault` 1.10, `jq` 1.6 |
| [ansible](plugins/ansible) | Ansible playbooks | `ansible-playbook` and `ansible-config` of ansible-core 2.16, `jq` 1.6 |

## Components

| Component | Units of | Uses |
|---|---|---|
| [packages](components/packages) | System packages, through the package manager of the machine | brew, apt, dnf |

## Use

A project declares the catalog once in `uses:`, with a Git ref, and names
its packages through that declaration:

```yaml
uses:
  ops: github.com/opstruss/catalog@v1
  tofu: ops.tofu          # an alias, which follows the pin of ops
units:
  web:
    uses: ops.compose
  network:
    uses: tofu
```

A package can also be declared alone, by its name:

```yaml
uses:
  <name>: github.com/opstruss/catalog/<name>@v1
```

OpsTruss pins the ref to a commit and a hash in `opstruss.lock`, and
`opstruss uses update` moves the pin. To work on a package, use a local
checkout of this repository by path instead:

```yaml
uses:
  <name>: ../catalog/plugins/<name>
```

## Versions

`v1` is the major version of this catalog, not of OpsTruss. Each release
has a tag `v1.Y.Z`, which never moves, and `v1` moves to the latest of
them. A release candidate, as `v1.0.0-rc.1`, is a pre-release whose new
packages, inputs, and outputs may still change; until `v1.0.0`, `v1`
names the latest one. `opstruss.lock` keeps the commit that a project got until
`opstruss uses update` moves it; a ref such as `@v1.2.0` names one
release, which an update does not move.

A release of `v1` adds packages, tasks, inputs, and outputs, and fixes
them. It may need a later OpsTruss, which `opstruss:` in the manifest of a
package names, or a later version of a tool, which the README of the
plugin names; its notes say so first, under Upgrade notes. On an older
OpsTruss, `opstruss uses update` stops with the version that it needs
and keeps the pins, and with an older tool the plugin stops with the
version that it needs.

What a unit does stays on `v1`: no release of it removes or renames a
package, a task, an input, or an output, changes the type, the default,
or the meaning of an input, or changes what a unit makes, as the name of
its Compose project or the place of its tofu state. Those come with `v2`,
and what they replace keeps working until then.

## Layout

| Path | Content |
|---|---|
| `plugins/<name>/` | a plugin: `opstruss.plugin.yaml` and its scripts |
| `components/<name>/` | a component, with `opstruss.yaml`, that uses the plugins of the catalog by path, as `../../plugins/apt` |
| `lib/` | helpers that the scripts of the plugins load |
| `examples/<name>/` | plugins that show how one is written, for its authors rather than for projects |
| `opstruss.catalog.yaml` | marks the root of the catalog, shares `lib`, and names the packages in `packages` |
| `tests/<name>/` | the tests of a package |

## Packages

- A package is the directory of a plugin in `plugins/` or of a component
  in `components/`, used by its name: `ops.<name>`, or
  `github.com/opstruss/catalog/<name>@v1`. A name is unique across both
  and stays for all of `v1`; a directory may move in a minor release,
  which runs the units of its package once again.
- A unit's digest
  hashes its package and the shared paths, so a change elsewhere in the
  catalog runs none of its units again, and a change in `lib/` runs all of
  them.
- Relative paths in a package, as programs in `run:`, `include` files, and
  symlink targets, lead only into the package or `lib/`. A package may use
  another package through `uses:`.
- Plugins are POSIX sh scripts with jq that load `lib/opstruss.sh`; the
  one file in another language is the callback that `ansible` gives to
  Ansible, in its Python. A plugin is compiled only when a script is not
  enough, and then ships release binaries through `bin:`.
- `lib/` is not a public API: it changes with the plugins of the catalog.
- The tests of a package live in `tests/<name>/`, outside the package, so
  a change to a test runs none of its units again.

## Develop

[CONTRIBUTING.md](CONTRIBUTING.md) shows how a plugin is written, with
the helpers of `lib/`, and how it is tested.

`mise install` installs the tools that the scripts are checked and tested
with, opstruss among them. `make lint` checks the scripts and the
workflows. `make test` runs the
[testscript](https://pkg.go.dev/github.com/rogpeppe/go-internal/testscript)
files of `tests/` against the tools that the plugins run; the tests of
compose that start containers need a Docker daemon and are skipped without
one. `make test TESTS=<file>` runs one test, and `make test OPSTRUSS=<path>`
tests another build of opstruss.

## License

[MIT](LICENSE)
