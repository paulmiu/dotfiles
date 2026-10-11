#!/usr/bin/env bash
# Shared installer primitives. Sourcing this file has no system side effects.
# Options are consumed by the platform entry points.
# shellcheck disable=SC2034

log() { printf '[dotfiles] %s\n' "$*"; }
warn() { printf '[dotfiles] Warning: %s\n' "$*" >&2; }
die() {
    printf '[dotfiles] Error: %s\n' "$*" >&2
    exit 1
}

installer_error() {
    local status=$1 line=$2
    printf '[dotfiles] Installation failed at line %s (exit %s).\n' "$line" "$status" >&2
    exit "$status"
}

installer_init() {
    set -Eeuo pipefail
    umask 022
    trap 'installer_error "$?" "$LINENO"' ERR
    trap 'exit 130' INT
    trap 'exit 143' TERM
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "Required command is missing: $1"
}

require_root() { [[ $EUID == 0 ]] || die 'Run this installer as root (sudo bash …).'; }

valid_user() { [[ $1 =~ ^[a-z_][a-z0-9_-]*\$?$ && ${#1} -le 32 ]]; }
valid_port() { [[ $1 =~ ^[0-9]{1,5}$ ]] && ((10#$1 >= 1 && 10#$1 <= 65535)); }
valid_host() { [[ $1 =~ ^[a-zA-Z0-9][a-zA-Z0-9.:%_-]*$ && ${#1} -le 253 ]]; }
valid_hostname() {
    local label
    [[ $1 =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*$ && ${#1} -le 253 ]] || return 1
    local IFS=.
    for label in $1; do
        [[ ${#label} -le 63 && $label != -* && $label != *- && -n $label ]] || return 1
    done
    [[ $1 != *..* && $1 != *. ]]
}

valid_ref() { [[ $1 =~ ^[a-zA-Z0-9][a-zA-Z0-9._/-]*$ && $1 != *..* && $1 != */ ]]; }

validate_public_key() {
    local key=$1 file
    [[ $key != *$'\n'* && $key != *$'\r'* ]] || die 'Supply exactly one public SSH key.'
    case $key in
        ssh-ed25519\ * | ssh-rsa\ * | ecdsa-sha2-*\ * | sk-ssh-ed25519@openssh.com\ * | sk-ecdsa-sha2-nistp256@openssh.com\ *) ;;
        *) die 'Expected a public SSH key, without authorized_keys options.' ;;
    esac
    require_command ssh-keygen
    file=$(mktemp "${TMPDIR:-/tmp}/dotfiles-key.XXXXXX")
    printf '%s\n' "$key" >"$file"
    if ! ssh-keygen -l -f "$file" >/dev/null 2>&1; then
        rm -f "$file"
        die 'Invalid public SSH key.'
    fi
    rm -f "$file"
}

confirm() {
    local question=$1 default=${2:-no} answer
    if [[ ${ASSUME_YES:-false} == true ]]; then
        [[ $default == yes ]]
        return
    fi
    [[ -t 0 || -r /dev/tty ]] || die 'Interactive input is unavailable; use explicit options and --yes.'
    while :; do
        printf '%s [%s]: ' "$question" "$default" >/dev/tty
        IFS= read -r answer </dev/tty || die 'Input closed; installation cancelled.'
        case ${answer:-$default} in
            y | Y | yes | YES) return 0 ;;
            n | N | no | NO) return 1 ;;
            *) printf 'Please enter yes or no.\n' >/dev/tty ;;
        esac
    done
}

prompt_value() {
    local question=$1 default=${2:-}
    [[ ${ASSUME_YES:-false} != true ]] || die "Missing required option: $question"
    printf '%s [%s]: ' "$question" "$default" >/dev/tty
    IFS= read -r PROMPT_VALUE </dev/tty || die 'Input closed; installation cancelled.'
    PROMPT_VALUE=${PROMPT_VALUE:-$default}
}

download_file() {
    local url=$1 destination=$2 partial
    [[ $url == https://* ]] || die 'Downloads must use HTTPS.'
    partial=$(mktemp "${destination}.XXXXXX")
    if command -v curl >/dev/null 2>&1; then
        if ! curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
            --connect-timeout 20 --max-time 300 --retry 2 "$url" -o "$partial"; then
            rm -f "$partial"
            return 1
        fi
    elif command -v wget >/dev/null 2>&1; then
        if ! wget --https-only --timeout=30 --tries=3 -qO "$partial" "$url"; then
            rm -f "$partial"
            return 1
        fi
    else
        rm -f "$partial"
        die 'Install curl or wget to download files.'
    fi
    [[ -s $partial ]] || {
        rm -f "$partial"
        return 1
    }
    mv -f "$partial" "$destination"
}

installer_usage() {
    cat <<'USAGE'
Usage: bash install/os/<os>.sh [options]
  --admin-user USER       Existing user, or create a Linux admin interactively
  --groups LIST           Comma-separated package group IDs; 'none' installs prerequisites only
  --yes                  Use default package groups without prompts
  --dry-run              Show the plan without changing the system
  --upgrade              Also upgrade installed system packages (Linux)
  --hostname NAME        Set the Linux hostname
  --add-ssh-key KEY       Authorize one public key for the target user
  --new-ssh-port PORT     Add an SSH listening port; retain existing ports (Linux)
  --skip-ssh             Leave SSH server configuration untouched (Linux)
  --skip-plugins         Skip downloading Fish, Vim and tmux plugins
  --no-shell-change      Keep the target user's current login shell
  --reboot               Schedule a Linux reboot after successful setup
  --ref REF              Dotfiles Git branch, tag or commit (default: main)
  --help                 Show this help
USAGE
}

parse_options() {
    ADMIN_USER='' PUBLIC_SSH_KEY='' NEW_SSH_PORT='' NEW_HOSTNAME='' NICKNAME=''
    ASSUME_YES=false DRY_RUN=false UPGRADE=false REBOOT=false SKIP_SSH=false
    SKIP_PLUGINS=false CHANGE_SHELL=true GROUPS_REQUESTED='' SHOW_HELP=false
    DOTFILES_REF=main
    local option value
    while (($#)); do
        option=${1%%=*}
        case $option in
            --admin-user | -u | --add-ssh-key | -k | --new-ssh-port | -p | --hostname | --nickname | -n | --groups | --ref)
                if [[ $1 == *=* ]]; then value=${1#*=}; else
                    (($# >= 2)) || die "Missing value for $option"
                    shift
                    value=$1
                fi
                [[ -n $value && $value != --* ]] || die "Missing value for $option"
                case $option in
                    --admin-user | -u)
                        valid_user "$value" || die 'Invalid username.'
                        ADMIN_USER=$value
                        ;;
                    --add-ssh-key | -k) PUBLIC_SSH_KEY=$value ;;
                    --new-ssh-port | -p)
                        valid_port "$value" || die 'SSH port must be between 1 and 65535.'
                        NEW_SSH_PORT=$((10#$value))
                        ;;
                    --hostname)
                        valid_hostname "$value" || die 'Invalid hostname.'
                        NEW_HOSTNAME=$value
                        ;;
                    --nickname | -n)
                        valid_host "$value" || die 'Invalid nickname.'
                        NICKNAME=$value
                        ;;
                    --groups) GROUPS_REQUESTED=$value ;;
                    --ref)
                        valid_ref "$value" || die 'Invalid Git ref.'
                        DOTFILES_REF=$value
                        ;;
                esac
                ;;
            --yes | --dry-run | --upgrade | --reboot | -r | -b | --skip-ssh | --skip-plugins | --no-shell-change | --help | -h)
                [[ $1 != *=* ]] || die "Unexpected value for $option"
                case $option in
                    --yes) ASSUME_YES=true ;;
                    --dry-run) DRY_RUN=true ;;
                    --upgrade) UPGRADE=true ;;
                    --reboot | -r | -b) REBOOT=true ;;
                    --skip-ssh) SKIP_SSH=true ;;
                    --skip-plugins) SKIP_PLUGINS=true ;;
                    --no-shell-change) CHANGE_SHELL=false ;;
                    --help | -h) SHOW_HELP=true ;;
                esac
                ;;
            *) die "Unknown option: $1" ;;
        esac
        shift
    done
    [[ $SKIP_SSH != true || -z $NEW_SSH_PORT ]] || die '--skip-ssh conflicts with --new-ssh-port.'
}

group_selected() {
    local item
    for item in ${SELECTED_GROUPS[@]+"${SELECTED_GROUPS[@]}"}; do
        [[ $item != "$1" ]] || return 0
    done
    return 1
}

select_groups() {
    local index item found
    local requested=()
    SELECTED_GROUPS=()
    if [[ -n $GROUPS_REQUESTED ]]; then
        [[ $GROUPS_REQUESTED != none ]] || return 0
        [[ $GROUPS_REQUESTED != ,* && $GROUPS_REQUESTED != *, && $GROUPS_REQUESTED != *,,* ]] || die 'Invalid group list.'
        IFS=, read -r -a requested <<<"$GROUPS_REQUESTED"
        for item in "${requested[@]}"; do
            found=false
            for index in "${!GROUP_IDS[@]}"; do
                [[ $item != "${GROUP_IDS[index]}" ]] || found=true
            done
            [[ $found == true ]] || die "Unknown group '$item'. Available: ${GROUP_IDS[*]}"
            if ! group_selected "$item"; then SELECTED_GROUPS+=("$item"); fi
        done
    else
        for index in "${!GROUP_IDS[@]}"; do
            if [[ $DRY_RUN == true || $ASSUME_YES == true ]]; then
                if [[ ${GROUP_DEFAULTS[index]} == yes ]]; then SELECTED_GROUPS+=("${GROUP_IDS[index]}"); fi
            elif confirm "Install ${GROUP_LABELS[index]} (${GROUP_IDS[index]})?" "${GROUP_DEFAULTS[index]}"; then
                SELECTED_GROUPS+=("${GROUP_IDS[index]}")
            fi
        done
    fi
}

print_plan() {
    log "Platform: $1; target user: ${ADMIN_USER:-${SUDO_USER:-root}}; dotfiles ref: $DOTFILES_REF"
    log "Package groups: ${SELECTED_GROUPS[*]:-none}; upgrade: $UPGRADE; plugins skipped: $SKIP_PLUGINS"
    log "Change login shell: $CHANGE_SHELL; SSH changes skipped: $SKIP_SSH; reboot: $REBOOT"
    if [[ -n $NEW_HOSTNAME ]]; then log "Set hostname: $NEW_HOSTNAME"; fi
    if [[ -n $NEW_SSH_PORT ]]; then log "Add SSH port: $NEW_SSH_PORT (existing listeners retained)"; fi
    if [[ -n $PUBLIC_SSH_KEY ]]; then log 'Authorize supplied public SSH key.'; fi
}
