#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2154 # sourced module intentionally consumes runtime globals from lib/globals_contract.sh

doctor_measurement_summary_tsv() {
    local summary_json
    summary_json=$(measurement_read_summary_json 2> /dev/null) || return 1
    jq -r '[
        (.field_verdict // "unknown"),
        (.operator_recommendation // "unknown"),
        (.operator_recommendation_reason // "n/a"),
        (.coverage_verdict // "unknown"),
        (.family_diversity_verdict // "unknown"),
        (.long_term_verdict // "unknown"),
        (.best_spare // "n/a"),
        (.best_spare_family // "n/a"),
        (.recommend_emergency // false | tostring)
    ] | @tsv' <<< "$summary_json"
}

doctor_runtime_service_state() {
    if declare -F systemctl_available > /dev/null 2>&1 && ! systemctl_available; then
        printf '%s\n' "no-systemd"
        return 0
    fi
    if declare -F systemd_running > /dev/null 2>&1 && ! systemd_running; then
        printf '%s\n' "no-systemd"
        return 0
    fi

    local state
    state=$(systemctl is-active xray 2> /dev/null || true)
    state=$(trim_ws "${state,,}")
    [[ -n "$state" ]] || state="unknown"
    printf '%s\n' "$state"
}

doctor_runtime_config_state() {
    [[ -f "$XRAY_CONFIG" ]] || {
        printf '%s\n' "missing"
        return 0
    }

    if declare -F xray_config_test_ok > /dev/null 2>&1; then
        if xray_config_test_ok "$XRAY_CONFIG" > /dev/null 2>&1; then
            printf '%s\n' "ok"
        else
            printf '%s\n' "invalid"
        fi
        return 0
    fi

    printf '%s\n' "present"
}

doctor_current_transport_label() {
    local transport="unknown"
    if declare -F detect_current_managed_transport > /dev/null 2>&1; then
        transport=$(detect_current_managed_transport 2> /dev/null || echo "unknown")
    elif [[ -n "${TRANSPORT:-}" ]]; then
        transport=$(transport_normalize "$TRANSPORT")
    fi
    printf '%s\n' "$transport"
}

doctor_installed_version() {
    if declare -F xray_installed_version > /dev/null 2>&1; then
        xray_installed_version 2> /dev/null || true
        return 0
    fi
    if [[ -x "$XRAY_BIN" ]]; then
        "$XRAY_BIN" version 2> /dev/null | head -1 | awk '{print $2}' | sed 's/^v//' || true
        return 0
    fi
    printf '%s\n' ""
}

doctor_has_managed_install() {
    if declare -F managed_install_contract_present > /dev/null 2>&1 && managed_install_contract_present; then
        return 0
    fi
    [[ -f "$XRAY_ENV" || -f "$XRAY_CONFIG" || -x "$XRAY_BIN" ]]
}

doctor_overall_verdict() {
    local managed_present="$1"
    local service_state="$2"
    local config_state="$3"
    local self_check_verdict="$4"
    local field_recommendation="$5"
    local coverage_verdict="$6"

    if [[ "$managed_present" != "true" ]]; then
        printf '%s\n' "not-installed"
        return 0
    fi

    if [[ "$config_state" == "invalid" || "$config_state" == "missing" ]]; then
        printf '%s\n' "broken"
        return 0
    fi

    case "$service_state" in
        active) ;;
        no-systemd)
            printf '%s\n' "warning"
            return 0
            ;;
        *)
            printf '%s\n' "broken"
            return 0
            ;;
    esac

    case "${self_check_verdict,,}" in
        broken)
            printf '%s\n' "broken"
            return 0
            ;;
        warning)
            printf '%s\n' "warning"
            return 0
            ;;
        *) ;;
    esac

    case "$field_recommendation" in
        promote-spare | field-test-emergency | watch-and-collect-more)
            printf '%s\n' "warning"
            return 0
            ;;
        collect-more-data)
            printf '%s\n' "warning"
            return 0
            ;;
        *) ;;
    esac

    if [[ "$coverage_verdict" != "ok" && "$coverage_verdict" != "unknown" ]]; then
        printf '%s\n' "warning"
        return 0
    fi

    printf '%s\n' "ok"
}

