#!/usr/bin/env bash
# PAULMIU/DOTFILES SETUP SCRIPT

# Log file path of the setup scripts
INSTALLATION_LOG_FILE="/paulmiu_dotfiles_setup.log"

# helper variables to make text bold
bold_start=$(tput bold)
bold_end=$(tput sgr0)

get_public_ssh_key()
{
    key_file="$HOME/.ssh/id_rsa"
    public_key_file="${key_file}.pub"

    if [ ! -f "$public_key_file" ] ; then
        ssh-keygen -t rsa -N "" -f $key_file
    fi

    public_key="$(cat $public_key_file)"

    echo "$public_key"
}

is_host_up() {
    local host=$1

    # Step 1: Check using ping
    ping -c 1 -W 2 $host &>/dev/null

    if [ $? -eq 0 ]; then
        return 0
    fi

    # Step 2: Check using netcat for a range of common ports
    declare -a ports=("22" "22222" "80" "443" "21" "25" "110" "143" "587" "993" "995" "3306")

    for port in "${ports[@]}"; do
        nc -z -w2 $host $port &>/dev/null
        if [ $? -eq 0 ]; then
            return 0
        fi
    done

    # Step 3: Check using nmap, but only if nmap is installed
    if command -v nmap &>/dev/null; then
        response=$(nmap -sn $host | grep "Host is up")
        if [ -n "$response" ]; then
            return 0
        fi
    fi

    return 1
}

