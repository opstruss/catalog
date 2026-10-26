# tofu

[OpenTofu](https://opentofu.org) root modules as units. `opstruss plan`
lists what `tofu plan` would change, `opstruss up` applies that plan, and
the outputs of the module become the outputs of the unit. Plan, apply,
and destroy print in color where OpsTruss shows color, and without it
when OpsTruss sets `NO_COLOR`.

Needs `tofu` and `jq` in `PATH`.

## Use

```yaml
uses:
  tofu: github.com/opstruss/catalog/plugins/tofu@v1

secrets:
  cloudflare: {env: CLOUDFLARE_API_TOKEN}

units:
  dns:
    uses: tofu
    with:
      dir: ./dns
      vars:
        zone: example.com
        cloudflare_api_token: ${{ secrets.cloudflare }}
```

Other units read the outputs of the module as
`${{ units.dns.outputs.<name> }}`.

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `dir` | string | `.` | The directory of the root module, relative to the file of the unit |
| `vars` | object | `{}` | Values of the variables of the module, which win over those of `var_files` |
| `var_files` | list of strings | `[]` | Files of values of the variables, `.tfvars` or `.tfvars.json`, relative to the file of the unit; a later file wins |
| `parallelism` | integer | that of tofu, 10 | How many operations tofu runs at once in `plan`, `apply`, and `destroy` |
| `args` | object | `{}` | Arguments that tofu gets after those of the plugin, by command: `init`, `plan`, and `apply`, each a list of strings |

## Arguments

The inputs shape how tofu runs. `var_files` and `parallelism` reach every
command that takes them, and `var_files` also `opstruss exec`; anything
else goes through `args`, after the arguments of the plugin:

```yaml
units:
  dns:
    uses: tofu
    with:
      dir: ./dns
      var_files: [./prod.tfvars]
      vars: {zone: example.com}
      parallelism: 4
      args:
        init: [-plugin-dir=/opt/tofu/providers]
        plan: [-refresh=false]
        apply: [-compact-warnings]
```

- Each item is one argument, as written: no shell reads it, so
  `"-var=note=a b"` keeps its space.
- tofu reads the variables in this order, and a later value wins:
  `var_files`, `vars`, then a `-var` in `args.plan`.
- The plugin gives `-chdir`, `-input`, `-state`, `-out`, the plan file of
  `apply`, `-auto-approve`, `-no-color`, and `-lockfile` for a module that
  cannot be written; `args` does not give them.
- A flag in `args.plan`, as `-target` or `-replace`, holds for every plan
  of the unit until it is removed.
- `destroy` takes no `args`: a destroy that leaves resources, as with
  `-target`, would lose them once OpsTruss removes the state of the unit.
- `args` become arguments of tofu, which other users of the machine can
  read in the list of processes: a secret goes in `vars`, which tofu reads
  from a file.
- A key of `args` that the plugin does not take, as a typo, stops `plan`
  with the key.

## Outputs

The outputs of the module, by name. Sensitive outputs stay sensitive.

## Tasks

| Task | What it does |
|---|---|
| `plan` | `tofu plan` into a plan file; the plan lists the resources and outputs that change, and is exact |
| `up` | `tofu apply` of the plan file of `plan`, or of a new plan; fails when it is not the plan that was approved |
| `destroy` | `tofu destroy` |
| `status` | `tofu state list` |
| `exec` | the program of `opstruss exec`, with tofu set up for the unit |

## Credentials

The plugin asks for no credential variables. A provider gets its
credentials from the variables of the module, as `cloudflare_api_token`
above, or from the files of its default chain under `HOME`, such as
`~/.aws/credentials`. A secret with `env:` reads a variable of the
environment, as in CI.

`TF_LOG` reaches tofu when the project passes it: `pass: [TF_LOG]`.

## State

- The state of the module is `terraform.tfstate` in the tool directory of
  the unit, which moves and locks with the state of OpsTruss, so the
  module has no backend block. Only the local backend of OpsTruss keeps it
  yet.
- The state holds the values of the module as tofu writes them, sensitive
  ones among them, in plain text.
- The work directory of the unit keeps only what `tofu init` fetches. The
  variables and the plan file live in the temporary directory of the run,
  which ends with it.

## Lock file

`.terraform.lock.hcl` belongs to the module, as in Terraform: the first
`up` writes it next to the module, and its user commits it. The units that
use the module, as the instances of a `for_each`, share it. A module that
cannot be written, as one from a remote source, needs a lock file that
covers its providers; its author makes one with `tofu providers lock`.

## exec

```sh
opstruss exec dns -- tofu state list
opstruss exec dns -- tofu plan
```

The program runs in the module with the data of the unit's `tofu init`,
and the state and the variables of the unit, from `var_files` and `vars`,
through `TF_CLI_ARGS_<command>`; `args` and `parallelism` stay with the
plan and the up of the unit. `tofu show` and `tofu state pull` take no
`-state`; the state of the unit is
`tofu show "$OPSTRUSS_STATE_DIR/terraform.tfstate"`.
