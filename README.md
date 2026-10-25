# OpsTruss catalog

Official plugins and components for
[OpsTruss](https://github.com/opstruss/opstruss).

## Plugins

| Plugin | Units of |
|---|---|
| [tofu](plugins/tofu) | OpenTofu root modules |
| [compose](plugins/compose) | Docker Compose projects |

## Use

A project declares a package in `uses:`, by its path in this repository and
a Git ref:

```yaml
uses:
  <name>: github.com/opstruss/catalog/plugins/<name>@v1
```

OpsTruss pins the ref to a commit and a hash in `opstruss.lock`, and
`opstruss plugins update` moves the pin. To work on a package, use a local
checkout of this repository by path instead:

```yaml
uses:
  <name>: ../catalog/plugins/<name>
```

## Layout

| Path | Content |
|---|---|
| `plugins/<name>/` | a plugin: `opstruss.plugin.yaml` and its scripts, with the components it ships in `components/` |
| `components/<name>/` | a component that composes several plugins |
| `lib/` | helpers that the scripts of the plugins load |
| `opstruss.catalog.yaml` | marks the root of the catalog and shares `lib` |
| `tests/<name>/` | the tests of a package |

## Packages

- A package is the directory of a plugin or a component. A unit's digest
  hashes its package and the shared paths, so a change elsewhere in the
  catalog runs none of its units again, and a change in `lib/` runs all of
  them.
- Relative paths in a package, as programs in `run:`, `include` files, and
  symlink targets, lead only into the package or `lib/`. A package may use
  another package through `uses:`.
- Plugins are POSIX sh scripts with jq that load `lib/opstruss.sh`. A plugin
  is compiled only when a script is not enough, and then ships release
  binaries through `bin:`.
- `lib/` is not a public API: it changes with the plugins of the catalog.
- The tests of a package live in `tests/<name>/`, outside the package, so
  a change to a test runs none of its units again.

## Develop

`mise install` installs the tools that the scripts are checked and tested
with, opstruss among them. `make lint` checks the scripts and the
workflows. `make test` runs the
[testscript](https://pkg.go.dev/github.com/rogpeppe/go-internal/testscript)
files of `tests/` against the tools that the plugins run; the tests of
compose need a Docker daemon and are skipped without one.
`make test OPSTRUSS=<path>` tests another build of opstruss.

## License

[MIT](LICENSE)
