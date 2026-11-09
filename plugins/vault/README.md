# vault

Secrets from the key/value secrets engine of
[Vault](https://developer.hashicorp.com/vault), for `secrets:` of a
project. The task `read` gives one field of a secret, or the whole secret
as an object, and the value stays sensitive wherever the project uses it.

Needs `vault`, Vault 1.10 or later, and `jq` 1.6 or later in `PATH`.

## Use

```yaml
uses:
  ops: github.com/opstruss/catalog@v1
  vault:
    source: ops.vault
    pass: [VAULT_ADDR, VAULT_TOKEN]

secrets:
  db_password:
    vault.read:
      path: secret/app/db
      field: password
  db:                              # the whole secret, as an object
    vault.read:
      path: secret/app/db

units:
  app:
    run: ./deploy.sh
    env:
      DB_PASSWORD: ${{ secrets.db_password }}
      DB_USER: ${{ secrets.db.user }}
```

## Tasks

| Task | What it does |
|---|---|
| `read` | `vault kv get` of a secret, or of one field of it |

### read

| Input | Type | Default | Description |
|---|---|---|---|
| `path` | string | required | The secret, as `<mount>/<path>`, the way `vault kv get` takes it |
| `field` | string | none | One field of the secret; the whole secret, as an object, without one |
| `version` | integer | the latest | The version of the secret, in a key/value engine of version 2 |

| Output | Type | Description |
|---|---|---|
| `value` | as Vault holds it, sensitive | The field, or the whole secret as an object |

- `read` takes both versions of the key/value engine, as `vault kv get`
  does.
- A secret that does not exist fails with the message of Vault; a field
  that it lacks fails with the names of the fields that it has, never
  their values. Only the units and tasks that read the secret fail.
- The value goes from `vault` to a file of the call and from there to
  the output, never to the log.

## Address and token

The address, the token, and the rest of the setup of Vault come from
variables of the operator that `pass:` lets through, never from an input,
which the project would write down. The plugin asks for `VAULT_*`, as
`opstruss doctor` lists, and `pass:` says which of them reach it:

- `VAULT_ADDR`, and `VAULT_NAMESPACE`, `VAULT_CACERT`, or
  `VAULT_SKIP_VERIFY` where the server needs them;
- `VAULT_TOKEN`, or the token that `vault login` wrote to
  `~/.vault-token`, which `vault` finds under `HOME` without `pass:`.

Without a token, Vault refuses the read with `permission denied`; `vault`
never prompts for one.