configure_new_server()
{
    echo
    echo "########## CONFIGURE NEW SERVER ##########"

    hostname="$1"

    old_port=$2
    if (( old_port == 22 )); then
        port=22
    else
        change_ssh_port=true
        new_ssh_port=$old_port
    fi

    old_user="$3"
    if [ "$old_user" = "root" ]; then
        install_user="root"
    else
        setup_admin_user=true
        admin_user="$old_user"
    fi

    add_ssh_config="$4"

    nickname="$5"
    [ -z "$nickname" ] && nickname="$hostname"

    # Servers domain or IP address
    if [ -z "$hostname" ]; then
        read -p "Hostname or IP address of the server: " hostname </dev/tty
        while ! is_host_up "$hostname" &>/dev/null
        do
            read -p "Host is not reachable. Please enter a valid hostname or IP address: " hostname </dev/tty
        done
    fi

    # SSH port
    if [ -z "$port" ]; then
        read -p "SSH port of the server [default=${bold_start}22${bold_end}]: " port </dev/tty
        [ -z "$port" ] && port="22"
    fi
    while ! nc -z $hostname $port &>/dev/null
    do
        read -p "Port $port is not open. Please enter the port where the ssh server is listening on [default=${bold_start}22${bold_end}]: " port </dev/tty
        [ -z "$port" ] && port="22"
    done


    # Change SSH port
    if [ -z "$change_ssh_port" ] || [ -z "$new_ssh_port" ]; then
        if (( port == 22 )); then
            read -p "Change SSH port to something else than 22? [${bold_start}Y${bold_end}/n] " change_ssh_port </dev/tty
            [ -z "$change_ssh_port" ] && change_ssh_port="y"
            case "${change_ssh_port:0:1}" in
                y|Y )
                    change_ssh_port=true

                    # New SSH port
                    read -p "New SSH port: [default=${bold_start}22222${bold_end}] " new_ssh_port </dev/tty
                    [ -z "$new_ssh_port" ] && new_ssh_port=22222
                    while [[ ! "$new_ssh_port" =~ ^[0-9]+$ ]]
                    do
                        read -p "Only numbers are allowed as an SSH port: [default=${bold_start}22222${bold_end}] " new_ssh_port </dev/tty
                        [ -z "$new_ssh_port" ] && new_ssh_port=22222
                    done
                ;;
                * )
                    change_ssh_port=false
                ;;
            esac
        else
            change_ssh_port=false
        fi
    fi

    # installation user
    if [ -z "$install_user" ]; then
        read -p "Which user do you want to use for the installation (must exist and have root privileges) [default=${bold_start}root${bold_end}]: " install_user </dev/tty
        [ -z "$install_user" ] && install_user="root"
    fi

    # setup admin user
    if [ -z "$setup_admin_user" ] || [ -z "$admin_user" ]; then
        read -p "Do you want to set up a new admin user (you can choose an existing user or create a new one)? [${bold_start}Y${bold_end}/n] " setup_admin_user </dev/tty
        [ -z "$setup_admin_user" ] && setup_admin_user="y"
        case "${setup_admin_user:0:1}" in
            y|Y )
                setup_admin_user=true
            ;;
            * )
                setup_admin_user=false
            ;;
        esac

        if [ "$setup_admin_user" = "true" ]; then
            read -p "Admin user name [default=${bold_start}${USER}${bold_end}]: " admin_user </dev/tty
            [ -z "$admin_user" ] && admin_user="$USER"
        else
            admin_user=""
        fi
    fi

    # add this config to ssh config
    if [ "$add_ssh_config" != "false" ]; then
        read -p "Add this config to SSH config file? [${bold_start}Y${bold_end}/n] " add_ssh_config </dev/tty
        [ -z "$add_ssh_config" ] && add_ssh_config="y"
        case "${add_ssh_config:0:1}" in
            y|Y )
                add_ssh_config=true

                # nickname for the server
                read -p "Nickname for this SSH login: [default=${bold_start}${hostname}${bold_end}] " nickname </dev/tty
                [ -z "$nickname" ] && nickname="$hostname"
                while [[ " ${hosts[@]} " =~ " ${nickname} " ]]
                do
                    read -p "Nickname does already exist. Please enter another nickname: [default=${bold_start}${hostname}${bold_end}] " nickname </dev/tty
                    [ -z "$nickname" ] && nickname="$hostname"
                done

                # autostart tmux at login
                read -p "Start tmux by default on SSH login? [${bold_start}Y${bold_end}/n] " tmux_autostart </dev/tty
                [ -z "$tmux_autostart" ] && tmux_autostart="y"
                case "${tmux_autostart:0:1}" in
                    y|Y )
                        tmux_autostart=true
                    ;;
                    * )
                        tmux_autostart=false
                    ;;
                esac
            ;;
            * )
                add_ssh_config=false
            ;;
        esac
    fi

    # login without entering a password in the future (adding id_rsa to known_hosts on server)
    read -p "Login without entering a password in the future? [${bold_start}Y${bold_end}/n] " ssh_copy_id </dev/tty
    [ -z "$ssh_copy_id" ] && ssh_copy_id="y"
    case "${ssh_copy_id:0:1}" in
        y|Y )
            ssh_copy_id=true
        ;;
        * )
            ssh_copy_id=false
        ;;
    esac

    if [ "$add_ssh_config" == "true" ]; then
        # add ssh configuration to ssh config file

        ssh_config_file="$HOME/.ssh/config"

        if [ ! -f "$ssh_config_file" ] ; then
            touch $ssh_config_file
        fi

        if [ -w "$ssh_config_file" ] ; then
            echo "" >> $ssh_config_file
            echo "Host $nickname" >> $ssh_config_file
            echo "    User $admin_user" >> $ssh_config_file
            echo "    HostName $hostname" >> $ssh_config_file
            if [ "$change_ssh_port" == "true" ]; then
                echo "    Port $new_ssh_port" >> $ssh_config_file
            else
                echo "    Port $port" >> $ssh_config_file
            fi
            if [ "$tmux_autostart" == "true" ]; then
                echo "    SendEnv TMUX_AUTOSTART" >> $ssh_config_file
            fi
        else
            echo "SSH configuration cannot be safed, because the SSH config file ($ssh_config_file) is not writable"
        fi
    fi

    # reboot server
    read -p "Do you want to reboot the server after a successful setup? [${bold_start}Y${bold_end}/n] " reboot_server </dev/tty
    [ -z "$reboot_server" ] && reboot_server="y"
    case "${reboot_server:0:1}" in
        y|Y )
            reboot_after_installation=true
        ;;
        * )
            reboot_after_installation=false
        ;;
    esac

    setup_remote_host $hostname $port $install_user $nickname $setup_admin_user $admin_user $ssh_copy_id $reboot_after_installation $change_ssh_port $new_ssh_port
}

