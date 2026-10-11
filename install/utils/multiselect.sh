#!/usr/bin/env bash
# Compatibility helper: multiselect SHOW_HELP RESULT_ARRAY OPTIONS_ARRAY [DEFAULTS_ARRAY].
# Bash 4.3+ is required for namerefs. The installers themselves support Bash 3.2.
multiselect() {
    if ((BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 3))); then
        printf 'multiselect requires Bash 4.3 or newer.\n' >&2
        return 1
    fi
    [[ $# == 3 || $# == 4 ]] || {
        printf 'Expected 3 or 4 arguments.\n' >&2
        return 1
    }
    local _ms_name
    for _ms_name in "${@:2}"; do
        [[ $_ms_name =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ && $_ms_name != _ms_* ]] || {
            printf 'Invalid array variable name.\n' >&2
            return 1
        }
    done
    [[ $2 != "$3" && $2 != "${4:-}" ]] || {
        printf 'Result must be a separate array.\n' >&2
        return 1
    }
    local -n _ms_result=$2 _ms_options=$3
    if [[ $# == 4 ]]; then local -n _ms_defaults=$4; else local -a _ms_defaults=(); fi
    local _ms_index _ms_input _ms_number _ms_valid
    local _ms_numbers=()
    _ms_result=()
    for _ms_index in "${!_ms_options[@]}"; do _ms_result[_ms_index]=${_ms_defaults[_ms_index]:-false}; done
    if [[ $1 == true ]]; then printf 'Enter space-separated option numbers to toggle; Enter confirms; q cancels.\n'; fi
    while :; do
        for _ms_index in "${!_ms_options[@]}"; do
            printf '%s. [%s] %s\n' "$((_ms_index + 1))" "${_ms_result[_ms_index]}" "${_ms_options[_ms_index]}"
        done
        IFS= read -r _ms_input || return 1
        [[ -n $_ms_input ]] || return 0
        [[ $_ms_input != q ]] || return 1
        read -r -a _ms_numbers <<<"$_ms_input"
        _ms_valid=true
        for _ms_number in "${_ms_numbers[@]}"; do
            if [[ ! $_ms_number =~ ^[1-9][0-9]{0,4}$ ]] || ((10#$_ms_number > ${#_ms_options[@]})); then
                _ms_valid=false
                break
            fi
        done
        if [[ $_ms_valid != true ]]; then
            printf 'Invalid selection.\n' >&2
            continue
        fi
        for _ms_number in "${_ms_numbers[@]}"; do
            _ms_index=$((10#$_ms_number - 1))
            if [[ ${_ms_result[_ms_index]} == true ]]; then _ms_result[_ms_index]=false; else _ms_result[_ms_index]=true; fi
        done
    done
}
