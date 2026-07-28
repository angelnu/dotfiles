#!/bin/bash
# Decrypts .chezmoisecrets/users.yaml.age to a temp file, opens it in VS
# Code, waits for you to close the tab, then re-encrypts it back in place.
# Run from anywhere; the temp plaintext is removed on exit either way
# (edited or not, error or not).
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SECRET_FILE="$REPO_DIR/.chezmoisecrets/users.yaml.age"
IDENTITY="$HOME/.config/sops/age/keys.txt"
RECIPIENT="age19zycawkart4t4l7a238w0n2w0rmw6anjadwv9yr3ce3js4dz3dcqqgkvsw"

for cmd in age code; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: $cmd not found on PATH" >&2; exit 1; }
done
[ -f "$IDENTITY" ] || { echo "ERROR: age identity not found at $IDENTITY" >&2; exit 1; }
[ -f "$SECRET_FILE" ] || { echo "ERROR: $SECRET_FILE not found" >&2; exit 1; }

TMPFILE="$(mktemp -t users-secret).yaml"
trap 'rm -f "$TMPFILE"' EXIT

age -d -i "$IDENTITY" -o "$TMPFILE" "$SECRET_FILE"
code --wait "$TMPFILE"
age -r "$RECIPIENT" -o "$SECRET_FILE" "$TMPFILE"

echo "==> Re-encrypted $SECRET_FILE"
echo "==> Review with: git -C \"$REPO_DIR\" diff --stat, then commit and push when ready"
