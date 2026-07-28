# Dotfiles (chezmoi + Homebrew + age)

One repo for macOS, Bazzite (gaming) my Linux dev server.

- **Dotfiles/config**: chezmoi templates, branched on OS (`.chezmoi.os`,
  detected automatically — no need to say "mac"), machine `role`
  (`default` / `gaming`), and `user` (`.chezmoi.username`, detected
  automatically, for future per-user config)
- **Packages**: single list in `.chezmoidata/packages.yaml` → rendered into a
  real `~/.config/homebrew/Brewfile` → applied with `brew bundle`
  (formulae + casks on macOS, formulae + Flatpaks on Bazzite)
- **Secrets**: age-encrypted files committed to this repo; the age *private
  key* is the only secret outside git. It's the same identity used with sops,
  kept locally at `~/.config/sops/age/keys.txt`, pasted once at bootstrap.
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

The repo is private, so the clone step needs auth - and a genuinely fresh
machine won't have `gh` installed yet, so don't depend on it. Pick one:

**A) Pre-place the SSH key, clone over SSH directly** (simplest, if you're
willing to paste one more key up front):

```sh
mkdir -p ~/.ssh && chmod 700 ~/.ssh
cat > ~/.ssh/id_ed25519   # paste the private key, then Ctrl-D - never into a chat/LLM session
chmod 600 ~/.ssh/id_ed25519
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --ssh --apply angelnu/dotfiles
```

**B) Browser download, local init, switch to SSH after** (no key pasting
beyond the age key, no `gh` needed - just github.com in a normal logged-in
browser tab, which already handles 2FA at login):

1. On github.com, open the repo → Code → Download ZIP.
2. Extract it straight into chezmoi's default source location:
   ```sh
   unzip ~/Downloads/dotfiles-master.zip -d ~/.local/share/
   mv ~/.local/share/dotfiles-master ~/.local/share/chezmoi
   ```
3. `chezmoi init --apply` (no repo argument needed - it uses the source
   already in place).

Either way, once our SSH key has been decrypted onto disk,
`run_once_after_15-switch-remote-to-ssh.sh.tmpl` takes care of git: for (A)
it's already a real SSH clone, nothing to do; for (B) there's no `.git` at
all yet (a ZIP download doesn't include it), so the script runs `git init`,
adds `origin` over SSH, fetches, and checks out the default branch - turning
it into a real tracked clone so `chezmoi update` works normally from then on.

Prompts once for `role` (default/gaming), git email, and `prune`. OS and
username are detected automatically, not prompted. It will also ask you to
paste the age private key, unless `~/.config/sops/age/keys.txt` already
exists — e.g. because you copied it there yourself ahead of time. This prompt
happens during `chezmoi init`'s own config-generation step (`.chezmoi.toml.tmpl`),
*before* `apply` touches anything — that placement matters: chezmoi decrypts
every `encrypted_` file while building its target state, which happens before
any `run_once_before_` script gets to run, so a script-based prompt can never
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
