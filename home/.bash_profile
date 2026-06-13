
# Source global definitions
if [ -f ~/.bashrc ]; then
    . ~/.bashrc
fi

# Use fish as login shell
# (Disable for now to explore the behaviour without this code.)
# (If this code is still commented out in 2-3 month, delete it.)
# case "$-" in
#     *i*) exec fish -il ;;
#     *)  ;;
# esac


. "$HOME/.cargo/env"
. "$HOME/.deno/env"