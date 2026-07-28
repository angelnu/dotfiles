# Dotfiles (chezmoi + Homebrew + age)

One repo for macOS, Bazzite (gaming) and the Linux server.

- **Dotfiles/config**: chezmoi templates, branched on OS and machine `role`
- **Packages**: single list in `.chezmoidata/packages.yaml` → rendered into a
  real `~/.config/homebrew/Brewfile` → applied with `brew bundle`
  (formulae + casks on macOS, formulae + Flatpaks on Bazzite)
- **Secrets**: age-encrypted files committed to this repo; the age *private key*
  is the only secret outside git — Bitwarden item `chezmoi-age-key`, or pasted
  once at bootstrap

## One-time setup

```sh
age-keygen -o key.txt                 # 1. generate keypair
# 2. put the PUBLIC key into .chezmoi.toml.tmpl (recipient = "age1...")
# 3. store key.txt contents in Bitwarden as secure note: chezmoi-age-key
```

## Bootstrap a machine

```sh
export BW_SESSION=$(bw unlock --raw)   # optional, for non-interactive key fetch
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply <your-git-remote>
```

Prompts once for `role` (mac/gaming/server), git email, and `prune`.
Answers land in `~/.config/chezmoi/chezmoi.toml`.

---

## Removal semantics (how deletions propagate)

Deleting a file from the source directory does **not** by itself delete it from
the target — chezmoi only adds and updates. There are three mechanisms:

### 1. `exact_` directories — automatic, preferred

A source dir prefixed `exact_` means "the target must contain exactly this and
nothing else". Delete a file from the source → it disappears from every machine
on next apply. Stray files created by hand are also removed.

```
dot_config/systemd/exact_user/chezmoi-update.timer
```

Attribute order matters: `exact_private_foo`, not `private_exact_foo`.

**Do not** mark `~` or `dot_config` itself as `exact_` — that would delete every
unmanaged file in your home directory or `~/.config`. Apply `exact_` only to
leaf directories you fully own.

### 2. `.chezmoiremove` — tombstone list

For files outside any `exact_` directory (e.g. top-level `~/.vimrc`). Listed
paths are deleted on every apply; globs and templating are supported. Add an
entry when you retire a file, prune the entry once all machines have converged.

### 3. `remove_` prefix

An empty source file named `remove_dot_vimrc` deletes `~/.vimrc`. Equivalent to
a `.chezmoiremove` entry, but lives next to the thing it replaces. Use whichever
you find more readable.

### Packages

`brew bundle install` adds; `brew bundle cleanup --force` removes anything not
declared in the Brewfile. Both run from `run_onchange_after_20-brew-bundle.sh`,
which re-fires whenever `packages.yaml` changes. So deleting a line from
`packages.yaml` uninstalls it fleet-wide on the next `chezmoi update`.

The cleanup phase prints what it would remove and asks before doing it. Set
`BREW_PRUNE_CONFIRM=yes` for unattended runs, or answer `false` to the `prune`
prompt to disable the destructive phase on a given machine.

Caveats:
- Cleanup only manages what brew knows about. Things installed via `dnf`,
  `rpm-ostree`, or by hand are untouched.
- Non-formula types are opt-in via flags (`--flatpaks` etc.). Confirm the exact
  flag names with `brew bundle cleanup --help` on your version.
- There is a known bug where cleanup's autoremove pass can cascade into
  dependencies of packages you *did* declare. Read the dry-run output the first
  few times rather than reflexively confirming.
- Casks are uninstalled, not zapped; add `--zap` if you want config removed too.

### What is *not* covered

`run_once_` scripts are recorded in chezmoi's state DB. Deleting such a script
does not undo what it did — write a compensating change instead. Same for
anything a script installed outside brew.

---

## Daily driving

```sh
chezmoi edit ~/.zshrc
chezmoi apply
chezmoi cd && git add -A && git commit -m "..." && git push

chezmoi update          # other machines (also runs daily via systemd timer)
chezmoi apply --dry-run --verbose   # preview, including removals
```

## Adding an encrypted secret

```sh
chezmoi add --encrypt ~/.ssh/id_ed25519
```

Creates `encrypted_*.age` in the source dir — commit it like any other file.
