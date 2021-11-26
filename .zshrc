#sh line
PROMPT_DIRNAME=3

DEFAULT_USER=`whoami`
export TERM="xterm-256color"
export PATH=$PATH:/usr/local/go/bin:~/go/bin:/usr/local/singlestore-toolbox
export GOPATH=~/go
export GOROOT=/usr/local/go

# doom
export PATH=~/.emacs.d/bin:$PATH
export PATH=~/.diff-so-fancy:$PATH
export PATH=~/.arcanist/bin/:$PATH
export PATH=~/.local/bin/:$PATH

# Path to your oh-my-zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Go
export GOPATH=~/go

export EDITOR='vim'

# Which plugins would you like to load? (plugins can be found in ~/.oh-my-zsh/plugins/*)
# Custom plugins may be added to ~/.oh-my-zsh/custom/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.

if [[ ! -d ~/.zsh-autopair ]]; then
  git clone https://github.com/hlissner/zsh-autopair ~/.zsh-autopair
fi

plugins=(
  git
  zsh-autosuggestions
  zsh-syntax-highlighting
  extract
  fzf
)

# autopair
if [[ ! -d ~/.zsh-autopair ]]; then
  git clone https://github.com/hlissner/zsh-autopair ~/.zsh-autopair
fi
source ~/.zsh-autopair/autopair.zsh
autopair-init

source $ZSH/oh-my-zsh.sh

# Starship
eval "$(starship init zsh)"

alias lsf="ls | fzf"
alias rc="vim ~/.zshrc"
alias sp="~/setup.sh"
alias spe="vim ~/setup.sh"

alias hel="cd ~/helios"

alias blez="cd ~/blez"
alias rt="cd $PROOT"
alias k="kubectl"

alias gr="git pull -r"
alias gcm="git cm"
alias gdf="git diff"
alias gal="git al"
alias preview="fzf --preview 'bat --color \"always\" {}'"
alias j="ranger"

alias dots="git --git-dir=$HOME/dots/ --work-tree=$HOME"
dots config --local status.showUntrackedFiles no

alias src="source ~/.zshrc"

# The next line updates PATH for the Google Cloud SDK.
if [ -f '/home/paval/google-cloud-sdk/path.zsh.inc' ]; then . '/home/paval/google-cloud-sdk/path.zsh.inc'; fi

# The next line enables shell command completion for gcloud.
if [ -f '/home/paval/google-cloud-sdk/completion.zsh.inc' ]; then . '/home/paval/google-cloud-sdk/completion.zsh.inc'; fi

if [ -f ~/.ssh/agent.env ] ; then
    . ~/.ssh/agent.env > /dev/null
    if ! kill -0 $SSH_AGENT_PID > /dev/null 2>&1; then
        echo "Stale agent file found. Spawning a new agent. "
        eval `ssh-agent | tee ~/.ssh/agent.env`
        ssh-add
    fi
else
    echo "Starting ssh-agent"
    eval `ssh-agent | tee ~/.ssh/agent.env`
    ssh-add
fi

#base64 decode
64dec() {
    if [ -n "$1" ]; then
        echo "$1" | base64 -d
    fi
}

fpath+=${ZDOTDIR:-~}/.zsh_functions
eval "$(direnv hook zsh)"
[ -f "/home/pkasko-ua/.ghcup/env" ] && source "/home/pkasko-ua/.ghcup/env" # ghcup-env