choose_remote_host()
{
    # get the hosts from ~/.ssh/config
    hosts=(`grep -w -i "Host" ~/.ssh/config | sed 's/[ ]*[Hh][Oo][Ss][Tt][ ]*//g'`)

    # add option 'New Server' to array
    host_options=('New Server')
    host_options+=("${hosts[@]}")

    echo
    echo "Choose the server you want to setup:"

    select host_option in "${host_options[@]}"
    do
        if [[ "$REPLY" =~ ^[0-9]+$ ]]; then
            if [ $REPLY -eq 1 ]; then
                configure_new_server
                break;
            elif [ 1 -lt $REPLY ] && [ $REPLY -le ${#host_options[@]} ]; then
                hostname=(`ssh -G "$host_option" | grep "^hostname " | sed 's/hostname[ ]*//g'`)
                port=(`ssh -G "$host_option" | grep "^port " | sed 's/port[ ]*//g'`)
                username=(`ssh -G "$host_option" | grep "^user " | sed 's/user[ ]*//g'`)

                # check if server got a clean install (https://www.pcmag.com/encyclopedia/term/clean-install)
                echo
                read -p "Was this server ($host_option) clean installed (no admin user, no custom ssh port, etc.)? [${bold_start}Y${bold_end}/n] " is_clean_install </dev/tty
                [ -z "$is_clean_install" ] && is_clean_install="y"
                case "${is_clean_install:0:1}" in
                    y|Y )
                        configure_new_server "$hostname" "$port" "$username" "false" "$host_option"
                    ;;
                    n|N )
                        setup_remote_host "$hostname" "$port" "$username" "$host_option"
                    ;;
                    * )
                        echo "Unavailable option: \"$is_clean_install\"" >/dev/stderr
                    ;;
                esac

                break;
            else
                echo "Incorrect Input: Select a number 1-${#host_options[@]}"
            fi
        else
            echo "Incorrect Input: Select a number 1-${#host_options[@]}"
        fi
    done </dev/tty || host_option="1"
}

exit_program()
{
    echo
    exit $1
}

# `readlink -f` functionality for macOS
get_path_of_current_file() {
    TARGET_FILE=$1

    cd `dirname $TARGET_FILE`
    TARGET_FILE=`basename $TARGET_FILE`

    # Iterate down a (possible) chain of symlinks
    while [ -L "$TARGET_FILE" ]
    do
        TARGET_FILE=`readlink $TARGET_FILE`
        cd `dirname $TARGET_FILE`
        TARGET_FILE=`basename $TARGET_FILE`
    done

    # Finding the physical path for the directory we are in
    echo `pwd -P`
}

call_installation_script()
{
    current_script_path=$(get_path_of_current_file "$0")
    target_os=$1
    install_script="${current_script_path}/os/${target_os}.sh"

    params=()
    [ "$ADMIN_USER" ] && params+=("--admin-user=$ADMIN_USER")
    [ "$NICKNAME" ] && params+=("--nickname=$NICKNAME")
    [ "$PUBLIC_SSH_KEY" ] && params+=("--add-ssh-key=$PUBLIC_SSH_KEY")
    [ "$NEW_SSH_PORT" ] && params+=("--new-ssh-port=$NEW_SSH_PORT")
    [ "$REBOOT_AFTER_INSTALLATION" ] && params+=("--reboot")

    (( EUID != 0 )) && run_as_root="sudo -s"
    if [ -f "$install_script" ]; then
        # To get a colored output unbuffer the following command like so: https://superuser.com/a/751809/325412
        $run_as_root "$install_script" "${params[@]}" 2>&1 | $run_as_root tee $INSTALLATION_LOG_FILE
        return_value="$?"
    else
        curl -sL "https://raw.githubusercontent.com/paulmiu/dotfiles/master/install/os/${target_os}.sh" -o "./${target_os}.sh"
        chmod +x "./${target_os}.sh"
        # To get a colored output unbuffer the following command like so: https://superuser.com/a/751809/325412
        $run_as_root "./$target_os.sh" "${params[@]}" 2>&1 | $run_as_root tee $INSTALLATION_LOG_FILE
        return_value="$?"
        rm -f "./${target_os}.sh"
    fi

    if (( return_value == 0 )); then
        echo
        echo "########## ${bold_start}PAULMIU/DOTFILES${bold_end} WAS INSTALLED SUCCESSFULLY ##########"
        exit_program 0
    else
        echo
        echo "########## !!! ${bold_start}PAULMIU/DOTFILES${bold_end} WAS NOT INSTALLED !!! ##########"
        exit_program 1
    fi
}

