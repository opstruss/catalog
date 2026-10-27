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

## Credentials and variables

A module and its providers read variables of their own, such as
`AWS_PROFILE`, `CLOUDFLARE_API_TOKEN`, `TF_VAR_<name>`, or `TF_LOG`, so the
plugin asks for every variable, and `pass:` of the project says which
reach tofu; without `pass:`, none does. Variables in a `.env` file reach
OpsTruss through mise, with `_.file = ".env"` under `[env]` of
`mise.toml`, through direnv, with `dotenv` in `.envrc`, or through the
shell, with `set -a; . ./.env; set +a`:

```yaml
uses:
  tofu:
    source: github.com/opstruss/catalog/plugins/tofu@v1
    pass: [AWS_PROFILE, AWS_REGION, CLOUDFLARE_*, TF_VAR_*]
```

A provider also finds credentials in the files of its default chain under
`HOME`, such as `~/.aws/credentials`, and in the variables of the module,
as `cloudflare_api_token` above. Secrets of each stack come from an
encrypted file, one variable per line:

```yaml
secrets:
  infra:
    sops: secrets/${{ stack }}.env
units:
  dns:
    uses: tofu
    with: {dir: ./dns}
    env:
      CLOUDFLARE_API_TOKEN: ${{ secrets.infra.CLOUDFLARE_API_TOKEN }}
```

The record keeps a fingerprint of what a unit passes, so a plan with
another `AWS_PROFILE` stops rather than destroy in another account later.
A credential that changes every session, as `AWS_SESSION_TOKEN` from
`aws-vault exec` or OIDC in CI, would stop every plan that way; it goes
through `secrets:` and `env:` instead, and a new value runs the unit
again:

```yaml
secrets:
  aws_key: {env: AWS_ACCESS_KEY_ID}
  aws_secret: {env: AWS_SECRET_ACCESS_KEY}
  aws_session: {env: AWS_SESSION_TOKEN}
uses:
  tofu:
    source: github.com/opstruss/catalog/plugins/tofu@v1
    pass: [AWS_REGION]
    env:
      AWS_ACCESS_KEY_ID: ${{ secrets.aws_key }}
      AWS_SECRET_ACCESS_KEY: ${{ secrets.aws_secret }}
      AWS_SESSION_TOKEN: ${{ secrets.aws_session }}
```

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
