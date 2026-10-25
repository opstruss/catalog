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
      file: ./compose.yaml
    env:
      IMAGE: ${{ units.build.outputs.image }}
```

Values of other units reach the Compose file through `env:` of the unit,
as variables that Compose interpolates, such as `image: ${IMAGE}`.

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `file` | string | `compose.yaml` | The Compose file, relative to the file of the unit |

## Outputs

| Name | Type | Description |
|---|---|---|
| `services` | array | The services of the project |

## Tasks

| Task | What it does |
|---|---|
| `plan` | compares the config hash of each service with the label of its container: create, replace, or delete |
| `up` | `docker compose up -d --wait --remove-orphans` |
| `down` | `docker compose down --remove-orphans` |
| `status` | `docker compose ps -a` |
| `logs` | `docker compose logs`; with `follow: true`, follows them |
| `config` | `docker compose config`: the Compose file as Compose reads it |
| `exec` | the program of `opstruss exec`, with Compose set to the file and the project of the unit |

The plan is not exact: `up` applies what Compose decides then, which the
plan does not promise.

## Project

The Compose project of a unit is named after its state key, such as
`default-web-7f3a9c1e`, so it stays when the unit moves, and `down` needs
only that name, not the Compose file.

## Docker host

The plugin asks for `DOCKER_HOST`, `DOCKER_CONTEXT`, and `DOCKER_CONFIG`,
which the project grants with `pass:`:

```yaml
uses:
  compose:
    source: github.com/opstruss/catalog/plugins/compose@v1
    pass: [DOCKER_CONTEXT]
```

The record keeps a fingerprint of what a unit passes, so `down` from
another Docker host stops. `DOCKER_CONFIG` names the directory of the
configuration of the Docker CLI, with its credentials and contexts, when
it is not `~/.docker`.

## exec

```sh
opstruss exec web -- docker compose ps
opstruss exec web -- docker compose logs -f
```

The program gets `COMPOSE_FILE` and `COMPOSE_PROJECT_NAME` of the unit. A
unit without a record has no project yet, and Compose names one after the
directory.
