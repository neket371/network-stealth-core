#!/usr/bin/env bash
# shellcheck shell=bash

managed_install_needs_migrate_stealth() {
    local current_transport
    local xray_config="${XRAY_CONFIG:-/etc/xray/config.json}"
    current_transport=$(detect_current_managed_transport)
    if transport_is_legacy "$current_transport"; then
        return 0
    fi
    if [[ -f "$xray_config" ]] && command -v jq > /dev/null 2>&1; then
        if jq -e --arg flow "${XRAY_DIRECT_FLOW:-xtls-rprx-vision}" '
            [ .inbounds[]
              | select(.streamSettings.realitySettings != null)
              | select((.listen // "0.0.0.0") | test(":") | not)
              | ((.settings.decryption // "none") != "none")
                and ((.settings.clients[0].flow // "") == $flow)
            ] | all
        ' "$xray_config" > /dev/null 2>&1; then
            return 1
        fi
    fi
    return 0
}

require_xhttp_transport_contract_for_action() {
    local action="${1:-$ACTION}"
    case "$action" in
        install)
            if transport_is_legacy "${TRANSPORT:-xhttp}"; then
                log ERROR "v7 больше не устанавливает grpc/http2 профили"
                log ERROR "используйте xhttp по умолчанию"
                return 1
            fi
            return 0
            ;;
        update | repair | add-clients | add-keys)
            local current_transport
            current_transport=$(detect_current_managed_transport)
            if managed_install_needs_migrate_stealth; then
                log ERROR "обнаружен managed install без strongest direct contract (${current_transport}); действие '${action}' заблокировано в v7"
                log ERROR "сначала выполните: xray-reality.sh migrate-stealth --non-interactive --yes"
                return 1
            fi
            return 0
            ;;
        *)
            return 0
            ;;
    esac
}
