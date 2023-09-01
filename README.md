# dots
https://www.atlassian.com/git/tutorials/dotfiles

```
echo "dots" >> .gitignore
git clone --bare github.com/blez $HOME/dots
alias dots='/usr/bin/git --git-dir=$HOME/dots/ --work-tree=$HOME'
dots config status.showUntrackedFiles no
dots checkout
setup.sh
```

Or look at scripts/dotsetup.sh
