# Dotfiles (chezmoi + Homebrew + age)

One repo for macOS and Linux machines (e.g. the dev server).

- **Dotfiles/config**: chezmoi templates, branched on OS (`.chezmoi.os`,
  detected automatically — no need to say "mac"), machine `role`
  (`default` / `server`), and `user` (`.chezmoi.username`, detected
  automatically, for future per-user config)
- **macOS Application Support**: `~/Library/Application Support/{fish,
  homebrew,sops}` are symlinked to their real locations under `~/.config`
  (`.chezmoiscripts/run_once_after_45-macos-appsupport-symlinks.sh.tmpl`),
  so tools that look in Application Support find the same content.
  Direction matters: `~/.config` stays a real, chezmoi-owned directory -
  `dot_config/fish`, `dot_config/homebrew`, `dot_config/systemd` are all
  normal, unconditional targets, identical on Linux and macOS, no
  OS-specific exclusions needed. The symlinks live entirely in Application
  Support instead, which isn't a chezmoi target at all, so nothing here
  ever conflicts with or gets overwritten by chezmoi's own apply.

  This is the opposite of the first two things we tried, both of which
  failed for the same underlying reason: chezmoi validates its entire
  source tree structurally and unconditionally re-enforces `~/.config` (or
  any subpath with a real, chezmoi-managed entry, like `~/.config/fish`) as
  a plain directory on every single apply, for as long as `dot_config/*`
  exists anywhere in the source tree - confirmed this is true even for a
  symlink pre-existing before `chezmoi apply` even starts, with zero script
  involvement. A declarative `symlink_dot_config.tmpl` coexisting with
  `dot_config/systemd` (needed as a real directory on Linux) hits an
  outright "inconsistent state" error; an imperative script fighting the
  same enforcement gets its symlink silently reverted, apply after apply.
  Symlinking the other direction sidesteps the conflict entirely, since
  chezmoi never has an opinion about Application Support in the first
  place. Safely migrates any existing content in each of the three
  directories first (refuses to finish for the affected one - leaves it
  as-is - if something with the same name already exists under `~/.config`,
  rather than risk clobbering it; the others still complete independently).
- **Packages**: single list in `.chezmoidata/packages.yaml` → rendered into a
  real `~/.config/homebrew/Brewfile` → applied with `brew bundle`
  (formulae + casks on macOS, formulae + Flatpaks on non-server Linux)
- **Secrets**: age-encrypted files committed to this repo (public); the age
  *private key* is the only secret outside git. It's the same identity used
  with sops, kept locally at `~/.config/sops/age/keys.txt`, pasted once at
  bootstrap.
