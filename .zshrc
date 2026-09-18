#sh line
PROMPT_DIRNAME=3

DEFAULT_USER=$(whoami)
export PATH=$PATH:/usr/local/go/bin:~/go/bin:/usr/local/singlestore-toolbox
export GOPATH=~/go
export GOROOT=/usr/local/go
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/lib/

#pnpm
export PNPM_HOME=~/.local/share/pnpm

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

# export EDITOR='emacsclient -nw -a "" -c -s ~/.emacs.d/server/server'
export EDITOR='emacsclient -nw -a ""'
# export EDITOR='emacsclient -c -a ""'

# export __GLX_VENDOR_LIBRARY_NAME=nvidia __NV_PRIME_RENDER_OFFLOAD=1 DRI_PRIME=1

# Which plugins would you like to load? (plugins can be found in ~/.oh-my-zsh/plugins/*)
# Custom plugins may be added to ~/.oh-my-zsh/custom/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(
    git
    fzf-tab
    zsh-autosuggestions
    zsh-syntax-highlighting
    extract
    fzf
    sudo
    copyfile
)
# Dropped where it is not installed, so oh-my-zsh does not warn.
[[ -d $ZSH/custom/plugins/fzf-tab ]] || plugins=(${plugins:#fzf-tab})

if [[ -o interactive ]]; then
    if [[ ! -d ~/.zsh-autopair ]]; then
        git clone https://github.com/hlissner/zsh-autopair ~/.zsh-autopair
    fi

    source ~/.zsh-autopair/autopair.zsh
    autopair-init

    bindkey -e
    bindkey \^U backward-kill-line

    eval "$(starship init zsh)"
fi

source $ZSH/oh-my-zsh.sh

# Print "start → end (elapsed)" after commands that ran for at least 10s,
# and send a desktop notification if this terminal is not the focused window.
zmodload zsh/datetime
autoload -Uz add-zsh-hook
_cmdtime_preexec() { _cmdtime_start=$EPOCHSECONDS _cmdtime_cmd=$1 }
_cmdtime_precmd() {
    local code=$?
    [[ -n $_cmdtime_start ]] || return
    local elapsed=$(( EPOCHSECONDS - _cmdtime_start ))
    if (( elapsed >= 10 )); then
        print -P "%F{242}$(strftime %T $_cmdtime_start) → $(strftime %T $EPOCHSECONDS) (${elapsed}s)%f"
        _cmdtime_notify $code $elapsed
    fi
    unset _cmdtime_start _cmdtime_cmd
}
_cmdtime_notify() {
    [[ -n $DISPLAY && -n $WINDOWID ]] && (( $+commands[notify-send] && $+commands[xprop] )) || return
    local active="$(xprop -root _NET_ACTIVE_WINDOW 2>/dev/null)"
    active=${active##* }
    (( ${active:-0} == WINDOWID )) && return
    if (( $1 == 0 )); then
        notify-send -a zsh "Done in ${2}s" -- "$_cmdtime_cmd"
    else
        notify-send -a zsh -u critical "Failed ($1) after ${2}s" -- "$_cmdtime_cmd"
    fi
}
add-zsh-hook preexec _cmdtime_preexec
add-zsh-hook precmd _cmdtime_precmd

alias lsf="ls | fzf"
alias rc="$EDITOR ~/.zshrc"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [ "$ID" = "ubuntu" ]; then
        alias sp="$HOME/setup-ubuntu.sh"
    else
        alias sp="$HOME/setup.sh"
    fi
fi
alias spe="$EDITOR ~/setup.sh"

alias hel="cd ~/helios"

alias dw="cd ~/Downloads"
alias blez="cd ~/blez"
alias rt="cd $PROOT"
alias k="kubectl"
alias em="$EDITOR"

alias gr="git pull -r"
alias gcm="git cm"
alias gdf="git diff"
alias gal="git al"
alias preview="fzf --preview 'bat --color \"always\" {}'"
alias j="ranger"
alias lse='exa -l --git --icons --color=always --group-directories-first'
if command -v eza >/dev/null; then
    alias ls='eza --icons --group-directories-first'
    alias ll='eza -l --git --icons --group-directories-first'
    alias la='eza -la --git --icons --group-directories-first'
    alias lt='eza --tree --level=2 --icons --group-directories-first'
fi
alias kn="k9s"
alias dr="$EDITOR ."

alias pbcopy='xclip -selection clipboard'
alias pbpaste='xclip -selection clipboard -o'

alias myip="curl -s ifconfig.me || curl -s api.ipify.org"
alias myloc="curl -s ipinfo.io/$(myip) | jq -r .timezone"

alias dots="git --git-dir=$HOME/dots/ --work-tree=$HOME"
alias dotsadd='dots add $(dots st -s | awk "{print \$2}")'
dots config --local status.showUntrackedFiles no

alias src="source ~/.zshrc"
alias claude-personal="CLAUDE_CONFIG_DIR=~/.claude-personal $HOME/.local/bin/claude"

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

function y() {
    local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
    yazi "$@" --cwd-file="$tmp"
    IFS= read -r -d '' cwd <"$tmp"
    [ -n "$cwd" ] && [ "$cwd" != "$PWD" ] && builtin cd -- "$cwd"
    rm -f -- "$tmp"
}

clip() {
    if [ -t 0 ]; then
        cat "$@" | xclip -selection clipboard
    else
        xclip -selection clipboard
    fi
}

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
command -v zoxide >/dev/null && eval "$(zoxide init zsh)"

[ -s "$HOME/.config/envman/load.sh" ] && source "$HOME/.config/envman/load.sh"

if [ -f '~/Downloads/google-cloud-sdk/path.zsh.inc' ]; then . '~/Downloads/google-cloud-sdk/path.zsh.inc'; fi
if [ -f '~/Downloads/google-cloud-sdk/completion.zsh.inc' ]; then . '~/Downloads/google-cloud-sdk/completion.zsh.inc'; fi

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
# Must come after fzf so atuin owns Ctrl-R. Up arrow keeps the normal zsh history.
command -v atuin >/dev/null && eval "$(atuin init zsh --disable-up-arrow)"
[ -f ~/.ghcup/env ] && . ~/.ghcup/env # ghcup-env

# The next line updates PATH for the Google Cloud SDK.
if [ -f '/home/paval/Downloads/google-cloud-sdk/path.zsh.inc' ]; then . '/home/paval/Downloads/google-cloud-sdk/path.zsh.inc'; fi

# The next line enables shell command completion for gcloud.
if [ -f '/home/paval/Downloads/google-cloud-sdk/completion.zsh.inc' ]; then . '/home/paval/Downloads/google-cloud-sdk/completion.zsh.inc'; fi
