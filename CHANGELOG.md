# Changelog

Every change to the catalog that a project using its plugins or components
can notice is written down here, newest first.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
A release tag `vX.Y.Z` covers the whole catalog and `vX` moves to the
latest release of each major version; a tag `<name>-vX.Y.Z` only names the
release assets of a compiled plugin. A release that needs a later OpsTruss
or a later version of a tool says so first, under Upgrade notes.

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
  state key, or after the input `project`, which takes over a project that
  runs already, with `logs` and `config` tasks and an `exec` hook that sets
  the files, profiles, env files, and project of the unit for
  `docker compose`. The inputs `files`, `profiles`, and `env_files` reach
  every `docker compose` of the unit, and `args` adds arguments to `up`
  and `down`. A service whose container stopped or never started is an
  update that `up` starts again, unless it exited with 0 and another
  service waits for it to complete, as for a migration. It asks for every
  variable, so `pass:` alone says which reach Compose, and a `.env` file
  reaches it only through `env_files`.
- `brew`, `apt`, and `dnf` plugins: system packages as units, through
  Homebrew, apt-get, and dnf. A unit installs what the machine lacks, and
  `destroy` removes only what the unit installed itself, also what an
  `up` that failed installed; a package that was there before stays.
  `apt` and `dnf` run `up` and `destroy` as root, which `sudo: true` on
  the unit allows; `plan` and `status` run as the operator. `args` adds
  arguments to install and remove, as `--no-install-recommends`.
- `packages` component: one list of packages for the package manager of
  the machine, brew on macOS, apt or dnf by `/etc/os-release` on Linux,
  or the input `manager`, with lists and `args` for each one.
- `tofu` and `compose` print in color unless OpsTruss sets `NO_COLOR`,
  which it does when it shows the output of a run without color.
- `compose` shows the progress of Compose at a terminal, as `docker
  compose` draws it, and a line per change in CI.
- Each package names the oldest OpsTruss that it takes in its manifest,
  `opstruss: "1.0"`, and each plugin the oldest version of its tool:
  OpenTofu 1.6, Docker Compose 2.23, and jq 1.6. An older one stops the
  plugin with the version that it needs.
