#!/usr/bin/env bash
# shellcheck shell=bash

GLOBAL_CONTRACT_MODULE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/globals_contract.sh"
if [[ ! -f "$GLOBAL_CONTRACT_MODULE" && "${XRAY_SOURCE_TREE_STRICT:-false}" != "true" && -n "${XRAY_DATA_DIR:-}" ]]; then
    GLOBAL_CONTRACT_MODULE="$XRAY_DATA_DIR/modules/lib/globals_contract.sh"
fi
if [[ ! -f "$GLOBAL_CONTRACT_MODULE" ]]; then
    echo "ERROR: не найден модуль global contract: $GLOBAL_CONTRACT_MODULE" >&2
    exit 1
fi
# shellcheck source=modules/lib/globals_contract.sh
source "$GLOBAL_CONTRACT_MODULE"

open_firewall_ports() {
    local ports_v4_list="${1:-}"
    local ports_v6_list="${2:-}"
    local -a ports_v4=()
    local -a ports_v6=()
    local port

    if [[ -n "$ports_v4_list" ]]; then
        # shellcheck disable=SC2206
        ports_v4=($ports_v4_list)
    fi
    if [[ -n "$ports_v6_list" ]]; then
        # shellcheck disable=SC2206
        ports_v6=($ports_v6_list)
    fi
    local fw_status="ok"
    if command -v ufw > /dev/null 2>&1; then
        for port in "${ports_v4[@]}"; do
            [[ -n "$port" ]] || continue
            if ufw status 2> /dev/null | grep -Eq "^${port}/tcp([[:space:]]|$).*ALLOW"; then
                continue
            fi
            if ufw allow "${port}/tcp" comment "Network Stealth Core" > /dev/null 2>&1; then
                record_firewall_rule_add "ufw" "$port" "v4" || true
            else
                fw_status="partial"
            fi
        done
        for port in "${ports_v6[@]}"; do
            [[ -n "$port" ]] || continue
            if ufw status 2> /dev/null | grep -Eq "^${port}/tcp([[:space:]]|$).*ALLOW"; then
                continue
            fi
            if ufw allow "${port}/tcp" comment "Network Stealth Core" > /dev/null 2>&1; then
                record_firewall_rule_add "ufw" "$port" "v6" || true
            else
                fw_status="partial"
            fi
        done
    elif command -v firewall-cmd > /dev/null 2>&1; then
        local fw_changed=false
        for port in "${ports_v4[@]}"; do
            [[ -n "$port" ]] || continue
            if firewall-cmd --permanent --query-port="${port}/tcp" > /dev/null 2>&1; then
                continue
            fi
            if firewall-cmd --permanent --add-port="${port}/tcp" > /dev/null 2>&1; then
                record_firewall_rule_add "firewalld" "$port" "v4" || true
                fw_changed=true
            else
                fw_status="partial"
            fi
        done
        for port in "${ports_v6[@]}"; do
            [[ -n "$port" ]] || continue
            if firewall-cmd --permanent --query-port="${port}/tcp" > /dev/null 2>&1; then
                continue
            fi
            if firewall-cmd --permanent --add-port="${port}/tcp" > /dev/null 2>&1; then
                record_firewall_rule_add "firewalld" "$port" "v6" || true
                fw_changed=true
            else
                fw_status="partial"
            fi
        done
        if [[ "$fw_changed" == true ]]; then
            if ! firewall-cmd --reload > /dev/null 2>&1; then
                fw_status="partial"
            fi
        fi
    elif command -v iptables > /dev/null 2>&1; then
        local ipt_err
        for port in "${ports_v4[@]}"; do
            [[ -n "$port" ]] || continue
            if ! iptables -C INPUT -p tcp --dport "$port" -j ACCEPT 2> /dev/null; then
                if ipt_err=$(iptables -A INPUT -p tcp --dport "$port" -j ACCEPT 2>&1); then
                    record_firewall_rule_add "iptables" "$port" "v4" || true
                else
                    debug_file "iptables error for port $port: $ipt_err"
                    fw_status="partial"
                fi
            fi
        done
        if [[ ${#ports_v6[@]} -gt 0 ]]; then
            if command -v ip6tables > /dev/null 2>&1; then
                for port in "${ports_v6[@]}"; do
                    [[ -n "$port" ]] || continue
                    if ! ip6tables -C INPUT -p tcp --dport "$port" -j ACCEPT 2> /dev/null; then
                        if ipt_err=$(ip6tables -A INPUT -p tcp --dport "$port" -j ACCEPT 2>&1); then
                            record_firewall_rule_add "ip6tables" "$port" "v6" || true
                        else
                            debug_file "ip6tables error for port $port: $ipt_err"
                            fw_status="partial"
                        fi
                    fi
                done
            else
                fw_status="partial"
            fi
        fi
        if command -v netfilter-persistent > /dev/null 2>&1; then
            if ! netfilter-persistent save > /dev/null 2>&1; then
                fw_status="partial"
            fi
        elif command -v iptables-save > /dev/null 2>&1 && [[ -d /etc/iptables ]]; then
            if ! iptables-save > /etc/iptables/rules.v4 2> /dev/null; then
                fw_status="partial"
            fi
            if [[ ${#ports_v6[@]} -gt 0 ]] && command -v ip6tables-save > /dev/null 2>&1; then
                if ! ip6tables-save > /etc/iptables/rules.v6 2> /dev/null; then
                    fw_status="partial"
                fi
            fi
        fi
    else
        fw_status="skipped"
    fi

    printf '%s\n' "$fw_status"
    return 0
}

record_firewall_rule_add() {
    local backend="${1:-}"
    local port="${2:-}"
    local family="${3:-v4}"
    if [[ -z "$backend" || -z "$port" ]]; then
        return 1
    fi
    FIREWALL_ROLLBACK_ENTRIES+=("${backend}|${port}|${family}")
    if [[ "$backend" == "firewalld" ]]; then
        FIREWALL_FIREWALLD_DIRTY=true
    fi
    return 0
}

rollback_firewall_changes() {
    if [[ ${#FIREWALL_ROLLBACK_ENTRIES[@]} -eq 0 ]]; then
        return 0
    fi

    log WARN "Откатываем изменения файрвола..."
    local i entry backend port family
    for ((i = ${#FIREWALL_ROLLBACK_ENTRIES[@]} - 1; i >= 0; i--)); do
        entry="${FIREWALL_ROLLBACK_ENTRIES[$i]}"
        IFS='|' read -r backend port family <<< "$entry"
        case "$backend" in
            ufw)
                if command -v ufw > /dev/null 2>&1; then
                    if ufw --force delete allow "${port}/tcp" > /dev/null 2>&1; then
                        log INFO "Откат файрвола: закрыт ${port}/tcp (ufw)"
                    fi
                fi
                ;;
            firewalld)
                if command -v firewall-cmd > /dev/null 2>&1; then
                    if firewall-cmd --permanent --remove-port="${port}/tcp" > /dev/null 2>&1; then
                        log INFO "Откат файрвола: удалён ${port}/tcp (firewalld)"
                    fi
                fi
                ;;
            iptables)
                if command -v iptables > /dev/null 2>&1; then
                    if iptables -D INPUT -p tcp --dport "$port" -j ACCEPT > /dev/null 2>&1; then
                        log INFO "Откат файрвола: удалён ${port}/tcp (iptables)"
                    fi
                fi
                ;;
            ip6tables)
                if command -v ip6tables > /dev/null 2>&1; then
                    if ip6tables -D INPUT -p tcp --dport "$port" -j ACCEPT > /dev/null 2>&1; then
                        log INFO "Откат файрвола: удалён ${port}/tcp (ip6tables)"
                    fi
                fi
                ;;
            *) ;;
        esac
    done

    if [[ "$FIREWALL_FIREWALLD_DIRTY" == "true" ]] && command -v firewall-cmd > /dev/null 2>&1; then
        if ! firewall-cmd --reload > /dev/null 2>&1; then
            log WARN "Не удалось перезагрузить firewalld при rollback"
        fi
    fi

    FIREWALL_ROLLBACK_ENTRIES=()
    FIREWALL_FIREWALLD_DIRTY=false
    return 0
}
