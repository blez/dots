#!/usr/bin/env bash
# Unlocks the git-crypt-encrypted dotfiles (paths in ~/.gitattributes) with the
# key stored in 1Password. Used by dotsetup.sh and setup.sh; safe to run again.
#
# Exit status: 0 when unlocked, already unlocked, or nothing is encrypted;
# 1 when it couldn't unlock (the reason and the fix are printed).
set -euo pipefail

key_item="dots git-crypt key"
account="my.1password.com"
git_dir="$HOME/dots"

dots() { git --git-dir="$git_dir" --work-tree="$HOME" "$@"; }

# Nothing tracked is marked for encryption: nothing to do.
if [ -z "$(cd "$HOME" && dots ls-files ':(attr:filter=git-crypt)' 2>/dev/null | head -1)" ]; then
    exit 0
fi
# git-crypt keeps the key inside the repo once unlocked.
if [ -f "$git_dir/git-crypt/keys/default" ]; then
    exit 0
fi

missing=()
command -v git-crypt >/dev/null || missing+=(git-crypt)
command -v op >/dev/null || missing+=("the 1Password CLI (op)")
if [ ${#missing[@]} -gt 0 ]; then
    echo "dots-unlock: the encrypted dotfiles stay locked for now. Missing: ${missing[*]}." >&2
    echo "  setup.sh installs what's missing and then unlocks them." >&2
    exit 1
fi

echo "==> Unlocking the encrypted dotfiles (1Password may ask you to approve or sign in)..."

# The key only ever lands in this private temp dir, which is removed on any
# exit, including errors and Ctrl-C.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# --foreground keeps the terminal usable, so op can ask for the account
# password when the desktop-app integration is off.
if ! timeout --foreground 300 op document get "$key_item" --account "$account" \
    --out-file "$tmp/key" >/dev/null; then
    cat >&2 <<EOF
dots-unlock: could not get "$key_item" from 1Password ($account).
  Either turn on Settings > Developer > "Integrate with 1Password CLI" in the
  1Password app, or add the account to the CLI: op account add --address $account
  Then run: ~/scripts/dots-unlock.sh
EOF
    exit 1
fi

if [ ! -s "$tmp/key" ]; then
    echo "dots-unlock: 1Password returned no key; run ~/scripts/dots-unlock.sh to try again." >&2
    exit 1
fi

if ! (cd "$HOME" && GIT_DIR="$git_dir" GIT_WORK_TREE="$HOME" git-crypt unlock "$tmp/key"); then
    cat >&2 <<EOF
dots-unlock: git-crypt unlock failed. It needs no uncommitted changes to
  tracked dotfiles: commit or stash them (dots stash), then run:
  ~/scripts/dots-unlock.sh
EOF
    exit 1
fi
echo "dots-unlock: unlocked the encrypted dotfiles."
