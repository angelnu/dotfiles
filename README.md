# Dotfiles (chezmoi + Homebrew + age)

One repo for macOS and Linux machines (e.g. the dev server).

- **Dotfiles/config**: chezmoi templates, branched on OS (`.chezmoi.os`,
  detected automatically — no need to say "mac"), machine `role`
  (`default` / `server` / `gaming`), and `user` (`.chezmoi.username`, detected
  automatically) - the same repo serves multiple people, each with their own
  age/SSH identity and package overlay, see "Per-user identity" below
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
- **Packages**: common list in `.chezmoidata/packages.yaml`, plus an optional
  per-user overlay in `.chezmoidata/packages-<username>.yaml` → both merged
  and rendered into a real `~/.config/homebrew/Brewfile` → applied with
  `brew bundle` (formulae + casks on macOS, formulae + Flatpaks on
  non-server Linux; rpm-ostree layered packages on Fedora Atomic hosts go
  through a separate script, see below)
- **Secrets**: age-encrypted files committed to this repo (public); each
  person's age *private key* is the only secret outside git, never shared
  between people. Kept locally at `~/.config/sops/age/keys.txt` (same
  identity used with sops), pasted once at bootstrap.
- **Per-user identity**: git `name`/`email`, the age encryption recipient,
  and the personal SSH signing key are all looked up per system username -
  see "Per-user identity" below.
- **Convenience**: `~/code/dotfiles` is a chezmoi-managed symlink to the
  actual chezmoi source checkout (`code/symlink_dotfiles.tmpl`), so it's
  reachable from the usual place alongside other projects.
- **Commit signing**: SSH-based (`gpg.format = ssh`), via `ssh-agent` — this
  matters for signing commits made inside VS Code dev containers, which get
  the agent forwarded but not `~/.ssh`. `dot_gitconfig.tmpl` derives
  `user.signingKey` directly from the current user's own encrypted private
  key at render time (decrypt, then `ssh-keygen -y` on it) rather than
  reading a `.pub` file or pointing at a file path, so it keeps working
  wherever `.gitconfig` ends up even without `~/.ssh` present, and stays
  correct per-person. The private key itself lives per-user under
  `.chezmoisecrets/ssh/<username>/id_ed25519.age` and is written to
  `~/.ssh/id_ed25519` automatically on `chezmoi apply`; the matching
  `~/.ssh/id_ed25519.pub` is derived from that file by a `run_after_` script
  (plain `ssh-keygen -y`, same as doing it by hand) rather than stored
  anywhere. Nothing to paste for the SSH key at all, beyond the one-time
  registration described in "Per-user identity" below.

  The signing key itself is only half the story - `git commit -S` also
  needs a running `ssh-agent` with that key loaded. On Linux (unlike macOS,
  which always has one running via launchd) nothing provides that on its
  own, so both `dot_config/fish/config.fish.tmpl` and `dot_profile.tmpl`
  (sourced by `dot_bashrc` too, for bash/sh/dev-container shells that don't
  go through fish) start-or-reuse one via `keychain` before falling through
  to a plain `ssh-add`. Confirmed the hard way as a real gap - signing
  silently failed on a machine where nothing had ever started an agent.

## One-time setup

```sh
age-keygen -o keys.txt                # 1. generate keypair (or reuse an
                                       #    existing sops age identity)
# 2. add yourself to .chezmoidata/identities.yaml:
#      identities:
#        yourusername:
#          age_recipient: age1...      # the PUBLIC key from step 1
# 3. keep keys.txt somewhere you control (password manager entry, offline
#    backup, etc.) so you can paste it on future machines

scripts/edit-ssh-secret.sh yourusername   # 4. paste your existing SSH private
                                           #    key in the editor that opens;
                                           #    encrypts it to your own
                                           #    recipient only, in
                                           #    .chezmoisecrets/ssh/yourusername/
scripts/edit-users-secret.sh              # 5. add your name/email; re-encrypts
                                           #    to everyone currently in
                                           #    identities.yaml
```

Commit and push both files when done. `dot_gitconfig.tmpl` and the SSH
templates already look themselves up by username - no further edits needed
there.

## Bootstrap a machine

The repo is public, so cloning needs no auth at all:

```sh
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply angelnu/dotfiles
```

Prompts once for `role` (default/server/gaming). OS and username are detected
automatically, not prompted - and git `name`/`email` aren't prompted for at
all, see "Per-user identity" below. Your username must already have an entry
in `.chezmoidata/identities.yaml` before running this - `init` fails fast
with a clear message otherwise, rather than producing a config with no
encryption recipient. Pruning (removing anything not declared in
`packages.yaml`) always runs; see "Packages" below to disable it per-run or
per-machine.

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

