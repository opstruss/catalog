# compose

[Docker Compose](https://docs.docker.com/compose/) projects as units.
`opstruss up` runs `docker compose up --wait`, and the services of the
project become the output of the unit. Compose prints in color where
OpsTruss shows color, and without it when OpsTruss sets `NO_COLOR`.

Needs `docker` with Compose v2 and `jq` in `PATH`.

## Use

```yaml
uses:
  compose: github.com/opstruss/catalog/plugins/compose@v1

units:
  web:
    uses: compose
    with:
      files: [./compose.yaml]
    env:
      IMAGE: ${{ units.build.outputs.image }}
```

Values of other units reach the Compose files through `env:` of the unit,
as variables that Compose interpolates, such as `image: ${IMAGE}`.

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `files` | list of strings | `[compose.yaml]` | The Compose files, relative to the file of the unit; a later file overrides an earlier one |
| `profiles` | list of strings | `[]` | The profiles whose services the project starts too |
| `env_files` | list of strings | `[]` | Files of the variables that Compose puts into the Compose files, relative to the file of the unit |
| `args` | object | `{}` | Arguments that `docker compose` gets after those of the plugin, by command: `up` and `down`, each a list of strings |

## Arguments

The inputs shape how Compose runs. `files`, `profiles`, and `env_files`
reach every `docker compose` of the unit, `opstruss exec` too, as
`COMPOSE_FILE`, `COMPOSE_PROFILES`, and `COMPOSE_ENV_FILES`; anything else
goes through `args`, after the arguments of the plugin:

```yaml
units:
  web:
    uses: compose
    with:
      files: [./compose.yaml, ./compose.prod.yaml]
      profiles: [monitoring]
      env_files: [./prod.env]
      args:
        up: [--pull, always, --build, --wait-timeout, "120"]
        down: [--timeout, "30"]
```

- Each item is one argument, as written: no shell reads it. A number is
  a string too, as `"120"`.
- `up` above pulls the images and builds the services with `build:` on
  every `up`, and waits two minutes for them; `down` gives the containers
  30 seconds to stop. `down` runs by the name of the project, without the
  Compose files, which may be gone.
- The plugin gives `-p`, `--ansi`, `-d`, `--wait`, and `--remove-orphans`;
  `args` does not give them.
- `args` become arguments of `docker compose`, which other users of the
  machine can read in the list of processes: a secret goes in `env:` of
  the unit or in an env file.
- A key of `args` that the plugin does not take, as a typo, stops `plan`
  with the key.

## Outputs

| Name | Type | Description |
|---|---|---|
| `services` | array | The services of the project |

## Tasks

| Task | What it does |
|---|---|
| `plan` | compares the config hash of each service with the label of its container: create, replace, or delete |
| `up` | `docker compose up -d --wait --remove-orphans` |
| `destroy` | `docker compose down --remove-orphans` |
| `status` | `docker compose ps -a` |
| `logs` | `docker compose logs`; with `follow: true`, follows them |
| `config` | `docker compose config`: the Compose files of the unit as Compose reads them |
| `exec` | the program of `opstruss exec`, with Compose set to the files, profiles, env files, and project of the unit |

The plan is not exact: `up` applies what Compose decides then, which the
plan does not promise.

## Project

The Compose project of a unit is named after its state key, such as
`default-web-7f3a9c1e`, so it stays when the unit moves, and `destroy` needs
only that name, not the Compose files.

## Docker host

The plugin asks for `DOCKER_HOST`, `DOCKER_CONTEXT`, and `DOCKER_CONFIG`,
which the project grants with `pass:`:

```yaml
uses:
  compose:
    source: github.com/opstruss/catalog/plugins/compose@v1
    pass: [DOCKER_CONTEXT]
```

The record keeps a fingerprint of what a unit passes, so `destroy` from
another Docker host stops. `DOCKER_CONFIG` names the directory of the
configuration of the Docker CLI, with its credentials and contexts, when
it is not `~/.docker`.

## exec

```sh
opstruss exec web -- docker compose ps
opstruss exec web -- docker compose logs -f
```

The program gets `COMPOSE_FILE`, `COMPOSE_PROFILES`, `COMPOSE_ENV_FILES`,
and `COMPOSE_PROJECT_NAME` of the unit, with absolute paths. A unit without
a record has no project yet, and Compose names one after the directory.
