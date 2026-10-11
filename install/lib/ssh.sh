#!/usr/bin/env bash
# Additive SSH configuration: retain working ports, validate, and roll back failed activation.

ssh_ports() { "$SSHD" -T -f "$1" | awk '$1 == "port" { print $2 }' | sort -un; }

write_ssh_candidate() {
    {
        printf '# BEGIN DOTFILES INSTALLER\nAcceptEnv TMUX_AUTOSTART\n'
        local port
        while IFS= read -r port; do
            [[ -z $port ]] || printf 'Port %s\n' "$port"
        done <"$transaction/managed-ports"
        printf '# END DOTFILES INSTALLER\n'
        cat "$transaction/body"
    } >"$transaction/candidate"
}

prepare_ssh_socket() {
    [[ -n $socket_unit && -n $NEW_SSH_PORT ]] || return 0
    systemctl show "$socket_unit" --property=Listen --value >"$transaction/listen"
    sed 's/ (Stream)/\n/g' "$transaction/listen" | sed '/^[[:space:]]*$/d; s/^[[:space:]]*//' >"$transaction/endpoints"
    [[ -s $transaction/endpoints ]] || die 'Cannot determine existing SSH socket listeners.'
    if grep -Eq "(^|:)${NEW_SSH_PORT}$" "$transaction/endpoints"; then return 0; fi
    # Restart both units in one systemd transaction so the old daemon releases its listeners.
    # KillMode=process preserves established SSH session children during that restart.
    [[ $(systemctl show "$service_unit" --property=KillMode --value) == process ]] || die 'SSH socket changes require KillMode=process to preserve existing sessions.'
    socket_override="$unit_dir/$socket_unit.d/90-dotfiles-listen.conf"
    [[ ! -L $socket_override ]] || die 'Refusing to replace a symlinked systemd override.'
    mkdir -p "$(dirname "$socket_override")"
    if [[ -f $socket_override ]]; then cp -p "$socket_override" "$transaction/socket-original"; fi
    {
        printf '[Socket]\nListenStream=\n'
        while IFS= read -r endpoint; do printf 'ListenStream=%s\n' "$endpoint"; done <"$transaction/endpoints"
        # Add the new port on exactly the existing address families and interfaces.
        # A private or IPv4-only listener must not become a public or IPv6 listener.
        while IFS= read -r endpoint; do
            if valid_port "$endpoint"; then
                printf 'ListenStream=%s\n' "$NEW_SSH_PORT"
            elif [[ $endpoint == *:* ]] && valid_port "${endpoint##*:}"; then
                printf 'ListenStream=%s:%s\n' "${endpoint%:*}" "$NEW_SSH_PORT"
            else
                die "Unsupported SSH socket endpoint: $endpoint"
            fi
        done <"$transaction/endpoints"

    } | awk '!seen[$0]++' >"$transaction/socket-candidate"
}

ssh_rollback() {
    local status=$?
    trap - EXIT
    if [[ $status != 0 && $activated == true ]]; then
        warn 'SSH activation failed; restoring the previous configuration.'
        cp -p "$transaction/original" "$config"
        if [[ -n $socket_override ]]; then
            if [[ -f $transaction/socket-original ]]; then
                cp -p "$transaction/socket-original" "$socket_override"
            else rm -f "$socket_override"; fi
        fi
        systemctl daemon-reload || warn 'Could not reload systemd during rollback.'
        if [[ -f $transaction/socket-candidate ]]; then
            systemctl restart "$socket_unit" "$service_unit" || warn 'Could not restore SSH listeners; use the provider console.'
        else
            systemctl reload-or-restart "$service_unit" || warn 'Could not restore SSH; use the provider console.'
        fi
    fi
    rm -rf "$transaction"
    exit "$status"
}

