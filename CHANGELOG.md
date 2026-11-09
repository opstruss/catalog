# Changelog

Every change to the catalog that a project using its plugins or components
can notice is written down here, newest first.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
A release tag `vX.Y.Z` covers the whole catalog and `vX` moves to the
latest release of each major version; a release candidate `vX.Y.Z-rc.N`
is a pre-release of `[Unreleased]`, which `vX` names only before the
first release of its major version; a tag `<name>-vX.Y.Z` only names the
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
- `terraform` plugin: Terraform root modules as units, with the inputs,
  outputs, tasks, state, and lock file of the `tofu` plugin.
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
- `restic` plugin: restic repositories as units, which a plan shows
  before `restic init` makes them, with the tasks `backup`, `forget`,
  `check`, and `restore`, whose outputs, as the snapshot that a backup
  made and the bytes that it added, later steps read. The password and
  the credentials of the backend reach restic as variables, never as
  arguments. A backup that could not read a file gives its snapshot and
  fails.
- `vault` plugin: the task `read`, a source of `secrets:` that gives one
  field of a secret of the key/value engine of Vault, of version 1 or 2,
  or the whole secret as an object. The address and the token come from
  the variables that `pass:` lets through, or from `vault login`.
- `ansible` plugin: Ansible playbooks as units, whose plan runs the
  playbook in check mode and lists each host that it would change. The
  data of `set_stats` become the outputs of the unit, with their types.
  `vars` reach the playbook through a file, and the playbook runs in its
  own directory, with its `ansible.cfg` and the callbacks that it
  enables.
- `packages` component: one list of packages for the package manager of
  the machine, brew on macOS, apt or dnf by `/etc/os-release` on Linux,
  or the input `manager`, with lists and `args` for each one.
- `tofu` and `compose` print in color unless OpsTruss sets `NO_COLOR`,
  which it does when it shows the output of a run without color.
- `compose` shows the progress of Compose at a terminal, as `docker
  compose` draws it, and a line per change in CI.
- Each package names the oldest OpsTruss that it takes in its manifest,
  `opstruss: "1.0"`, and each plugin the oldest version of its tool:
  OpenTofu 1.6, Terraform 1.5, Docker Compose 2.23, restic 0.17.1, Vault
  1.10, ansible-core 2.16, and jq 1.6. An older one stops the plugin with
  the version that it needs.