check_os()
{
    echo
    uppercase_hostname=`echo "$HOSTNAME" | tr '[:lower:]' '[:upper:]'`
    echo "########## SETUP $uppercase_hostname ##########"

    case "$OSTYPE" in
        linux*)
            os_release_file=/etc/os-release

            if [ -f "$os_release_file" ] ; then
                source $os_release_file

                if [ "$ID" == "fedora" ] && (( "$VERSION_ID" >= "29" )); then
                    call_installation_script "fedora"
                elif [ "$ID" == "ubuntu" ]; then
                    call_installation_script "ubuntu"
                else
                    echo "This linux distro isn't supported."
                    exit_program 1
                fi
            else
                echo "Couldn't specify the linux distro."
                exit_program 1
            fi
        ;;
        darwin*)
            call_installation_script "macos"
        ;;
        msys*)
            echo "Windows is currently not supported."
            exit_program 1
        ;;
        *)
            echo "Unknown operating system. This OS is not supported."
            exit_program 1
        ;;
    esac
}

remove_verification_keys()
{
    hostname=$1
    port=$2

    # echo "Removing old host verification keys for $hostname from ~/.ssh/known_hosts ..."
    ssh-keygen -R "$hostname" &>/dev/null
    if (( port != 22 )); then
        ssh-keygen -R "[${hostname}]:$port" &>/dev/null
    fi
}

add_verification_key()
{
    hostname=$1
    port=$2

    # echo "Adding host verification keys for $hostname to ~/.ssh/known_hosts ..."
    ssh-keyscan -H -p "$port" $hostname >> "$HOME/.ssh/known_hosts" 2>/dev/null
}

add_verification_keys_for_all_ips()
{
    hostname=$1
    port=$2

    # If hostname is an IP address
    if [[ $hostname =~ ^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)(\.|$)){4}$ ]]; then
        return
    fi

    for ip in $(dig @8.8.8.8 $hostname +short)
    do
        # echo "Adding host verification keys for $ip to ~/.ssh/known_hosts ..."
        ssh-keygen -R "$ip" &>/dev/null
        if (( port != 22 )); then
            ssh-keygen -R "[${ip}]:$port" &>/dev/null
        fi
        ssh-keyscan -H -p "$port" $hostname,$ip >> "$HOME/.ssh/known_hosts" 2>/dev/null
        ssh-keyscan -H -p "$port" $ip >> "$HOME/.ssh/known_hosts" 2>/dev/null
    done
}

update_verification_keys()
{
    hostname=$1
    port=$2

    echo "Update host verification keys for $hostname ..."
    remove_verification_keys "$hostname" "$port"
    add_verification_key "$hostname" "$port"
    add_verification_keys_for_all_ips "$hostname" "$port"
}

