# chezmoi

Dotfiles that [chezmoi](https://www.chezmoi.io/) applies from a
repository, as a unit. On a machine that chezmoi has set up, `opstruss
plan` fetches the repository, so a new commit shows up, and lists each
file that differs from it, as one edited by hand; `opstruss up` pulls and
applies, over such edits.

Needs `chezmoi` 2.40 or later, `git`, and `jq` 1.6 or later in `PATH`.

## Use

A new Mac, from its packages to its dotfiles and the tools that they
name:

```yaml
uses:
  ops: github.com/opstruss/catalog@v1

units:
  packages:
    uses: ops.packages
    sudo: true
    with:
      brew: [chezmoi, mise]
  dotfiles:
    uses: ops.chezmoi
    needs: [packages]
    with:
      repo: https://github.com/ana/dotfiles.git
      prompts:
        Email: ana@example.com
        Work machine: true
  tools:
    uses: ops.mise
    needs: [dotfiles]
    with:
      dir: ~/.config/mise
```

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `repo` | string | required | The repository of the dotfiles, as `chezmoi init` takes it, such as `https://github.com/ana/dotfiles.git` or `ana` |
| `prompts` | object | `{}` | Answers to the prompts of the template of the configuration, by the text of each prompt; a string, a boolean, or an integer |
| `args` | object | `{}` | Arguments that chezmoi gets after those of the plugin, by command: `init` for the first `up` and `update` for the others, each a list of strings |

## Prompts

chezmoi asks the prompts of the template of its configuration, as
`promptStringOnce`, at `chezmoi init`. The plugin runs chezmoi without a
keyboard, so `prompts` answers them, by the text of each prompt:

```
{{ $email := promptStringOnce . "email" "Email" -}}
{{ $work := promptBoolOnce . "work" "Work machine" -}}
```

- A string answers with `--promptString`, a boolean with `--promptBool`,
  and an integer with `--promptInt`.
- A prompt without an answer fails `up` at once, with the message of
  chezmoi, rather than wait.
- chezmoi drops a quote at either end of a prompt or an answer that holds
  one `=`, so the plugin stops at one.
- The answers count at the first `up`. chezmoi keeps them in its
  configuration, where a prompt such as `promptStringOnce` finds its
  answer and does not ask again: a new answer needs `chezmoi init` by
  hand.

## Arguments

```yaml
units:
  dotfiles:
    uses: ops.chezmoi
    with:
      repo: ana
      args:
        init: [--branch=main]
        update: [--exclude=scripts]
```

- Each item is one argument, as written: no shell reads it.
- The plugin gives `--apply`, `--force`, `--no-tty`, the prompts, and the
  repository to `init`, and `--force` and `--no-tty` to `update`.
- A key of `args` that the plugin does not take, as a typo, stops
  `validate`.

## Outputs

| Name | Type | Description |
|---|---|---|
| `commit` | string | The commit of the source that chezmoi applied, short |
| `files` | list of strings | The files that chezmoi manages, relative to the home directory |

## Tasks

| Task | What it does |
|---|---|
| `plan` | `create dotfiles` where chezmoi has not set the machine up; else `git fetch` in the source, `update source` where the repository has new commits, and `update file.<path>` for each file that `chezmoi status` lists |
| `up` | `chezmoi init --apply` the first time, then `chezmoi update` |

- The plan reaches the repository on each `opstruss plan`; without the
  network, it fails with the message of git. git asks for no password: a
  private repository goes through SSH, whose agent reaches git, or a
  credential helper.
- `up` writes over a file edited by hand, which the plan listed.
- The plan is not exact: `up` pulls what the repository has when it runs.
- A machine that chezmoi has set up keeps its source: another `repo`
  takes effect only after `chezmoi purge`.
- The unit has no `destroy`: `chezmoi purge` would remove the source,
  which can hold commits that were never pushed, so `opstruss destroy`
  forgets the unit and leaves the source and the files. Run `chezmoi
  purge` to remove the source and the configuration.
