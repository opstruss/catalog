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
  state of the module kept with the state of OpsTruss, the lock file of
  the providers in the module, and an `exec` hook that sets up `tofu` for
  the unit.
- `compose` plugin: Docker Compose projects as units, named after their
  state key, with `logs` and `config` tasks and an `exec` hook that sets
  the file and the project of the unit for `docker compose`.