- **Per-user identity**: git `name`/`email` are looked up from
  `.chezmoisecrets/users.yaml.age`, keyed by system username, directly in
  `dot_gitconfig.tmpl` (the only place they're needed) — see below.
- **Convenience**: `~/code/dotfiles` is a chezmoi-managed symlink to the
  actual chezmoi source checkout (`code/symlink_dotfiles.tmpl`), so it's
  reachable from the usual place alongside other projects.
- **Commit signing**: SSH-based (`gpg.format = ssh`), via `ssh-agent` — this
  matters for signing commits made inside VS Code dev containers, which get
  the agent forwarded but not `~/.ssh`. `dot_gitconfig.tmpl` inlines the
  literal public key into `user.signingKey` at render time (via chezmoi's
  `include`, reading `private_dot_ssh/private_readonly_id_ed25519.pub`)
  rather than pointing at a file path, so it keeps working wherever
  `.gitconfig` ends up even without `~/.ssh` present. That `.pub` file is
  still the single source of truth — it's also written to `~/.ssh/` on
  `chezmoi apply` for everything else that expects it there. Both halves of
  the keypair live in the repo under `private_dot_ssh/` — the public key in
  plaintext, the private key age-encrypted
  (`encrypted_private_readonly_id_ed25519.age`) — and are written to
  `~/.ssh/` automatically on `chezmoi apply`. Nothing to paste for the SSH
  key at all.

## One-time setup

```sh
age-keygen -o keys.txt                # 1. generate keypair (or reuse an
                                       #    existing sops age identity)
# 2. put the PUBLIC key into .chezmoi.toml.tmpl (recipient = "age1...")
# 3. keep keys.txt somewhere you control (password manager entry, offline
#    backup, etc.) so you can paste it on future machines

chezmoi add --encrypt --follow ~/.ssh/id_ed25519       # 4. commit the private
                                                        #    signing key, encrypted
chezmoi add --follow ~/.ssh/id_ed25519.pub             # 5. commit the public key
                                                        #    in plaintext (not secret)
# dot_gitconfig.tmpl already points user.signingKey at ~/.ssh/id_ed25519.pub,
# so no further edits needed there.
```

## Bootstrap a machine

The repo is public, so cloning needs no auth at all:

```sh
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply angelnu/dotfiles
```

Prompts once for `role` (default/server). OS and username are detected
automatically, not prompted - and git `name`/`email` aren't prompted for at
all, see "Per-user identity" below. Pruning (removing anything not declared
in `packages.yaml`) always runs; see "Packages" below to disable it per-run
or per-machine.

It will also ask you to paste the age private key, unless
`~/.config/sops/age/keys.txt` already exists — e.g. because you copied it
there yourself ahead of time. This prompt happens during `chezmoi init`'s own
config-generation step (`.chezmoi.toml.tmpl`), *before* `apply` touches
anything — that placement matters: chezmoi decrypts every `encrypted_` file
while building its target state, which happens before any
`run_once_before_` script gets to run, so a script-based prompt can never
fire in time once the repo has encrypted files (we hit exactly this: `chezmoi
init --apply` failed with "no such file or directory" because the age key
wasn't there yet and nothing had prompted for it). Doing the prompt inside
`chezmoi init` itself sidesteps that, since `init` always fully completes -
including this prompt and writing the key file - before `apply` starts.
Never paste the key into a chat/LLM session; type or pipe it in locally
(`pbpaste`, a password manager's CLI, etc.) if you're scripting this instead
of typing it at the prompt. Once that key is in place, chezmoi decrypts
everything else on its own — including the SSH signing key — no further
pasting needed.

The same "config not ready yet" ordering problem rules out looking up
`name`/`email` here too: chezmoi's `decrypt` template function reads from the
`[age]` section that *this very file* is producing, so calling it from inside
`.chezmoi.toml.tmpl` always fails with "encryption not configured" - also
confirmed the hard way. That's exactly why the lookup lives in
`dot_gitconfig.tmpl` instead: by the time *that* renders, during `apply`,
`[age]` has already been loaded from the config `init` finished generating.

Cloning is anonymous (read-only), so pushing changes afterward still needs
real auth. `.chezmoiscripts/run_once_after_15-switch-remote-to-ssh.sh.tmpl` switches the
source repo's remote to SSH automatically once our own SSH key has been
decrypted onto disk. If you'd rather have push access from the very first
clone instead of waiting for that, pre-place your SSH key and use `--ssh`:

```sh
mkdir -p ~/.ssh && chmod 700 ~/.ssh
cat > ~/.ssh/id_ed25519   # paste the private key, then Ctrl-D - never into a chat/LLM session
chmod 600 ~/.ssh/id_ed25519
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --ssh --apply angelnu/dotfiles
```

Answers land in `~/.config/chezmoi/chezmoi.toml`.

## Per-user identity

`.chezmoisecrets/users.yaml.age` is an age-encrypted dictionary, keyed by
system username:

```yaml
users:
  someusername:
    name: "Some User"
    email: "someuser@example.com"
```

`dot_gitconfig.tmpl` decrypts it and looks itself up by `.chezmoi.username`
when rendering `~/.gitconfig` - the only place `name`/`email` are actually
needed. If the username isn't found, `user.name`/`user.email` are just left
blank rather than failing the whole `apply`/`update` run (this file can
render unattended, via the daily auto-update timer, so it can't prompt).

To add a user, run `scripts/edit-users-secret.sh` - decrypts it to a temp
file, opens VS Code, waits for you to close the tab, re-encrypts it back in
place, and cleans up the temp file either way. Not chezmoi-managed
(`scripts/**` in `.chezmoiignore`), so it's just there to run directly from
the checkout, not applied anywhere.

This deliberately lives outside `.chezmoidata/`, not inside it: chezmoi
eagerly parses *every* file under `.chezmoidata/` as one of its known data
formats (yaml/json/toml/...) on every command, not just `init` - an
unrecognized extension like `.age` there is a hard error on every future
`apply`/`diff`/`update`, confirmed by testing it directly. A sibling
`.chezmoisecrets/` directory isn't special to chezmoi, so it's left alone and
only ever read explicitly, via `include`.

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
declared in the Brewfile. Both run from
`.chezmoiscripts/run_onchange_after_20-brew-bundle.sh.tmpl`,
which re-fires whenever `packages.yaml` changes. So deleting a line from
`packages.yaml` uninstalls it fleet-wide on the next `chezmoi update`.

The cleanup phase only runs at all if there's something to remove (skipped
silently otherwise), and prints what it would remove and asks before doing
it. Set `BREW_PRUNE_CONFIRM=yes` for unattended runs (e.g. the daily
auto-update timer) to skip that confirmation.

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
