#!/bin/bash
# Entry point for the com.chezmoi.update LaunchAgent (see
# Library/LaunchAgents/com.chezmoi.update.plist): runs the daily
# `chezmoi update --force` under launchd. launchd gives this process a
# minimal PATH (/usr/bin:/bin:...), so the PATH is curated explicitly
# instead of trusting the inherited one (confirmed the hard way elsewhere
# in this repo: run_after_22-derive-ssh-pubkey failed from a stale
# shadowed binary - same class of problem). --force because an unattended
# apply must never hang on a conflict prompt: managed targets are
# chezmoi's to write, that's the deal.
set -euo pipefail
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/home/linuxbrew/.linuxbrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
exec chezmoi update --force
