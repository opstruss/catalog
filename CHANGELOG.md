# Changelog

Every change to the catalog that a project using its plugins or components can notice is written down here, newest first.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). A release tag `vX.Y.Z` covers the whole catalog and `vX` moves to the latest release of each major version; a release candidate `vX.Y.Z-rc.N` is a pre-release of `[Unreleased]`, which `vX` names only before the first release of its major version; a tag `<name>-vX.Y.Z` only names the release assets of a compiled plugin. A release that needs a later OpsTruss or a later version of a tool says so first, under Upgrade notes.

## [Unreleased]

The first release of the catalog: 11 plugins and 1 component for OpsTruss 1.0. Each package names the oldest OpsTruss and tool versions that it takes, and stops with the version that it needs when one is older. Its README says what it does.

### Added

| Package | Kind | Units of | Needs, at least |
|---|---|---|---|
| [tofu](plugins/tofu) | plugin | OpenTofu root modules | `tofu` 1.6, `jq` 1.6 |
| [terraform](plugins/terraform) | plugin | Terraform root modules | `terraform` 1.5, `jq` 1.6 |
| [compose](plugins/compose) | plugin | Docker Compose projects | `docker` with Compose 2.23, `jq` 1.6 |
| [brew](plugins/brew) | plugin | Homebrew formulae and casks | `brew`, `jq` 1.6 |
| [apt](plugins/apt) | plugin | Debian and Ubuntu packages, as root | `apt-get`, `dpkg-query`, `jq` 1.6, `sudo` |
| [dnf](plugins/dnf) | plugin | Fedora, RHEL, and other RPM packages, as root | `dnf`, `rpm`, `jq` 1.6, `sudo` |
| [restic](plugins/restic) | plugin | restic repositories, with tasks to back up, forget, check, and restore | `restic` 0.17.1, `jq` 1.6 |
| [vault](plugins/vault) | plugin | none: its task `read` gives secrets of Vault | `vault` 1.10, `jq` 1.6 |
| [ansible](plugins/ansible) | plugin | Ansible playbooks | `ansible-playbook` and `ansible-config` of ansible-core 2.16, `jq` 1.6 |
| [mise](plugins/mise) | plugin | The tools of mise configurations | `mise` 2025.11, `jq` 1.6 |
| [chezmoi](plugins/chezmoi) | plugin | Dotfiles that chezmoi applies from a repository | `chezmoi` 2.40, `git`, `jq` 1.6 |
| [packages](components/packages) | component | System packages, through the package manager of the machine | the plugin `brew`, `apt`, or `dnf` |
