# compose

[Docker Compose](https://docs.docker.com/compose/) projects as units.
`opstruss up` runs `docker compose up --wait`, and the services of the
project become the output of the unit. Compose prints in color where
OpsTruss shows color, and without it when OpsTruss sets `NO_COLOR`.

Needs `docker` with Compose v2 and `jq` in `PATH`.

## Use

```yaml
uses:
  cat: github.com/opstruss/catalog@v1

units:
  web:
    uses: cat.compose
    with:
      files: [./compose.yaml]
    env:
      IMAGE: ${{ units.build.outputs.image }}
```

Values of other units reach the Compose files through `env:` of the unit,
as variables that Compose interpolates, such as `image: ${IMAGE}`. The
plugin can also be declared alone, as
`compose: github.com/opstruss/catalog/plugins/compose@v1`, for units that
use it as `compose`.

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
    uses: cat.compose
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
| `plan` | compares the config hash and the state of each service with its container: create, replace, update, or delete |
| `up` | `docker compose up -d --wait --remove-orphans` |
| `destroy` | `docker compose down --remove-orphans` |
| `status` | `docker compose ps -a` |
| `logs` | `docker compose logs`; with `follow: true`, follows them |
| `config` | `docker compose config`: the Compose files that it is given, as Compose reads them; a step calls it (below) |
| `exec` | the program of `opstruss exec`, with Compose set to the files, profiles, env files, and project of the unit |

The plan is not exact: `up` applies what Compose decides then, which the
plan does not promise.

A step calls `config` through a name of the plugin in `uses:`, with the
files as a unit gives them:

```yaml
uses:
  cat: github.com/opstruss/catalog@v1
  compose: cat.compose
tasks:
  check:
    steps:
      - compose.config: {files: [./compose.yaml]}
```

Compose then names the project after the directory. For the files and the
project of a unit, `opstruss exec web -- docker compose config` runs
Compose as the unit does ([exec](#exec)).

A service whose container is `created`, `dead`, or exited with a code
other than 0, as after a crash, `docker stop`, or a reboot without a
restart policy, is an update, which `up` starts again. One that exited
with 0 ran as it should, as a migration does, and stays unchanged, and so
does one that is `paused` or `restarting`, which `up -d` leaves as it is.

`--wait` takes a service that exits with 0 only when another service
depends on it with `condition: service_completed_successfully`, as an app
on its migration; on its own, `up` fails with `exited (0)`:

```yaml
services:
  migrate:
    image: example/app
    command: [migrate]
  app:
    image: example/app
    depends_on:
      migrate: {condition: service_completed_successfully}
```

## Variables

The Compose files read variables of their own, as `${TAG}`, and so does
Docker, as `DOCKER_HOST`, so the plugin asks for every variable, and
`pass:` of the project says which reach Compose; without `pass:`, none
does:

```yaml
uses:
  cat: github.com/opstruss/catalog@v1
  compose:
    source: cat.compose
    pass: [DOCKER_CONTEXT, TAG]
```

Compose reads a `.env` file of its own through `env_files: [.env]`.

The record keeps a fingerprint of what a unit passes, so `destroy` from
another Docker host stops. `DOCKER_CONFIG` names the directory of the
configuration of the Docker CLI, with its credentials and contexts, when
it is not `~/.docker`.

## Project

The Compose project of a unit is named after its state key, such as
`default-web-7f3a9c1e`, so it stays when the unit moves, and `destroy` needs
only that name, not the Compose files.

## exec

```sh
opstruss exec web -- docker compose ps
opstruss exec web -- docker compose logs -f
```

The program gets `COMPOSE_FILE`, `COMPOSE_PROFILES`, `COMPOSE_ENV_FILES`,
and `COMPOSE_PROJECT_NAME` of the unit, with absolute paths. A unit without
a record has no project yet, and Compose names one after the directory.
