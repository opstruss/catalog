# ansible

[Ansible](https://docs.ansible.com/) playbooks as units. `opstruss plan`
runs the playbook in check mode and lists each host that it would
change; `opstruss up` runs it. The data of `set_stats` become the outputs
of the unit, with their types, for the units after it.

Needs `ansible-playbook` and `ansible-config` of ansible-core 2.16 or
later, and `jq` 1.6 or later, in `PATH`.

## Use

```yaml
uses:
  ops: github.com/opstruss/catalog@v1

units:
  hosts:
    uses: ops.ansible
    with:
      playbook: ./ansible/site.yml
      inventory: [./ansible/hosts.yml]
      vars: {wg_port: 51820}
  dns:
    uses: ops.tofu
    with:
      vars:
        addresses: ${{ units.hosts.outputs.addresses }}
```

```yaml
# ansible/site.yml
- hosts: vpn
  tasks:
    - ansible.builtin.include_role: {name: wireguard}
    - ansible.builtin.set_stats:
        data:
          addresses: "{{ {inventory_hostname: ansible_host} }}"
```

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `playbook` | string | required | The playbook, relative to the file of the unit; `ansible-playbook` runs in its directory |
| `inventory` | list of strings | `[]` | Inventory files or directories, relative to the file of the unit; that of `ansible.cfg` without one |
| `vars` | object | `{}` | Extra variables of the playbook, which win over every other variable |
| `limit` | string | none | The hosts or groups to run on, as `ansible-playbook --limit` takes them |
| `args` | object | `{}` | Arguments that `ansible-playbook` gets after those of the plugin: `playbook` for every run, `check` for the run of the plan, each a list of strings |

`vars` reach the playbook through a file, `--extra-vars @<file>`, as they
are, with their types; no shell reads them, and they are not arguments,
which other users of the machine can read in the list of processes. They
are not sensitive: a secret goes to the playbook through Ansible Vault or
a lookup of its own.

## Arguments

```yaml
units:
  hosts:
    uses: ops.ansible
    with:
      playbook: ./ansible/site.yml
      args:
        playbook: [--become, --tags=base]
        check: [--skip-tags=slow]
```

- Each item is one argument, as written: no shell reads it.
- The plugin gives `--check` and `--diff` to the run of the plan, and
  `--inventory`, `--extra-vars`, `--limit`, and the playbook to both; a
  host list, as `web1,web2,`, goes in `args.playbook` as
  `--inventory=web1,web2,`.
- A prompt, as `--ask-become-pass`, gets no keyboard; Ansible reads such a
  password from a file, as `--vault-password-file`, or from the
  inventory.
- A key of `args` that the plugin does not take, as a typo, stops
  `validate`.

## Outputs

Each key of the data of `set_stats`, as Ansible aggregates it without
`per_host`, with its type: an object, a list, a number, or a string. A
playbook that gives one value per host writes it as an object by host, as
above, so the outputs stay one object. Ansible marks no value of
`set_stats` sensitive, so a secret never goes there.

## Tasks

| Task | What it does |
|---|---|
| `plan` | `ansible-playbook --check --diff`; `update host.<name>` for each host where a task would change, and the outputs whose value would change |
| `up` | `ansible-playbook` |

- The plan reaches every host, as through SSH, on each `opstruss plan`.
- The plan is not exact: check mode skips a task that cannot run without
  changing the host, as `command` and `shell` do, so the plan does not
  show it, and `up` runs the whole playbook again.
- `up` gives the outputs also where the playbook fails part way, and
  OpsTruss keeps them as pending.
- The unit has no `destroy`: a playbook has no reverse, so `opstruss
  destroy` forgets the unit and leaves the hosts as they are. A playbook
  that undoes it runs as a task of the project.

## Configuration

`ansible-playbook` runs in the directory of the playbook, so an
`ansible.cfg` there applies, and the paths in it hold. `pass:` lets
variables of the operator through, as `ANSIBLE_CONFIG` or the credentials
of a dynamic inventory; `SSH_AUTH_SOCK` reaches Ansible without it.

The plugin reads the data of `set_stats` through a callback of its own,
`opstruss_stats.py`, the one file in Python in the catalog, since only a
callback sees that data. It runs from a copy in the temporary directory
of the run, before the callback plugins that the configuration names,
which keep running.