setup_remote_host()
{
    echo
    echo "########## SETUP REMOTE HOST ##########"

    hostname="$1"
    port="$2"
    install_user="$3"
    nickname="$4"
    setup_admin_user="$5"
    admin_user="$6"
    ssh_copy_id="$7"
    reboot_after_installation="$8"
    change_ssh_port="$9"
    new_ssh_port=${10}

    echo "username: $install_user"
    echo "hostname: $hostname"

    params=("curl -sL https://raw.githubusercontent.com/paulmiu/dotfiles/master/install/install.sh | bash -s --")
    params+=("--local")
    params+=("--no-greeting")
    params+=("--nickname=$nickname")
    [ "$setup_admin_user" == "true" ] && params+=("--admin-user=$admin_user")
    [ "$reboot_after_installation" == "true" ] && params+=("--reboot")
    [ "$ssh_copy_id" == "true" ] && params+=("--add-ssh-key='$(get_public_ssh_key)'")
    [ "$change_ssh_port" == "true" ] && params+=("--new-ssh-port=$new_ssh_port")

    update_verification_keys "$hostname" "$port"

    ssh -o StrictHostKeyChecking=no -p $port $install_user@$hostname -t "${params[@]}"

    if [ "$change_ssh_port" == "true" ]; then
        update_verification_keys "$hostname" "$new_ssh_port"
    fi

    known_hosts_backup="$HOME/.ssh/known_hosts.old"
    if [ -f "$known_hosts_backup" ] ; then
        rm "$known_hosts_backup"
    fi

    exit_program
}

choose_install_target()
{
    echo
    # install remote or locally
    while :
    do
        read -p "Do you want to set up the (l)ocal or a (r)emote host? [l/${bold_start}R${bold_end}] " install_target </dev/tty || install_target="l"
        [ -z "$install_target" ] && install_target="r"
        case "${install_target:0:1}" in
            r|R )
                choose_remote_host
                break
            ;;
            l|L )
                check_os
                break
            ;;
            * )
                echo "Invalid choice. Please select ${bold_start}l${bold_end} for local or ${bold_start}r${bold_end} for remote!"
            ;;
        esac
    done
}


while [ $# -gt 0 ]; do
  case "$1" in
    -r|--remote)
        INSTALLATION_TARGET="remote"
        shift
    ;;
    -l|--local)
        INSTALLATION_TARGET="local"
        shift
    ;;
    -g|--no-greeting)
        NO_GREETING=true
        shift
    ;;
    -b|--reboot)
        REBOOT_AFTER_INSTALLATION=true
        shift
    ;;
    -u|--admin-user)
        ADMIN_USER="$2"
        shift 2
        if [ $? -gt 0 ]; then
            echo "You must pass an admin user as second argument to -u or --admin-user!" >&2
            exit 1
        fi
    ;;
    --admin-user=*)
        ADMIN_USER="${1#*=}"
        shift
    ;;
    -n|--nickname)
        NICKNAME="$2"
        shift 2
        if [ $? -gt 0 ]; then
            echo "You must pass a nickname as second argument to -n or --nickname!" >&2
            exit 1
        fi
    ;;
    --nickname=*)
        NICKNAME="${1#*=}"
        shift
    ;;
    -k|--add-ssh-key)
        PUBLIC_SSH_KEY="$2"
        shift 2
        if [ $? -gt 0 ]; then
            echo "You must pass a public SSH key as second argument to -k or --add-ssh-key!" >&2
            exit 1
        fi
    ;;
    --add-ssh-key=*)
        PUBLIC_SSH_KEY="${1#*=}"
        shift
    ;;
    -p|--new-ssh-port)
        NEW_SSH_PORT="$2"
        shift 2
        if [ $? -gt 0 ]; then
            echo "You must pass a port number as second argument to -p or --new-ssh-port!" >&2
            exit 1
        fi
    ;;
    --new-ssh-port=*)
        NEW_SSH_PORT="${1#*=}"
        shift
    ;;
    *)
        echo "unknown option: $1" >&2
        exit_program 1
    ;;
  esac
done

if [ -z "$NO_GREETING" ]; then
    echo
    echo "Welcome to the ${bold_start}paulmiu/dotfiles${bold_end} setup script!"
fi

if [ -z "$INSTALLATION_TARGET" ]; then
    choose_install_target
elif [ "$INSTALLATION_TARGET" == "remote" ]; then
    choose_remote_host
elif [ "$INSTALLATION_TARGET" == "local" ]; then
    check_os
fi

exit_program
