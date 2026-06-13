# SET ENVIRONMENT VARIABLES
set -x LC_ALL en_US.UTF-8
set -x LANG en_US.UTF-8
set -x TERM xterm-256color
set -x EDITOR vim
set -x GPG_TTY (tty)
set -x XDG_CONFIG_HOME $HOME/.config
set -x XDG_CACHE_HOME $HOME/.cache
set -x XDG_DATA_HOME $HOME/.local/share

set -x PATH $HOME/bin $HOME/.local/bin $XDG_CONFIG_HOME/fish/scripts $PATH

# Disable the default virtualenv prompt, since it doesn't play nice with fish
set -x VIRTUAL_ENV_DISABLE_PROMPT 1

# FISH SHELL CONFIGS
if not set -q USE_TMUX_BY_DEFAULT
    set USE_TMUX_BY_DEFAULT false
end
if not set -q ONLY_ATTACH_TO_TMUX_IN_SSH_SESSIONS
    set ONLY_ATTACH_TO_TMUX_IN_SSH_SESSIONS false
end
if not set -q CTRL_R_ENABLE_COLORS
    set -g CTRL_R_ENABLE_COLORS true # this option makes the CTRL-R function slower (just try it)
end
# Load all abbreviations declared in ./functions/abbreviations.fish
abbreviations

# IMPORT FISH SCRIPTS
source $HOME/.homesick/repos/homeshick/homeshick.fish
source $HOME/.homesick/repos/homeshick/completions/homeshick.fish
if test -f $HOME/bin/google-cloud-sdk/path.fish.inc
    source $HOME/bin/google-cloud-sdk/path.fish.inc
end
source "$HOME/.cargo/env.fish"
source "$HOME/.deno/env.fish"
pyenv init - fish | source

# CHECK IF BAT IS INSTALLED (CAT ALTERNATIVE)
if type -q bat
    set -g __BAT_CMD (which bat)
else if type -q batcat
    set -g __BAT_CMD (which batcat)
    alias bat=batcat
end
# SET BAT AS PAGER (IF IT'S INSTALLED)
if type -q $__BAT_CMD
    set -x PAGER "$__BAT_CMD -p"
    set -x MANPAGER "sh -c 'col -bx | $__BAT_CMD -l man --style=plain,numbers'"
    set -x MANROFFOPT "-c"
    set -x SYSTEMD_PAGER "$__BAT_CMD -l log -p"
end
# SET PNPM HOME
set -gx PNPM_HOME "$HOME/.local/share/pnpm"
if not string match -q -- $PNPM_HOME $PATH
  set -gx PATH "$PNPM_HOME" $PATH
end
# CHECK IF FD IS INSTALLED (FIND ALTERNATIVE)
if type -q fd
    set -g __FD_CMD (which fd)
else if type -q fdfind
    set -g __FD_CMD (which fdfind)
    alias fd=fdfind
end

# BOBTHEFISH THEME CONFIGS
function fish_greeting -d "Override fish greeting function to disable the bobthefish greeting"; end
set -g theme_display_git yes
set -g theme_display_git_master_branch no
set -g theme_display_user ssh
set -g theme_display_hostname ssh
set -g theme_display_date yes
set -g theme_title_use_abbreviated_path yes
set -g theme_title_display_user yes
set -g fish_prompt_pwd_dir_length 0
set -g theme_project_dir_length 0
set -g theme_date_format "+%d.%m.%Y %H:%M:%S"
set -g theme_powerline_fonts yes
set -g theme_show_exit_status yes
set -g theme_display_jobs_verbose yes
set -g theme_color_scheme base16

# ALIASES
alias ls="ls -h --group-directories-first --color"
alias la="ls -lah --group-directories-first --color"

# TMUX FISH INTEGRATION
# Replace currently running shell with tmux if
#  - current shell is a login shell AND
#  - current shell is interactive AND
#  - the "$USE_TMUX_BY_DEFAULT" variable is set to true
if type -q tmux
    and status is-login
    and status is-interactive
    # the following condition check is a workaround for this bug (and should be removed once it's solved): https://github.com/microsoft/vscode-remote-release/issues/4813#issuecomment-818780854
    and not ps -o command $fish_pid | tail -1 | awk '{print $2}' | string match "*c*" >/dev/null
    and test "$USE_TMUX_BY_DEFAULT" = "true"
    # make sure that current shell is not inside tmux
    if not tmux has-session 2>/dev/null; or test -z "$TMUX"
        # not inside of tmux session therefore create new one
        if test -n "$SSH_CLIENT" -o -n "$SSH_CONNECTION" -o -n "$SSH_TTY" -o "$ONLY_ATTACH_TO_TMUX_IN_SSH_SESSIONS" = "false"
            # only try to attach to existing tmux session if in ssh session or if specified with config var
            exec tmux new-session -A -s main
        else
            exec tmux
        end
    else
        # redraw tmux window if a new shell is created
        tmux refresh-client
    end
end