doctor_next_action() {
    local verdict="$1"
    local field_recommendation="$2"
    local recommend_emergency="$3"

    case "$verdict" in
        not-installed)
            printf '%s\n' "sudo xray-reality.sh install"
            ;;
        broken)
            printf '%s\n' "sudo xray-reality.sh repair --non-interactive --yes"
            ;;
        warning)
            case "$field_recommendation" in
                promote-spare)
                    printf '%s\n' "sudo xray-reality.sh update --replan --non-interactive --yes"
                    ;;
                field-test-emergency)
                    if [[ "$recommend_emergency" == "true" ]]; then
                        printf '%s\n' "save more field reports and verify only the emergency raw config on real clients"
                    else
                        printf '%s\n' "save more field reports before changing the primary order"
                    fi
                    ;;
                collect-more-data | watch-and-collect-more)
                    printf '%s\n' "save at least two field reports across different networks"
                    ;;
                *)
                    printf '%s\n' "sudo xray-reality.sh status --verbose"
                    ;;
            esac
            ;;
        *)
            printf '%s\n' "no immediate action"
            ;;
    esac
}

doctor_colored_verdict() {
    local verdict="${1:-unknown}"
    case "$verdict" in
        ok)
            printf '%b%s%b' "${GREEN:-}" "OK" "${NC:-}"
            ;;
        warning)
            printf '%b%s%b' "${YELLOW:-}" "WARNING" "${NC:-}"
            ;;
        broken)
            printf '%b%s%b' "${RED:-}" "BROKEN" "${NC:-}"
            ;;
        not-installed)
            printf '%b%s%b' "${CYAN:-}" "NOT INSTALLED" "${NC:-}"
            ;;
        *)
            printf '%b%s%b' "${DIM:-}" "UNKNOWN" "${NC:-}"
            ;;
    esac
}

doctor_flow() {
    local managed_present=false
    if doctor_has_managed_install; then
        managed_present=true
    fi

    local service_state="unknown"
    local config_state="missing"
    local transport="unknown"
    local installed_version=""
    local self_check_verdict="unknown"
    local self_check_action="n/a"
    local self_check_variant="n/a"
    local field_verdict="unknown"
    local field_recommendation="unknown"
    local field_reason="n/a"
    local coverage_verdict="unknown"
    local family_diversity="unknown"
    local long_term="unknown"
    local best_spare="n/a"
    local best_spare_family="n/a"
    local recommend_emergency="false"

    if [[ "$managed_present" == "true" ]]; then
        service_state=$(doctor_runtime_service_state)
        config_state=$(doctor_runtime_config_state)
        transport=$(doctor_current_transport_label)
        installed_version=$(doctor_installed_version)
    fi

    local self_check_summary=""
    if declare -F self_check_status_summary_tsv > /dev/null 2>&1; then
        self_check_summary=$(self_check_status_summary_tsv 2> /dev/null || true)
    fi
    if [[ -n "$self_check_summary" ]]; then
        IFS=$'\t' read -r self_check_verdict self_check_action _ _ self_check_variant _ _ _ <<< "$self_check_summary"
    fi

    local measurement_summary=""
    if declare -F doctor_measurement_summary_tsv > /dev/null 2>&1; then
        measurement_summary=$(doctor_measurement_summary_tsv 2> /dev/null || true)
    fi
    if [[ -n "$measurement_summary" ]]; then
        IFS=$'\t' read -r \
            field_verdict \
            field_recommendation \
            field_reason \
            coverage_verdict \
            family_diversity \
            long_term \
            best_spare \
            best_spare_family \
            recommend_emergency <<< "$measurement_summary"
    fi

    local overall_verdict next_action
    overall_verdict=$(doctor_overall_verdict "$managed_present" "$service_state" "$config_state" "$self_check_verdict" "$field_recommendation" "$coverage_verdict")
    next_action=$(doctor_next_action "$overall_verdict" "$field_recommendation" "$recommend_emergency")

    echo ""
    echo -e "${BOLD}${CYAN}$(ui_section_title_string "Doctor")${NC}"
    echo ""
    echo -e "Verdict: $(doctor_colored_verdict "$overall_verdict")"

    if [[ "$managed_present" != "true" ]]; then
        echo -e "Runtime: ${YELLOW}managed install not found${NC}"
        echo -e "Next action: ${BOLD}${next_action}${NC}"
        echo ""
        return 0
    fi

    echo -e "Runtime: service=${service_state}, config=${config_state}, transport=${transport}${installed_version:+, xray=${installed_version}}"
    if [[ -n "$self_check_summary" ]]; then
        echo -e "Self-check: ${self_check_verdict} (${self_check_action}, variant ${self_check_variant})"
    else
        echo -e "Self-check: ${YELLOW}no data${NC}"
    fi
    if [[ -n "$measurement_summary" ]]; then
        echo -e "Field: ${field_verdict} | ${field_recommendation}"
        echo -e "Field details: coverage=${coverage_verdict}, families=${family_diversity}, trend=${long_term}, best spare=${best_spare} [${best_spare_family}]"
        echo -e "Field reason: ${field_reason}"
    else
        echo -e "Field: ${YELLOW}no saved measurements${NC}"
    fi
    echo -e "Next action: ${BOLD}${next_action}${NC}"
    echo ""
}
