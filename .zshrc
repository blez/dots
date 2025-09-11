#sh line
PROMPT_DIRNAME=3

DEFAULT_USER=$(whoami)
export TERM="xterm-256color"
export PATH=$PATH:/usr/local/go/bin:~/go/bin:/usr/local/singlestore-toolbox
export GOPATH=~/go
export GOROOT=/usr/local/go
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/lib/

#pnpm
export PNPM_HOME=~/.local/share/pnpm

# doom
export PATH=~/.emacs.d/bin:$PATH
export PATH=~/.config/emacs/bin:$PATH
export PATH=~/.diff-so-fancy:$PATH
export PATH=~/.arcanist/bin/:$PATH
export PATH=~/.local/bin/:$PATH
export PATH=/usr/java/jre1.8.0_333/bin/:$PATH
export PATH=~/flutter/bin/:$PATH
export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"
export PATH="$PNPM_HOME:$PATH"

# Path to your oh-my-zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Go
export GOPATH=~/go

export EDITOR='emacs -nw'

# export __GLX_VENDOR_LIBRARY_NAME=nvidia __NV_PRIME_RENDER_OFFLOAD=1 DRI_PRIME=1

# Which plugins would you like to load? (plugins can be found in ~/.oh-my-zsh/plugins/*)
# Custom plugins may be added to ~/.oh-my-zsh/custom/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.

if [[ ! -d ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-vi-mode ]]; then
    git clone https://github.com/jeffreytse/zsh-vi-mode ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-vi-mode
fi

plugins=(
    git
    zsh-vi-mode
    zsh-autosuggestions
    zsh-syntax-highlighting
    extract
    fzf
    sudo
    copyfile
)

# autopair
if [[ ! -d ~/.zsh-autopair ]]; then
    git clone https://github.com/hlissner/zsh-autopair ~/.zsh-autopair
fi
source ~/.zsh-autopair/autopair.zsh
autopair-init

# vi mode
bindkey -v
KEYTIMEOUT=1
export ZVM_CURSOR_STYLE_ENABLED=true
export ZVM_VI_INSERT_MODE_STRING="-- INSERT --"
export ZVM_VI_NORMAL_MODE_STRING="-- NORMAL --"
export ZVM_VI_VISUAL_MODE_STRING="-- VISUAL --"
bindkey -M viins '^[f' forward-word
bindkey -M viins '^[b' backward-word
bindkey -M viins '^[d' delete-word
bindkey -M viins '^D' delete-char
# Configure zsh-autopair for vi-insert mode
bindkey -M viins '(' autopair-insert
bindkey -M viins '{' autopair-insert
bindkey -M viins '[' autopair-insert
bindkey -M viins '"' autopair-insert
bindkey -M viins "'" autopair-insert
bindkey -M viins '`' autopair-insert

source $ZSH/oh-my-zsh.sh

# Bindings
bindkey -e
bindkey \^U backward-kill-line

# Starship
eval "$(starship init zsh)"

alias lsf="ls | fzf"
alias rc="emacs -nw ~/.zshrc"
alias sp="~/setup.sh"
alias spe="emacs -nw ~/setup.sh"

alias hel="cd ~/helios"

alias dw="cd ~/Downloads"
alias blez="cd ~/blez"
alias rt="cd $PROOT"
alias k="kubectl"
alias em="emacs -nw"

alias gr="git pull -r"
alias gcm="git cm"
alias gdf="git diff"
alias gal="git al"
alias preview="fzf --preview 'bat --color \"always\" {}'"
alias j="ranger"
alias lse='exa -l --git --icons --color=always --group-directories-first'
alias kn="k9s"
alias dr="emacs -nw ."

alias pbcopy='xclip -selection clipboard'
alias pbpaste='xclip -selection clipboard -o'

alias myip="curl -s ifconfig.me || curl -s api.ipify.org"
alias myloc="curl -s ipinfo.io/$(myip) | jq -r .timezone"

alias dots="git --git-dir=$HOME/dots/ --work-tree=$HOME"
dots config --local status.showUntrackedFiles no

alias src="source ~/.zshrc"

if [ -f ~/.ssh/agent.env ]; then
    . ~/.ssh/agent.env >/dev/null
    if ! kill -0 $SSH_AGENT_PID >/dev/null 2>&1; then
        echo "Stale agent file found. Spawning a new agent."
        eval $(ssh-agent | tee ~/.ssh/agent.env)
        ssh-add
    else
        # Check if key is already added
        if ! ssh-add -l >/dev/null 2>&1; then
            echo "No keys found in agent. Adding default key."
            ssh-add
        fi
    fi
else
    echo "Starting ssh-agent"
    eval $(ssh-agent | tee ~/.ssh/agent.env)
    ssh-add
fi

#base64 decode
64dec() {
    if [ -n "$1" ]; then
        echo "$1" | base64 -d
    fi
}

opc() {
    item=${1}
    op item get $item --format json | jq -r '.fields[] | select(.id=="password").value' | xclip -selection clipboard
}

build-clean-test-op() {
    make kube-rebuild-operator && make operator-test-clean && make operator-test
}

clean-test-op() {
    make operator-test-clean && make operator-test
}

fpath+=${ZDOTDIR:-~}/.zsh_functions
eval "$(direnv hook zsh)"
[ -f "/home/pkasko-ua/.ghcup/env" ] && source "/home/pkasko-ua/.ghcup/env" # ghcup-env

# Generated for envman. Do not edit.
[ -s "$HOME/.config/envman/load.sh" ] && source "$HOME/.config/envman/load.sh"

# The next line updates PATH for the Google Cloud SDK.
if [ -f '/home/pkasko-ua/Downloads/google-cloud-sdk/path.zsh.inc' ]; then . '/home/pkasko-ua/Downloads/google-cloud-sdk/path.zsh.inc'; fi

# The next line enables shell command completion for gcloud.
if [ -f '/home/pkasko-ua/Downloads/google-cloud-sdk/completion.zsh.inc' ]; then . '/home/pkasko-ua/Downloads/google-cloud-sdk/completion.zsh.inc'; fi