configure_ssh() (
    local config=${1:-/etc/ssh/sshd_config} unit_dir=${2:-/etc/systemd/system}
    local transaction activated=false socket_unit='' socket_override='' service_unit=ssh.service
    local old_ports new_ports port endpoint
    SSHD=${SSHD:-/usr/sbin/sshd}
    [[ -f $config && ! -L $config ]] || die "Expected a regular SSH configuration: $config"
    "$SSHD" -t -f "$config"
    transaction=$(mktemp -d "$(dirname "$config")/.dotfiles-ssh.XXXXXX")
    trap ssh_rollback EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    cp -p "$config" "$transaction/original"
    if [[ $DISTRO == fedora ]]; then service_unit=sshd.service; fi
    for socket_unit in ssh.socket sshd.socket; do
        if systemctl is-active --quiet "$socket_unit"; then break; fi
        socket_unit=''
    done
    old_ports=$(ssh_ports "$config")
    awk '/^# BEGIN DOTFILES INSTALLER$/ { managed=1; next }
         /^# END DOTFILES INSTALLER$/ { managed=0; next }
         managed && $1 == "Port" { print $2 }' "$config" >"$transaction/managed-ports"
    awk '/^# BEGIN DOTFILES INSTALLER$/ { managed=1; next }
         /^# END DOTFILES INSTALLER$/ { managed=0; next }
         !managed { print }' "$config" >"$transaction/body"
    if [[ -n $NEW_SSH_PORT ]] && ! grep -qx "$NEW_SSH_PORT" <<<"$old_ports"; then
        printf '%s\n' "$NEW_SSH_PORT" >>"$transaction/managed-ports"
    fi
    write_ssh_candidate
    new_ports=$(ssh_ports "$transaction/candidate")
    # An explicit Port overrides sshd's implicit port 22. Preserve that listener too.
    while IFS= read -r port; do
        if ! grep -qx "$port" <<<"$new_ports"; then printf '%s\n' "$port" >>"$transaction/managed-ports"; fi
    done <<<"$old_ports"
    write_ssh_candidate
    "$SSHD" -t -f "$transaction/candidate"
    prepare_ssh_socket
    if [[ -z $socket_unit && -n $NEW_SSH_PORT ]]; then
        "$SSHD" -T -f "$transaction/candidate" | awk -v port="$NEW_SSH_PORT" '
            $1 == "listenaddress" { split($2, parts, ":"); if (parts[length(parts)] == port) found=1 }
            END { exit !found }' || die 'Explicit ListenAddress settings prevent the requested SSH port; update those bindings manually.'
    fi
    if cmp -s "$config" "$transaction/candidate" && [[ ! -f $transaction/socket-candidate ]]; then
        if [[ -z $socket_unit ]]; then
            systemctl is-active --quiet "$service_unit" || systemctl start "$service_unit"
        fi
        log 'SSH configuration is already current.'
        return 0
    fi

    if [[ -n $NEW_SSH_PORT ]] && { ! grep -qx "$NEW_SSH_PORT" <<<"$old_ports" || [[ -f $transaction/socket-candidate ]]; }; then
        if command -v getenforce >/dev/null 2>&1 && [[ $(getenforce) != Disabled ]]; then
            require_command semanage
            # Do not reassign a port owned by another SELinux service.
            if ! semanage port -l | awk -v p="$NEW_SSH_PORT" '$1 == "ssh_port_t" && $2 == "tcp" {
                for (i=3; i<=NF; i++) { gsub(/,/, "", $i); if ($i == p) found=1 }
            } END { exit !found }'; then
                semanage port -a -t ssh_port_t -p tcp "$NEW_SSH_PORT"
            fi
        fi
        if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
            firewall-cmd --add-port="$NEW_SSH_PORT/tcp"
            firewall-cmd --permanent --add-port="$NEW_SSH_PORT/tcp"
        elif command -v ufw >/dev/null 2>&1 && ufw status | grep -q '^Status: active'; then
            ufw allow "$NEW_SSH_PORT/tcp"
        fi

    fi

    activated=true
    [[ ! -L $config.dotfiles-backup ]] || die 'Refusing to overwrite a symlinked SSH backup.'
    cp -p "$config" "$config.dotfiles-backup"
    cat "$transaction/candidate" >"$config"
    if [[ -f $transaction/socket-candidate ]]; then
        install -m 644 "$transaction/socket-candidate" "$socket_override"
    fi
    "$SSHD" -t -f "$config"
    systemctl daemon-reload
    if [[ -f $transaction/socket-candidate ]]; then
        systemctl restart "$socket_unit" "$service_unit"
        systemctl is-active --quiet "$socket_unit"
        systemctl is-active --quiet "$service_unit"
    elif [[ -n $socket_unit ]]; then
        # An inactive socket-activated daemon reads the new config on its next start.
        if systemctl is-active --quiet "$service_unit"; then systemctl reload "$service_unit"; fi
    else
        systemctl reload-or-restart "$service_unit"
        systemctl is-active --quiet "$service_unit"
    fi
    activated=false
    if [[ -n $NEW_SSH_PORT ]]; then
        log "SSH port $NEW_SSH_PORT configured. Existing ports remain available. Check provider firewall rules and verify a new connection."
    fi
)
