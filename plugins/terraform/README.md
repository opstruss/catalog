# terraform

[Terraform](https://developer.hashicorp.com/terraform) root modules as
units. `opstruss plan` lists what `terraform plan` would change, `opstruss
up` applies that plan, and the outputs of the module become the outputs
of the unit. Plan, apply, and destroy print in color where OpsTruss shows
color, and without it when OpsTruss sets `NO_COLOR`.

Needs `terraform`, Terraform 1.5 or later, and `jq` 1.6 or later in
`PATH`.

## Use

```yaml
uses:
  ops: github.com/opstruss/catalog@v1

secrets:
  cloudflare: {env: CLOUDFLARE_API_TOKEN}

units:
  dns:
    uses: ops.terraform
    with:
      dir: ./dns
      vars:
        zone: example.com
        cloudflare_api_token: ${{ secrets.cloudflare }}
```

Other units read the outputs of the module as
`${{ units.dns.outputs.<name> }}`. The plugin can also be declared
alone, as `terraform: github.com/opstruss/catalog/terraform@v1`, for units
that use it as `terraform`.

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `dir` | string | `.` | The directory of the root module, relative to the file of the unit |
| `vars` | object | `{}` | Values of the variables of the module, which win over those of `var_files` |
| `var_files` | list of strings | `[]` | Files of values of the variables, `.tfvars` or `.tfvars.json`, relative to the file of the unit; a later file wins |
| `parallelism` | integer | that of terraform, 10 | How many operations terraform runs at once in `plan`, `apply`, and `destroy` |
| `args` | object | `{}` | Arguments that terraform gets after those of the plugin, by command: `init`, `plan`, and `apply`, each a list of strings |

## Arguments

The inputs shape how terraform runs. `var_files` and `parallelism` reach
every command that takes them, and `var_files` also `opstruss exec`;
anything else goes through `args`, after the arguments of the plugin:

```yaml
units:
  dns:
    uses: ops.terraform
    with:
      dir: ./dns
      var_files: [./prod.tfvars]
      vars: {zone: example.com}
      parallelism: 4
      args:
        init: [-plugin-dir=/opt/terraform/providers]
        plan: [-refresh=false]
        apply: [-compact-warnings]
```

- Each item is one argument, as written: no shell reads it, so
  `"-var=note=a b"` keeps its space.
- terraform reads the variables in this order, and a later value wins:
  `var_files`, `vars`, then a `-var` in `args.plan`.
- The plugin gives `-chdir`, `-input`, `-reconfigure`, `-state` or the
  `path` of `backend "local" {}` ([State](#state)), `-out`, the plan file
  of `apply`, `-auto-approve`, `-no-color`, and `-lockfile` for a module
  that cannot be written; `args` does not give them.
- A flag in `args.plan`, as `-target` or `-replace`, holds for every plan
  of the unit until it is removed.
- `destroy` takes no `args`: a destroy that leaves resources, as with
  `-target`, would lose them once OpsTruss removes the state of the unit.
- `args` become arguments of terraform, which other users of the machine
  can read in the list of processes: a secret goes in `vars`, which
  terraform reads from a file.
- A key of `args` that the plugin does not take, as a typo, stops `plan`
  with the key.

## Outputs

The outputs of the module, by name. Sensitive outputs stay sensitive.

## Tasks

| Task | What it does |
|---|---|
| `plan` | `terraform plan` into a plan file; the plan lists the resources and outputs that change, and is exact |
| `up` | `terraform apply` of the plan file of `plan`, or of a new plan; fails when it is not the plan that was approved |
| `destroy` | `terraform destroy` |
| `status` | `terraform state list` |
| `exec` | the program of `opstruss exec`, with terraform set up for the unit |

## Credentials and variables

A module and its providers read variables of their own, such as
`AWS_PROFILE`, `CLOUDFLARE_API_TOKEN`, `TF_VAR_<name>`, or `TF_LOG`, so
the plugin asks for every variable, and `pass:` of the project says which
reach terraform; without `pass:`, none does. Variables in a `.env` file
reach OpsTruss through mise, with `_.file = ".env"` under `[env]` of
`mise.toml`, through direnv, with `dotenv` in `.envrc`, or through the
shell, with `set -a; . ./.env; set +a`:

```yaml
uses:
  ops: github.com/opstruss/catalog@v1
  terraform:
    source: ops.terraform
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
    uses: terraform
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
  ops: github.com/opstruss/catalog@v1
  terraform:
    source: ops.terraform
    pass: [AWS_REGION]
    env:
      AWS_ACCESS_KEY_ID: ${{ secrets.aws_key }}
      AWS_SECRET_ACCESS_KEY: ${{ secrets.aws_secret }}
      AWS_SESSION_TOKEN: ${{ secrets.aws_session }}
```

## Provider cache

Each unit runs `terraform init` in a work directory of its own, so the
first plan of each unit downloads its providers again. A cache in the CLI
configuration of the machine downloads each provider once for every unit
and project:

```hcl
# ~/.terraformrc
plugin_cache_dir = "$HOME/.terraform.d/plugin-cache"
```

The directory must exist, as `mkdir -p ~/.terraform.d/plugin-cache`.
Terraform does not promise that the cache is safe for `terraform init`
runs at once, as in the plans of units that run at the same time, so the
cache fits units that `needs` order, or a machine whose cache already
holds their providers. `TF_PLUGIN_CACHE_DIR` through
`pass:` does the same, but the record of each unit keeps a fingerprint of
it, so a machine with another path, as CI, stops at plan with
`context changed`.

## State

The module says where its state lives:

| The module has | The state is |
|---|---|
| no backend block | `terraform.tfstate` in the tool directory of the unit, given as `-state`, which terraform warns about as deprecated |
| `backend "local" {}`, without a path | the same file, given as the path of the backend |
| a backend that names its place, as a `path`, or a `bucket` and `key` | there; OpsTruss does not move, lock, or remove it |

```hcl
terraform {
  backend "local" {}
}
```

- The tool directory moves and locks with the state of OpsTruss, and a
  destroy removes it. Only the local backend of OpsTruss keeps it yet.
- A place that the module names serves one unit. The instances of a
  `for_each` would share it, so their plan stops, unless `args.init` gives
  each its own, as `-backend-config=path=${{ each.key }}.tfstate`.
- A unit whose state is in the tool directory, and whose module comes to
  name a place, stops at plan and prints the commands that move the
  state there: `terraform state push` through `opstruss exec`, then
  `opstruss state rm <unit> --tool`.
- The state holds the values of the module as terraform writes them,
  sensitive ones among them, in plain text.
- The work directory of the unit keeps only what `terraform init`
  fetches. The variables and the plan file live in the temporary
  directory of the run, which ends with it.

## Existing state

A module that already has a state, from terraform run alone, becomes a
unit without making anything again:

- A module whose backend names its place, as `backend "s3"` or
  `backend "local" { path = "…" }`, keeps it there, and nothing moves.
- A module without a backend block keeps its state in the tool directory
  of the unit, so the state goes there once. `cat` writes a new file,
  which terraform can lock also when the old file is a read-only backup:

  ```sh
  opstruss exec dns --stack prod -- sh -c 'cat "$1" > "$OPSTRUSS_STATE_DIR/terraform.tfstate"' sh /backup/dns.tfstate
  ```

- Each instance of a `for_each` has a state of its own: copy one to each
  instance, or give each its own path with `-backend-config=path=…` in
  `args.init`.

Then the first `opstruss plan` of the unit lists no resource to create,
and `opstruss up` writes its record. Keep the old file as a backup; the
unit no longer reads it.

A module without a backend block that terraform applied alone has its
state in `terraform.tfstate` next to it, which the unit does not read.
Until the unit has a state, its plan and up stop and print both ways:
move that file to the unit with `opstruss exec` and `cat`, or keep it in
the module with `backend "local" { path = "terraform.tfstate" }`.

## Lock file

`.terraform.lock.hcl` belongs to the module, as when terraform runs
alone: the first `up` writes it next to the module, and its user commits
it. The units that use the module, as the instances of a `for_each`,
share it. A module that cannot be written, as one from a remote source,
needs a lock file that covers its providers; its author makes one with
`terraform providers lock`.

## exec

```sh
opstruss exec dns -- terraform state list
opstruss exec dns -- terraform plan
```

The program runs in the module with the data of the unit's `terraform
init`, the backend of the module, and the variables of the unit, from
`var_files` and `vars`, through `TF_CLI_ARGS_<command>`; without a
backend block, the state of the unit goes there as `-state` too. `args`
and `parallelism` stay with the plan and the up of the unit. `terraform
show` and `terraform state pull` take no `-state`; without a backend
block, the state of the unit is `terraform show
"$OPSTRUSS_STATE_DIR/terraform.tfstate"`.
