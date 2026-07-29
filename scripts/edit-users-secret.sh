#!/bin/bash
# Decrypts .chezmoisecrets/users.yaml.age to a temp file, opens it in VS
# Code, waits for you to close the tab, then re-encrypts it back in place.
# Run from anywhere; the temp plaintext is removed on exit either way
# (edited or not, error or not).
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SECRET_FILE="$REPO_DIR/.chezmoisecrets/users.yaml.age"
IDENTITIES_FILE="$REPO_DIR/.chezmoidata/identities.yaml"
IDENTITY="$HOME/.config/sops/age/keys.txt"

for cmd in age yq code; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: $cmd not found on PATH" >&2; exit 1; }
done
[ -f "$IDENTITY" ] || { echo "ERROR: age identity not found at $IDENTITY" >&2; exit 1; }
[ -f "$SECRET_FILE" ] || { echo "ERROR: $SECRET_FILE not found" >&2; exit 1; }

# Encrypted to every registered identity, not just one - this file is
# decrypted by dot_gitconfig.tmpl for whoever is applying, so everyone
# needs to be able to read it.
RECIPIENTS=()
while IFS= read -r r; do RECIPIENTS+=(-r "$r"); done < <(yq -r '.identities[].age_recipient' "$IDENTITIES_FILE")
[ "${#RECIPIENTS[@]}" -gt 0 ] || { echo "ERROR: no recipients found in $IDENTITIES_FILE" >&2; exit 1; }

TMPFILE="$(mktemp -t users-secret).yaml"
trap 'rm -f "$TMPFILE"' EXIT

age -d -i "$IDENTITY" -o "$TMPFILE" "$SECRET_FILE"
code --wait "$TMPFILE"
age "${RECIPIENTS[@]}" -o "$SECRET_FILE" "$TMPFILE"

echo "==> Re-encrypted $SECRET_FILE"
echo "==> Review with: git -C \"$REPO_DIR\" diff --stat, then commit and push when ready"
