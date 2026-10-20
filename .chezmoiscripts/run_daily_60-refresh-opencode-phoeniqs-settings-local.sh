#!/bin/bash
# Keeps the extra opencode-agents (shared Phoeniqs settings: rules, skills,
# agents) checkout at ~/.config/opencode-phoeniqs-settings-local fresh -
# OPENCODE_CONFIG/OPENCODE_CONFIG_DIR point there (see .chezmoidata/env.yaml),
# so a stale checkout would silently run yesterday's rules and skills.
# Clones it if missing, otherwise fast-forwards the current branch to its
# truth: origin/local for the generated `local` branch (the sync-local
# pipeline publishes overlay commits there), origin/main for any other
# branch. Runs once a day: chezmoi tracks the run_daily_ interval in its
# persistent state, and fires whenever `chezmoi update`/`apply` runs.
#
# Safety rules, in order:
# - Uncommitted changes -> skip (never overwrite work; the skip shows up in
#   the chezmoi update output).
# - Fast-forward ONLY: local commits that diverge from the target branch
#   are never rebased, merged or discarded - you get a notice instead, and
#   rebase/merge by hand when you want them kept. This branch is exactly
#   where local changes are meant to live.
# - Fetch failures (offline, VPN down) skip silently instead of failing the
#   whole chezmoi update - a daily refresh missing one day is fine, a red
#   update every morning is not.
# - Clone + `local` branch creation only when the checkout doesn't exist
#   yet; SSH remote like the primary checkout (HTTPS has no keychain
#   credential for git.kvant.cloud - confirmed 2026-10-18).
set -euo pipefail

# Curated PATH, not whatever this process inherited (same as
# run_after_22-derive-ssh-pubkey): git is resolved by bare name and must
# not pick up a stale brew/nix shadow on some machine.
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/home/linuxbrew/.linuxbrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

REPO="$HOME/.config/opencode-phoeniqs-settings-local"
URL="ssh://git@git-ssh.kvant.cloud:2222/phoenix/opencode-agents.git"

if [ ! -d "$REPO/.git" ]; then
    echo "==> opencode-phoeniqs-settings-local: missing, cloning"
    git clone --quiet "$URL" "$REPO"
    git -C "$REPO" checkout -q -B local origin/local 2>/dev/null || git -C "$REPO" checkout -q -b local
    echo "==> opencode-phoeniqs-settings-local: cloned on branch local ($(git -C "$REPO" log --oneline -1))"
    exit 0
fi

if [ -n "$(git -C "$REPO" status --porcelain)" ]; then
    echo "==> opencode-phoeniqs-settings-local: uncommitted changes, skipping refresh"
    exit 0
fi

BRANCH="$(git -C "$REPO" branch --show-current)"
if ! git -C "$REPO" fetch --quiet origin 2>/dev/null; then
    echo "==> opencode-phoeniqs-settings-local: fetch failed (offline?), skipping refresh"
    exit 0
fi

# The `local` branch is GENERATED (sync-local pipeline overlay commits on
# origin/local) - its truth is origin/local, not origin/main. Any other
# branch still tracks origin/main.
TARGET="origin/main"
if [ "$BRANCH" = "local" ] && git -C "$REPO" rev-parse --verify --quiet origin/local >/dev/null 2>&1; then
    TARGET="origin/local"
fi

if [ "$(git -C "$REPO" rev-parse HEAD)" = "$(git -C "$REPO" rev-parse "$TARGET")" ]; then
    echo "==> opencode-phoeniqs-settings-local ($BRANCH): already up to date ($(git -C "$REPO" log --oneline -1))"
elif git -C "$REPO" merge-base --is-ancestor HEAD "$TARGET"; then
    git -C "$REPO" merge -q --ff-only "$TARGET"
    echo "==> opencode-phoeniqs-settings-local ($BRANCH): refreshed to $(git -C "$REPO" log --oneline -1)"
else
    echo "==> opencode-phoeniqs-settings-local ($BRANCH): diverged from $TARGET (local commits), leaving it alone"
fi
