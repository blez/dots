# dots
https://www.atlassian.com/git/tutorials/dotfiles

```
curl -sS https://raw.githubusercontent.com/blez/dots/master/scripts/dotsetup.sh | bash
```

In case of issues on previous step try do this
```
echo "dots" >> .gitignore
git clone --bare github.com/blez $HOME/dots
alias dots='/usr/bin/git --git-dir=$HOME/dots/ --work-tree=$HOME'
dots config status.showUntrackedFiles no
dots checkout
setup.sh
```
