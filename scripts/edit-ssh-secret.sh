#!/bin/bash
# Decrypts .chezmoisecrets/ssh/<username>/id_ed25519.age to a temp file
# (creating the parent dir if this is a brand new user), opens it in VS
# Code, waits for you to close the tab, then re-encrypts it back in place -
# to that one username's own age recipient only, never anyone else's. Run
# from anywhere; the temp plaintext is removed on exit either way (edited or
# not, error or not).
#
# Unlike edit-users-secret.sh, decrypting an *existing* file here only
# succeeds if you're running this as that username's own identity - that's
# the point: each person can only ever rotate their own key.
set -euo pipefail

SSH_KEY_USER="${1:-}"
[ -n "$SSH_KEY_USER" ] || { echo "usage: $0 <username>" >&2; exit 1; }

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SECRET_DIR="$REPO_DIR/.chezmoisecrets/ssh/$SSH_KEY_USER"
SECRET_FILE="$SECRET_DIR/id_ed25519.age"
IDENTITIES_FILE="$REPO_DIR/.chezmoidata/identities.yaml"
IDENTITY="$HOME/.config/sops/age/keys.txt"

for cmd in age yq code; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: $cmd not found on PATH" >&2; exit 1; }
done
[ -f "$IDENTITY" ] || { echo "ERROR: age identity not found at $IDENTITY" >&2; exit 1; }

# Bracket notation with the username embedded as a literal string, rather
# than yq's env()/--arg mechanisms: those aren't portable across the two
# unrelated tools both called "yq" (mikefarah/yq's `env(VAR)` vs. the
# Python/jq-wrapper's `--arg`/`env.VAR`) - confirmed the hard way when this
# broke on a machine where "yq" resolved to the jq-wrapper variant. This
# syntax works identically against both.
ESCAPED_USER=$(printf '%s' "$SSH_KEY_USER" | sed 's/\\/\\\\/g; s/"/\\"/g')
RECIPIENT="$(yq -r ".identities[\"${ESCAPED_USER}\"].age_recipient // \"\"" "$IDENTITIES_FILE")"
[ -n "$RECIPIENT" ] || { echo "ERROR: no identities.age_recipient entry for \"$SSH_KEY_USER\" in $IDENTITIES_FILE" >&2; exit 1; }

TMPFILE="$(mktemp -t ssh-secret)"
trap 'rm -f "$TMPFILE"' EXIT

if [ -f "$SECRET_FILE" ]; then
    age -d -i "$IDENTITY" -o "$TMPFILE" "$SECRET_FILE"
fi

code --wait "$TMPFILE"

mkdir -p "$SECRET_DIR"
age -r "$RECIPIENT" -o "$SECRET_FILE" "$TMPFILE"

echo "==> Re-encrypted $SECRET_FILE"
echo "==> Review with: git -C \"$REPO_DIR\" diff --stat, then commit and push when ready"
