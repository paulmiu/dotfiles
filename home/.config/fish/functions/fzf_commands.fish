
function fzf_commands

    # CUSTOM FZF INTEGRATION
    # more infos about fzf can be found here: https://github.com/junegunn/fzf
    # this custom fzf integration may be replaced in the future by this fish plugin: https://github.com/PatrickF1/fzf.fish
    if type -q fzf
        # FZF (FUZZY FINDER) CONFIGS
        set -gx FZF_ALT_C_OPTS ""
        set -gx FZF_CTRL_R_OPTS ""
        set -gx FZF_DEFAULT_OPTS "--ansi -0 -1 --multi --height 40% --layout reverse --info inline --bind change:top --bind alt-space:toggle --bind tab:toggle+clear-query --bind alt-enter:toggle+down --prompt='██ ' --color 'prompt:#dddddd,bg:#282828'"

        set -l FZF_EXCLUDED_DIRS '.git' 'GoogleDrive' 'Google Drive' 'Library' '.Trash' 'node_modules'
        set -l FZF_EXCLUDED_FILES '*.zip' '*.tar' '*.tar.gz' '*.7z' '*.dmg' '*.png' '*.jpg' '*.jpeg' '*.so' '*.db' '*.plist' '*.ttf' '*.otf' '*.woff' '*.woff2' '*.dat' '*.sqlite' '*.sqlite3' '*.sqlite-wal' '*.sqlite-shm' '*.db-wal' '*.db-shm' '*.ico' '*.icns' '.DS_Store' '.localize'
        set -l FZF_FD_EXCLUDES "-E='"$FZF_EXCLUDED_DIRS"'"
        set -gx FZF_FD_EXCLUDES $FZF_FD_EXCLUDES "-E='"$FZF_EXCLUDED_FILES"'"
        set -l FZF_FIND_EXCLUDES "-not \( -ipath '*"$FZF_EXCLUDED_DIRS"/*' -prune \)" # this directory exclude pattern is needed when searching for files
        set -l FZF_FIND_EXCLUDES $FZF_FIND_EXCLUDES "-not \( -ipath '*/"$FZF_EXCLUDED_DIRS"' -prune \)" # and this directory exclude pattern is needed when searching for folders
        set -gx FZF_FIND_EXCLUDES $FZF_FIND_EXCLUDES "-not -iname '"$FZF_EXCLUDED_FILES"'"

        if set -q __FD_CMD; and type -q $__FD_CMD
            set -gx FZF_DEFAULT_COMMAND "$__FD_CMD --hidden --follow --type file $FZF_FD_EXCLUDES"
        else
            set -gx FZF_DEFAULT_COMMAND "bash -c \"find * -type f,l $FZF_FIND_EXCLUDES\""
        end

        # FZF SPECIFIC USER FUNCTIONS
        function vim
            if count $argv >/dev/null
                command vim $argv
            else
                set -l fzf_params "-m"
                set -l fzf_params $fzf_params "--height=40%"
                set -l fzf_params $fzf_params "--layout=reverse"
                set -l fzf_params $fzf_params "--info=inline"
                set -l fzf_params $fzf_params "--bind=change:top"
                set -l fzf_params $fzf_params "--bind=tab:toggle+down+clear-query"
                set -l fzf_params $fzf_params "--prompt=██ "
                set -l fzf_params $fzf_params "--color=prompt:#dddddd,bg:#282828"
                if set -q __BAT_CMD; and type -q $__BAT_CMD
                    set fzf_params $fzf_params "--preview=$__BAT_CMD --style=numbers --color=always {} | head -500"
                end
                command vim (fzf $fzf_params)
            end
        end

        function cd
            if count $argv >/dev/null
                if [ "$argv[1]" = ".." ]
                    fzf-cd navigate-up
                else
                    builtin cd $argv
                end
            else
                fzf-cd
            end
        end

        function history
            if count $argv >/dev/null
                builtin history $argv
            else
                fzf-history
            end
        end
    end

    # FZF FUNCTIONS

    function fzf-history -d "Show command history"
        set -q FZF_TMUX_HEIGHT
        or set FZF_TMUX_HEIGHT 40%
        begin
            set -lx FZF_DEFAULT_OPTS "--height $FZF_TMUX_HEIGHT $FZF_DEFAULT_OPTS --tiebreak=index --bind=ctrl-r:toggle-sort $FZF_CTRL_R_OPTS +m"

            set -l FISH_MAJOR (echo $version | cut -f1 -d.)
            set -l FISH_MINOR (echo $version | cut -f2 -d.)

            if set -q __BAT_CMD; and type -q $__BAT_CMD
                and test "$CTRL_R_ENABLE_COLORS" = "true"
                builtin history -z |
                awk -v ORS='⏎ ' '1' |
                string replace -r '⏎ $' '' |
                string split0 |
                command $__BAT_CMD --paging=never -p --color=always --italic-text=always -l bash |
                eval (__fzfcmd) --print0 -q '(commandline)' |
                string replace -ar '⏎ ' '\n' |
                read -gz result
                and commandline -- $result
            else
                builtin history -z | eval (__fzfcmd) --read0 --print0 -q '(commandline)' | read -gz result
                and commandline -- $result
            end
        end
        commandline -f repaint
    end

    function fzf-cd -a mode -d "Change directory"
        set -l commandline (__fzf_parse_commandline)
        set -l dir $commandline[1]
        set -l fzf_query $commandline[2]

        if not set -q FZF_ALT_C_COMMAND -a "$mode" != "navigate-up"
            if set -q __FD_CMD; and type -q $__FD_CMD
                set FZF_ALT_C_COMMAND "$__FD_CMD -H -t d $FZF_FD_EXCLUDES 2>/dev/null"
            else
                set FZF_ALT_C_COMMAND "find . -mindepth 1 -type d $FZF_FIND_EXCLUDES 2>/dev/null"
            end
        end

        if type -q z
            z -c > /dev/null
            set FZF_ALT_C_COMMAND "begin; z -l 2>/dev/null | awk '{ print \$2 }' | sed -e \"s#$HOME#~#g\"; $FZF_ALT_C_COMMAND; end"
        end

        if test "$mode" = "navigate-up"
            set -l PARENT_DIRS "command pwd | awk '
                    @include \"join\"
                    {
                        split(\$0, a, \"/\")
                    }
                    END {
                        for (i = 1; i < length(a) - 1; i++) {
                            path = join(a, 1, length(a) - i, \"/\")
                            print path
                            if (path == \"$HOME\") {
                                break;
                            }
                        }
                    }
                ' | sed -e \"s#$HOME#~#g\""
            set FZF_ALT_C_COMMAND "begin; $PARENT_DIRS; $FZF_ALT_C_COMMAND; end"
        else
            set FZF_ALT_C_COMMAND "begin; echo $HOME; $FZF_ALT_C_COMMAND; end"
        end

        set -q FZF_TMUX_HEIGHT
        or set FZF_TMUX_HEIGHT 40%
        begin
            set -lx FZF_DEFAULT_OPTS "--height $FZF_TMUX_HEIGHT --reverse $FZF_DEFAULT_OPTS $FZF_ALT_C_OPTS"
            eval "$FZF_ALT_C_COMMAND | "(__fzfcmd)' +m --no-sort --query "'$fzf_query'"' | read -l result

            if test -n "$result"
                if string match -q '~*' "$result"
                    string replace '~' "$HOME" "$result" | read result
                end

                builtin cd $result

                # Remove last token from commandline.
                commandline -t ""
            end
        end

        commandline -f repaint
    end

    function __fzfcmd
        set -q FZF_TMUX
        or set FZF_TMUX 0
        set -q FZF_TMUX_HEIGHT
        or set FZF_TMUX_HEIGHT 40%
        if [ $FZF_TMUX -eq 1 ]
            echo "fzf-tmux -d$FZF_TMUX_HEIGHT"
        else
            echo "fzf"
        end
    end

    function __fzf_parse_commandline -d 'Parse the current command line token and return split of existing filepath and rest of token'
        # eval is used to do shell expansion on paths
        set -l commandline (eval "printf '%s' "(commandline -t))

        if [ -z $commandline ]
            # Default to current directory with no --query
            set dir '.'
            set fzf_query ''
        else
            set dir (__fzf_get_dir $commandline)

            if [ "$dir" = "." -a (string sub -l 1 $commandline) != '.' ]
                # if $dir is "." but commandline is not a relative path, this means no file path found
                set fzf_query $commandline
            else
                # Also remove trailing slash after dir, to "split" input properly
                set fzf_query (string replace -r "^$dir/?" '' "$commandline")
            end
        end

        echo $dir
        echo $fzf_query
    end

    function __fzf_get_dir -d 'Find the longest existing filepath from input string'
        set dir $argv

        # Strip all trailing slashes. Ignore if $dir is root dir (/)
        if [ (string length $dir) -gt 1 ]
            set dir (string replace -r '/*$' '' $dir)
        end

        # Iteratively check if dir exists and strip tail end of path
        while [ ! -d "$dir" ]
            # If path is absolute, this can keep going until ends up at /
            # If path is relative, this can keep going until entire input is consumed, dirname returns "."
            set dir (dirname "$dir")
        end

        echo $dir
    end

end