This repo serves multiple people (each on their own macOS/Linux machines),
not just one. Three things are keyed by `.chezmoi.username`:

### Age encryption recipient

`.chezmoidata/identities.yaml` is a **plaintext** map of username → age
public key:

```yaml
identities:
  someusername:
    age_recipient: age1...
```

Plaintext deliberately - `.chezmoi.toml.tmpl` needs this to set `[age]
recipient` while it's *generating* the very config that chezmoi's `decrypt`
function depends on, so `decrypt` isn't available to it yet (confirmed the
hard way - see "Bootstrap a machine"). If your username has no entry here,
`chezmoi init` fails immediately with a clear message rather than silently
producing a config with no recipient. Each person's own age *private* key
never appears in this repo at all - only ever locally, at
`~/.config/sops/age/keys.txt`.

### Name/email (git)

`.chezmoisecrets/users.yaml.age` is an age-encrypted dictionary, keyed the
same way:

```yaml
users:
  someusername:
    name: "Some User"
    email: "someuser@example.com"
```

Encrypted to **every** recipient in `identities.yaml` (not just one), since
`dot_gitconfig.tmpl` decrypts it for whoever is applying. `dot_gitconfig.tmpl`
looks itself up by `.chezmoi.username` when rendering `~/.gitconfig` - the
only place `name`/`email` are actually needed. If the username isn't found,
`user.name`/`user.email` are just left blank rather than failing the whole
`apply`/`update` run (this file can render unattended, via the daily
auto-update timer, so it can't prompt).

To add/edit a user, run `scripts/edit-users-secret.sh` - decrypts it to a
temp file, opens VS Code, waits for you to close the tab, re-encrypts it back
in place (to every current recipient), and cleans up the temp file either
way. Not chezmoi-managed (`scripts/**` in `.chezmoiignore`), so it's just
there to run directly from the checkout, not applied anywhere.

### Personal SSH key

`.chezmoisecrets/ssh/<username>/id_ed25519.age` holds each person's personal
key (used for git commit signing, GitHub, etc.), encrypted **only** to that
one person's own recipient - unlike `users.yaml.age`, this is never
multi-recipient, so nobody can decrypt anyone else's. `private_dot_ssh/
private_readonly_id_ed25519.tmpl` picks the current user's file by username
and writes it to `~/.ssh/id_ed25519`; a `run_after_` script derives
`~/.ssh/id_ed25519.pub` from it (plain `ssh-keygen -y`) on every apply, and
`dot_gitconfig.tmpl`'s `signingKey` derives it the same way independently
(the `.pub` file doesn't exist yet at template-render time on a first apply -
see the comment in that file).

To add/rotate your own key, run `scripts/edit-ssh-secret.sh <username>` -
same decrypt/edit/re-encrypt flow as above, but single-recipient and
per-user: decrypting an *existing* file only works if you're running it as
that username's own identity, so in practice each person can only ever
rotate their own key, never someone else's.

A couple of SSH keys (`id_rsa`, `ansible_rsa` - infra-automation access) stay
Angel-only regardless of who else is registered: gated out entirely for any
other username via a conditional block in `.chezmoiignore`, rather than
becoming multi-recipient like the personal key above.

### Package overlay

`.chezmoidata/packages-<username>.yaml`, one file per person, each under a
uniquely-named top-level key so multiple files merge without collisions
(chezmoi merges every file under `.chezmoidata/` into one data tree).
Same shape as `packages.yaml` itself (see "Packages" below for what that
shape means and how it's merged/flattened):

```yaml
per_user_someusername:
  brews:
    default:
      any-os: []
      darwin: []
      linux: []
  casks:
    default:
      any-os: []
  flatpaks:
    gaming:            # only merged in when role="gaming" - see angel's
      any-os: []       # file for a real example
  rpm_ostree: {}
```

Merged on top of `packages.yaml`'s own lists (concatenated, not replaced)
when rendering the Brewfile and the rpm-ostree script - see "Packages"
below. A category/role/os you don't need can just be omitted entirely
(everything degrades gracefully to empty).

### Why some of this lives outside `.chezmoidata/`

`.chezmoisecrets/` (both `users.yaml.age` and `ssh/`) deliberately isn't
under `.chezmoidata/`: chezmoi eagerly parses *every* file there as one of
its known data formats (yaml/json/toml/...) on every command, not just
`init` - an unrecognized extension like `.age` there is a hard error on
every future `apply`/`diff`/`update`, confirmed by testing it directly. A
sibling `.chezmoisecrets/` directory isn't special to chezmoi, so it's left
alone and only ever read explicitly, via `include`. `identities.yaml` is
plain `.yaml`, so it doesn't have this problem and lives under
`.chezmoidata/` normally.

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

`.chezmoidata/packages.yaml` declares five categories - `taps`, `brews`,
`casks`, `flatpaks`, `rpm_ostree` - and every one of them shares the exact
same two-level shape: **role** bucket, then **os** bucket:

```yaml
brews:
  default:          # always applies
    any-os: []       # both darwin and linux
    darwin: []
    linux: []
  server:            # only when role="server"
    any-os: []
  non_server:        # only when role != "server" (default or gaming)
    any-os: []
  gaming:            # only when role="gaming"
    any-os: []
  non_gaming:        # only when role != "gaming" (default or server)
    any-os: []
```

A machine always gets `default`, plus exactly one of `server`/`non_server`,
plus exactly one of `gaming`/`non_gaming` - so a headless server on the
`gaming` role's opposite side still gets `non_gaming`, etc. Any bucket you
don't need can just be omitted (see `.chezmoidata/packages.yaml` itself -
most categories only ever populate `default` and one or two others).

Per-user extras (`.chezmoidata/packages-<username>.yaml`, see "Per-user
identity" above) share this exact same shape and get merged in - list
leaves concatenated with the common ones, not replacing them - for whoever
is currently applying. Deleting a line there only uninstalls it for that
one person, not everyone.

The merge (`.packages` + the current user's overlay) and the
role/os-filtering down to a flat list are both implemented once, as shared
`.chezmoitemplates/` partials (`merged-packages`, `role-buckets`,
`merged-package-list`) called via chezmoi's `includeTemplate` function -
the only way to get a *value* back from a shared template, since plain
`template` only writes output. Used identically by both
`dot_config/homebrew/Brewfile.tmpl` and the rpm-ostree script below, so
there's one implementation of "what applies to this machine," not two.

`brew bundle install` adds; `brew bundle cleanup --force` removes anything not
declared in the rendered Brewfile. Both run from
`.chezmoiscripts/run_onchange_after_20-brew-bundle.sh.tmpl`,
which re-fires whenever `packages.yaml` (or the current user's overlay)
changes. So deleting a line from either uninstalls it on the next
`chezmoi update`.

The cleanup phase only runs at all if there's something to remove (skipped
silently otherwise), and prints what it would remove and asks before doing
it. Set `BREW_PRUNE_CONFIRM=yes` for unattended runs (e.g. the daily
auto-update timer) to skip that confirmation.

Caveats:
- Cleanup only manages what brew knows about. Things installed by hand are
  untouched.
- Non-formula types are opt-in via flags (`--flatpaks` etc.). Confirm the exact
  flag names with `brew bundle cleanup --help` on your version.
- There is a known bug where cleanup's autoremove pass can cascade into
  dependencies of packages you *did* declare. Read the dry-run output the first
  few times rather than reflexively confirming.
- Casks are uninstalled, not zapped; add `--zap` if you want config removed too.

#### rpm-ostree (Fedora Atomic / Bazzite)

`packages.rpm_ostree` (same role/os-scoped shape as everything else, merged
with the current user's overlay via the shared `.chezmoitemplates/`
partials described above) declares packages to layer with `rpm-ostree
install` on atomic hosts - things brew/flatpak can't provide, e.g.
`nextcloud-client-dolphin` for real file-manager overlay-icon integration
(a flatpak's sandbox can't hook into Dolphin the same way). Converged by
`.chezmoiscripts/run_onchange_after_21-rpm-ostree.sh.tmpl`, which:

- Renders to an empty no-op file on any host where `/run/ostree-booted` doesn't
  exist (i.e. everywhere except rpm-ostree hosts) - safe to leave declared
  packages in `packages.yaml` even if only some machines are atomic.
- Diffs the flattened package list against `rpm-ostree status`'s
  requested-package list, `rpm-ostree install`s anything missing, and offers to
  `rpm-ostree uninstall` anything no longer declared (same ask-first pattern as
  brew cleanup; set `RPM_OSTREE_PRUNE_CONFIRM=yes` for unattended runs).
- **Never reboots automatically.** Layered changes only take effect after a
  reboot - the script just reminds you; running it unattended (e.g. the daily
  timer) leaves the host in a "changes pending" state until you reboot it
  yourself.

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
chezmoi add --encrypt ~/.ssh/ansible_rsa
```

Creates `encrypted_*.age` in the source dir — commit it like any other file.
Encrypts to *your own* recipient (`.chezmoidata/identities.yaml`), so this is
right for secrets that are yours alone. For the personal SSH key
(`id_ed25519`) specifically, use `scripts/edit-ssh-secret.sh` instead - see
"Per-user identity" above.
