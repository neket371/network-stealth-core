#!/usr/bin/env bash
# shellcheck shell=bash

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
    local payload=""
    payload=$(operator_decision_payload_json 2> /dev/null || true)
    [[ -n "$payload" ]] || payload='{}'

    local overall_verdict next_action managed_present
    local service_state config_state transport installed_version
    local self_check_verdict self_check_action self_check_variant
    local field_verdict field_recommendation field_reason
    local coverage_verdict family_diversity long_term summary_state summary_state_reason
    local rotation_verdict weak_streak cooldown_families cooldown_domains
    local best_spare best_spare_family promotion_block_reason

    overall_verdict=$(jq -r '.overall_verdict // "unknown"' <<< "$payload" 2> /dev/null || echo "unknown")
    next_action=$(jq -r '.next_action // "n/a"' <<< "$payload" 2> /dev/null || echo "n/a")
    managed_present=$(jq -r '.runtime.managed_present // false' <<< "$payload" 2> /dev/null || echo false)
    service_state=$(jq -r '.runtime.service_state // "unknown"' <<< "$payload" 2> /dev/null || echo "unknown")
    config_state=$(jq -r '.runtime.config_state // "missing"' <<< "$payload" 2> /dev/null || echo "missing")
    transport=$(jq -r '.runtime.transport // "unknown"' <<< "$payload" 2> /dev/null || echo "unknown")
    installed_version=$(jq -r '.runtime.installed_version // empty' <<< "$payload" 2> /dev/null || true)
    self_check_verdict=$(jq -r '.self_check.verdict // "unknown"' <<< "$payload" 2> /dev/null || echo "unknown")
    self_check_action=$(jq -r '.self_check.action // "n/a"' <<< "$payload" 2> /dev/null || echo "n/a")
    self_check_variant=$(jq -r '.self_check.variant_key // "n/a"' <<< "$payload" 2> /dev/null || echo "n/a")
    field_verdict=$(jq -r '.field.field_verdict // "unknown"' <<< "$payload" 2> /dev/null || echo "unknown")
    field_recommendation=$(jq -r '.decision_recommendation // "unknown"' <<< "$payload" 2> /dev/null || echo "unknown")
    field_reason=$(jq -r '.decision_reason // "n/a"' <<< "$payload" 2> /dev/null || echo "n/a")
    coverage_verdict=$(jq -r '.field.coverage_verdict // "unknown"' <<< "$payload" 2> /dev/null || echo "unknown")
    family_diversity=$(jq -r '.field.family_diversity_verdict // "unknown"' <<< "$payload" 2> /dev/null || echo "unknown")
    long_term=$(jq -r '.field.long_term_verdict // "unknown"' <<< "$payload" 2> /dev/null || echo "unknown")
    summary_state=$(jq -r '.field.summary_state // "missing"' <<< "$payload" 2> /dev/null || echo "missing")
    summary_state_reason=$(jq -r '.field.summary_state_reason // empty' <<< "$payload" 2> /dev/null || true)
    rotation_verdict=$(jq -r '.field.rotation_verdict // "keep-current-primary"' <<< "$payload" 2> /dev/null || echo "keep-current-primary")
    weak_streak=$(jq -r '.field.primary_weak_streak // 0' <<< "$payload" 2> /dev/null || echo 0)
    cooldown_families=$(jq -r '(.field.cooldown_families // []) | join(", ")' <<< "$payload" 2> /dev/null || true)
    cooldown_domains=$(jq -r '(.field.cooldown_domains // []) | join(", ")' <<< "$payload" 2> /dev/null || true)
    best_spare=$(jq -r '.field.best_spare // "n/a"' <<< "$payload" 2> /dev/null || echo "n/a")
    best_spare_family=$(jq -r '.field.best_spare_family // "n/a"' <<< "$payload" 2> /dev/null || echo "n/a")
    promotion_block_reason=$(jq -r '.field.promotion_block_reason // empty' <<< "$payload" 2> /dev/null || true)

    echo ""
    echo -e "${BOLD:-}${CYAN:-}$(ui_section_title_string "Doctor")${NC:-}"
    echo ""
    echo -e "Verdict: $(doctor_colored_verdict "$overall_verdict")"

    if [[ "$managed_present" != "true" ]]; then
        echo -e "Runtime: ${YELLOW:-}managed install not found${NC:-}"
        echo -e "Next action: ${BOLD:-}${next_action}${NC:-}"
        echo ""
        return 0
    fi

    echo -e "Runtime: service=${service_state}, config=${config_state}, transport=${transport}${installed_version:+, xray=${installed_version}}"
    echo -e "Self-check: ${self_check_verdict} (${self_check_action}, variant ${self_check_variant})"
    echo -e "Field: ${field_verdict} | ${field_recommendation}"
    echo -e "Field details: coverage=${coverage_verdict}, families=${family_diversity}, trend=${long_term}, best spare=${best_spare} [${best_spare_family}]"
    if [[ "$summary_state" != "ok" ]]; then
        echo -e "Field summary: ${summary_state}${summary_state_reason:+ | ${summary_state_reason}}"
    fi
    echo -e "Rotation: ${rotation_verdict} | weak streak=${weak_streak}"
    if [[ -n "$cooldown_families" || -n "$cooldown_domains" ]]; then
        echo -e "Cooldowns: families=${cooldown_families:-none}, domains=${cooldown_domains:-none}"
    fi
    if [[ -n "$promotion_block_reason" ]]; then
        echo -e "Rotation block: ${promotion_block_reason}"
    fi
    echo -e "Reason: ${field_reason}"
    echo -e "Next action: ${BOLD:-}${next_action}${NC:-}"
    echo ""
}
