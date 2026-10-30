# Changelog

Every change to the catalog that a project using its plugins or components
can notice is written down here, newest first.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
A release tag `vX.Y.Z` covers the whole catalog and `vX` moves to the
latest release of each major version; a tag `<name>-vX.Y.Z` only names the
release assets of a compiled plugin.

## [Unreleased]

### Added

- `tofu` plugin: OpenTofu root modules as units, with exact plans, the
  state of the module kept with the state of OpsTruss, or where a backend
  of the module names, the lock file of the providers in the module, and
  an `exec` hook that sets up `tofu` for the unit. The inputs
  `var_files` and `parallelism` reach every command that takes them, and
  `args` adds arguments to `init`, `plan`, and `apply`. It asks for
  every variable, so `pass:` alone says which reach the module and its
  providers.
- `compose` plugin: Docker Compose projects as units, named after their
  state key, with `logs` and `config` tasks and an `exec` hook that sets
  the files, profiles, env files, and project of the unit for
  `docker compose`. The inputs `files`, `profiles`, and `env_files` reach
  every `docker compose` of the unit, and `args` adds arguments to `up`
  and `down`. A service whose container stopped with an error, or never
  started, is an update that `up` starts again. It asks for every
  variable, so `pass:` alone says which reach Compose, and stops with
  what is missing when `docker` has no Compose v2.
- `tofu` and `compose` print in color unless OpsTruss sets `NO_COLOR`,
  which it does when it shows the output of a run without color.
- Every package on `v1` works with OpsTruss 1.0 and later, and
  `opstruss.catalog.yaml` names its level, `opstruss: "1.0"`.
