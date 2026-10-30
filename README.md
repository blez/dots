# dots

Dotfiles and setup scripts for an Ubuntu 24.04 desktop: xmonad + xmobar,
Doom Emacs, zsh, alacritty, rofi, dunst, yazi, and helper scripts in `scripts/`.

The repo is a bare git repo in `~/dots` with `$HOME` as its work tree, so files
stay where programs expect them. How that works:
[Atlassian's dotfiles tutorial](https://www.atlassian.com/git/tutorials/dotfiles).

## New machine

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/blez/dots/master/scripts/dotsetup.sh)
```

`scripts/dotsetup.sh` creates an SSH key (if there's none) and copies it to the
clipboard for you to add to GitHub. It then checks out the dotfiles, moving
files the checkout would overwrite to `~/.config-backup`, installs git-crypt,
the GTK theme and the Nerd Font.

Then install everything else:

```sh
~/setup.sh
```

It installs missing tools and offers upgrades, and is safe to run again later.
`-y` answers yes to the upgrade prompts (Emacs is still asked about; Go stays
pinned), `-i` only reports them. See `~/setup.sh --help`.

### By hand

If `dotsetup.sh` fails, with an SSH key already added to GitHub:

```sh
cd ~
echo dots >> ~/.gitignore
git clone --bare git@github.com:blez/dots.git ~/dots
alias dots='git --git-dir=$HOME/dots/ --work-tree=$HOME'
dots config status.showUntrackedFiles no
dots checkout   # lists the files in the way if it fails: move them aside, run it again
~/setup.sh
```

## Encrypted files

Some files are encrypted with [git-crypt](https://github.com/AGWA/git-crypt):
Claude Code settings and notes, and the wallpapers. In this public repo they're
ciphertext; their names, sizes and change history are not hidden. The paths are
listed in `~/.gitattributes`, and the key is in 1Password.

`setup.sh` unlocks them once the 1Password CLI is installed. To do it yourself:
`~/scripts/dots-unlock.sh`.

To encrypt a new file, add its path to `~/.gitattributes` **before** its first
`dots add`. A file committed before that is stored in plain text and stays
readable in the history. List the encrypted files with:

```sh
dots ls-files ':(attr:filter=git-crypt)'
```

## Daily use

The aliases are in `~/.zshrc`:

- `dots` is `git` for this repo: `dots status`, `dots diff`, `dots commit`, `dots push`.
- `dotsadd` stages changes to tracked files (`dots add -u`).
- `dots-crypt` is `git-crypt` for this repo.

Untracked files are hidden from `dots status`, so add a new file by name:
`dots add ~/.config/foo/config`.
