#!/usr/bin/env bash
# shellcheck source=install/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

shell_quote() {
    local value=$1
    printf "'"
    while [[ $value == *\'* ]]; do
        printf '%s' "${value%%\'*}" "'\\''"
        value=${value#*\'}
    done
    printf "%s'" "$value"
}

detect_platform() {
    case $(uname -s) in
        Darwin) printf 'macos\n' ;;
        Linux)
            local distro
            distro=$(sed -n 's/^ID=//p' /etc/os-release | tr -d '\042\047')
            case $distro in
                ubuntu | fedora) printf '%s\n' "$distro" ;;
                *) die "Unsupported Linux distribution: $distro" ;;
            esac
            ;;
        *) die 'Only macOS and supported Linux distributions are available.' ;;
    esac
}

parse_launcher_options() {
    INSTALL_ARGS=()
    MODE='' REMOTE_TARGET='' SSH_PORT=''
    while (($#)); do
        case $1 in
            --local | -l)
                [[ -z $MODE || $MODE == local ]] || die '--local conflicts with --remote.'
                MODE=local
                ;;
            --remote | -r | --remote=*)
                [[ -z $MODE || $MODE == remote ]] || die '--remote conflicts with --local.'
                MODE=remote
                if [[ $1 == *=* ]]; then
                    REMOTE_TARGET=${1#*=}
                elif [[ $# -gt 1 && $2 != -* ]]; then
                    shift
                    REMOTE_TARGET=$1
                fi
                ;;
            --port | --port=*)
                if [[ $1 == *=* ]]; then
                    SSH_PORT=${1#*=}
                else
                    (($# >= 2)) || die 'Missing --port value.'
                    shift
                    SSH_PORT=$1
                fi
                valid_port "$SSH_PORT" || die 'SSH port must be between 1 and 65535.'
                SSH_PORT=$((10#$SSH_PORT))
                ;;
            --no-greeting | -g) ;;
            *) INSTALL_ARGS+=("$1") ;;
        esac
        shift
    done
    parse_options ${INSTALL_ARGS[@]+"${INSTALL_ARGS[@]}"}
    [[ $MODE != local || -z $SSH_PORT ]] || die '--port is a remote connection option.'
    if [[ -n $REMOTE_TARGET ]]; then validate_remote_target "$REMOTE_TARGET"; fi
}

validate_remote_target() {
    local target=$1 host=$1 user
    if [[ $target == *@* ]]; then
        user=${target%%@*}
        host=${target#*@}
        valid_user "$user" || die 'Invalid remote login user.'
    fi
    valid_host "$host" || die 'Invalid remote host or SSH alias.'
}

local_install() {
    local platform log_dir log_file status
    local command=() statuses=()
    platform=$(detect_platform)
    command=(bash "$INSTALL_ROOT/os/$platform.sh" ${INSTALL_ARGS[@]+"${INSTALL_ARGS[@]}"})
    if [[ $DRY_RUN == true ]]; then
        "${command[@]}"
        return
    fi
    if [[ $platform != macos && $EUID != 0 ]]; then
        require_command sudo
        command=(sudo -- "${command[@]}")
    fi
    log_dir="$HOME/.local/state/dotfiles/logs"
    mkdir -p "$log_dir"
    chmod 700 "$log_dir"
    log_file=$(mktemp "$log_dir/install.XXXXXXXX")
    chmod 600 "$log_file"
    log "Installation log: $log_file"
    if "${command[@]}" 2>&1 | tee "$log_file"; then
        log 'Setup finished successfully.'
    else
        statuses=("${PIPESTATUS[@]}")
        status=${statuses[0]}
        if ((status == 0)); then status=${statuses[1]}; fi
        warn "Setup failed (exit $status). See $log_file"
        return "$status"
    fi
}

prepare_payload() {
    local repo=$1 destination=$2
    mkdir -p "$destination/source"
    if [[ -e $repo/.git ]]; then
        # Transfer only committed files. This includes unpublished installer changes.
        git -C "$repo" archive HEAD | tar -xf - -C "$destination/source"
        if [[ $DOTFILES_REF == main ]]; then
            git -C "$repo" bundle create "$destination/source/install/source.bundle" HEAD
        fi
    else
        cp -R "$repo/." "$destination/source/"
    fi
    [[ -f $destination/source/install/lib/launcher.sh ]] || die 'Commit the installer changes before using remote setup.'
    tar -czf "$destination/payload.tar.gz" -C "$destination/source" .
}

remote_cleanup() {
    local status=$?
    trap - EXIT
    if [[ -n ${REMOTE_WORK:-} ]]; then
        # Best effort cleanup uses the authenticated connection, never another host.
        ssh "${SSH_OPTIONS[@]}" -o BatchMode=yes "$REMOTE_TARGET" "rm -rf -- $(shell_quote "$REMOTE_WORK")" </dev/null >/dev/null 2>&1 || true
    fi
    ssh "${SSH_OPTIONS[@]}" -O exit "$REMOTE_TARGET" </dev/null >/dev/null 2>&1 || true
    rm -rf "$LAUNCH_WORK"
    exit "$status"
}

remote_install() (
    require_command ssh
    require_command scp
    if [[ -z $REMOTE_TARGET ]]; then
        prompt_value 'SSH target (user@host or existing SSH alias)'
        REMOTE_TARGET=$PROMPT_VALUE
    fi
    validate_remote_target "$REMOTE_TARGET"
    if [[ $DRY_RUN == true ]]; then
        log "Remote target: $REMOTE_TARGET; connection port: ${SSH_PORT:-from SSH config}"
        log 'Would transfer the committed installer snapshot over verified SSH and run its local setup.'
        return 0
    fi
    umask 077
    LAUNCH_WORK=$(mktemp -d /tmp/dotfiles-launch.XXXXXXXX)
    REMOTE_WORK=''
    SSH_OPTIONS=(-o StrictHostKeyChecking=ask -o ConnectTimeout=15 -o ServerAliveInterval=15 -o ServerAliveCountMax=3
        -o ControlMaster=auto -o ControlPersist=60 -o "ControlPath=$LAUNCH_WORK/ssh-%C")
    if [[ $ASSUME_YES == true ]]; then SSH_OPTIONS+=(-o BatchMode=yes); fi
    if [[ -n $SSH_PORT ]]; then SSH_OPTIONS+=(-p "$SSH_PORT"); fi
    trap remote_cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    local repo remote_command argument remote_script remote_directory scp_target remote_host
    local scp_options=(-o StrictHostKeyChecking=ask -o "ControlPath=$LAUNCH_WORK/ssh-%C")
    if [[ -n $SSH_PORT ]]; then scp_options+=(-P "$SSH_PORT"); fi
    repo=$(cd "$INSTALL_ROOT/.." && pwd)
    prepare_payload "$repo" "$LAUNCH_WORK"
    remote_directory=$(ssh "${SSH_OPTIONS[@]}" "$REMOTE_TARGET" 'mktemp -d /tmp/dotfiles-remote.XXXXXXXX')
    [[ $remote_directory =~ ^/tmp/dotfiles-remote\.[a-zA-Z0-9]+$ ]] || die 'Unexpected remote temporary directory response.'
    REMOTE_WORK=$remote_directory
    scp_target=$REMOTE_TARGET
    remote_host=${REMOTE_TARGET##*@}
    if [[ $remote_host == *:* ]]; then
        scp_target="[$remote_host]"
        if [[ $REMOTE_TARGET == *@* ]]; then scp_target="${REMOTE_TARGET%@*}@$scp_target"; fi
    fi
    scp "${scp_options[@]}" "$LAUNCH_WORK/payload.tar.gz" "$scp_target:$REMOTE_WORK/payload.tar.gz"
    # Expanded by the remote Bash process, after POSIX-safe single-quote escaping.
    # shellcheck disable=SC2016
    remote_script='set -euo pipefail
work=$1; shift
trap '\''rm -rf "$work"'\'' EXIT
mkdir "$work/source"
tar -xzf "$work/payload.tar.gz" -C "$work/source"
bash "$work/source/install/install.sh" --local "$@"'
    remote_command="bash -c $(shell_quote "$remote_script") -- $(shell_quote "$REMOTE_WORK")"
    for argument in ${INSTALL_ARGS[@]+"${INSTALL_ARGS[@]}"}; do
        remote_command+=" $(shell_quote "$argument")"
    done
    ssh "${SSH_OPTIONS[@]}" -t "$REMOTE_TARGET" "$remote_command"
)

launcher_main() {
    installer_init
    parse_launcher_options "$@"
    if [[ $SHOW_HELP == true ]]; then
        printf 'Usage: install.sh [--local | --remote USER@HOST] [--port PORT] [options]\n'
        printf 'Remote targets may be SSH aliases. --port selects the existing SSH connection port.\n'
        installer_usage
        return 0
    fi
    if [[ -z $MODE ]]; then
        if [[ $DRY_RUN == true || $ASSUME_YES == true ]]; then
            MODE=local
        elif confirm 'Configure a remote host over SSH?' no; then MODE=remote; else MODE=local; fi
    fi
    if [[ $MODE == remote ]]; then remote_install; else local_install; fi
}
