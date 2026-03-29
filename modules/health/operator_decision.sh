#!/usr/bin/env bash
# shellcheck shell=bash

GLOBAL_CONTRACT_MODULE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../lib" && pwd)/globals_contract.sh"
if [[ ! -f "$GLOBAL_CONTRACT_MODULE" && "${XRAY_SOURCE_TREE_STRICT:-false}" != "true" && -n "${XRAY_DATA_DIR:-}" ]]; then
    GLOBAL_CONTRACT_MODULE="$XRAY_DATA_DIR/modules/lib/globals_contract.sh"
fi
if [[ ! -f "$GLOBAL_CONTRACT_MODULE" ]]; then
    echo "ERROR: не найден модуль global contract: $GLOBAL_CONTRACT_MODULE" >&2
    exit 1
fi
# shellcheck source=modules/lib/globals_contract.sh
source "$GLOBAL_CONTRACT_MODULE"

OPERATOR_DECISION_MEASUREMENTS_MODULE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/measurements.sh"
if [[ ! -f "$OPERATOR_DECISION_MEASUREMENTS_MODULE" && "${XRAY_SOURCE_TREE_STRICT:-false}" != "true" && -n "${XRAY_DATA_DIR:-}" ]]; then
    OPERATOR_DECISION_MEASUREMENTS_MODULE="$XRAY_DATA_DIR/modules/health/measurements.sh"
fi
if [[ ! -f "$OPERATOR_DECISION_MEASUREMENTS_MODULE" ]]; then
    echo "ERROR: не найден модуль measurements: $OPERATOR_DECISION_MEASUREMENTS_MODULE" >&2
    exit 1
fi
# shellcheck source=modules/health/measurements.sh
source "$OPERATOR_DECISION_MEASUREMENTS_MODULE"

OPERATOR_DECISION_SELF_CHECK_MODULE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/self_check.sh"
if [[ ! -f "$OPERATOR_DECISION_SELF_CHECK_MODULE" && "${XRAY_SOURCE_TREE_STRICT:-false}" != "true" && -n "${XRAY_DATA_DIR:-}" ]]; then
    OPERATOR_DECISION_SELF_CHECK_MODULE="$XRAY_DATA_DIR/modules/health/self_check.sh"
fi
if [[ ! -f "$OPERATOR_DECISION_SELF_CHECK_MODULE" ]]; then
    echo "ERROR: не найден модуль self-check: $OPERATOR_DECISION_SELF_CHECK_MODULE" >&2
    exit 1
fi
# shellcheck source=modules/health/self_check.sh
source "$OPERATOR_DECISION_SELF_CHECK_MODULE"

operator_runtime_service_state() {
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

operator_runtime_config_state() {
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

operator_current_transport_label() {
    local transport="unknown"
    if declare -F detect_current_managed_transport > /dev/null 2>&1; then
        transport=$(detect_current_managed_transport 2> /dev/null || echo "unknown")
    elif [[ -n "${TRANSPORT:-}" ]]; then
        transport=$(transport_normalize "$TRANSPORT")
    fi
    printf '%s\n' "$transport"
}

operator_installed_version() {
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

operator_has_managed_install() {
    if declare -F managed_install_contract_present > /dev/null 2>&1 && managed_install_contract_present; then
        return 0
    fi
    [[ -f "$XRAY_ENV" || -f "$XRAY_CONFIG" || -x "$XRAY_BIN" ]]
}

operator_runtime_state_json() {
    local managed_present=false
    if operator_has_managed_install; then
        managed_present=true
    fi

    local service_state="unknown"
    local config_state="missing"
    local transport="unknown"
    local installed_version=""
    if [[ "$managed_present" == "true" ]]; then
        service_state=$(operator_runtime_service_state)
        config_state=$(operator_runtime_config_state)
        transport=$(operator_current_transport_label)
        installed_version=$(operator_installed_version)
    fi

    jq -n \
        --argjson managed_present "$managed_present" \
        --arg service_state "$service_state" \
        --arg config_state "$config_state" \
        --arg transport "$transport" \
        --arg installed_version "$installed_version" \
        '{
            managed_present: $managed_present,
            service_state: $service_state,
            config_state: $config_state,
            transport: $transport,
            installed_version: (if ($installed_version | length) > 0 then $installed_version else null end)
        }'
}

operator_self_check_summary_json() {
    local summary=""
    if declare -F self_check_status_summary_tsv > /dev/null 2>&1; then
        summary=$(self_check_status_summary_tsv 2> /dev/null || true)
    fi

    if [[ -z "$summary" ]]; then
        jq -n '{
            verdict: "unknown",
            action: "n/a",
            checked_at: null,
            config_name: null,
            variant_key: null,
            variant_mode: null,
            variant_family: null,
            latency_ms: null
        }'
        return 0
    fi

    local verdict action checked_at config_name variant_key variant_mode variant_family latency_ms
    IFS=$'\t' read -r verdict action checked_at config_name variant_key variant_mode variant_family latency_ms <<< "$summary"
    jq -n \
        --arg verdict "${verdict,,}" \
        --arg action "$action" \
        --arg checked_at "$checked_at" \
        --arg config_name "$config_name" \
        --arg variant_key "$variant_key" \
        --arg variant_mode "$variant_mode" \
        --arg variant_family "$variant_family" \
        --arg latency_ms "$latency_ms" \
        '{
            verdict: (if ($verdict | length) > 0 then $verdict else "unknown" end),
            action: (if ($action | length) > 0 then $action else "n/a" end),
            checked_at: (if ($checked_at | length) > 0 then $checked_at else null end),
            config_name: (if ($config_name | length) > 0 then $config_name else null end),
            variant_key: (if ($variant_key | length) > 0 then $variant_key else null end),
            variant_mode: (if ($variant_mode | length) > 0 then $variant_mode else null end),
            variant_family: (if ($variant_family | length) > 0 then $variant_family else null end),
            latency_ms: (if ($latency_ms | length) > 0 then ($latency_ms | tonumber? // null) else null end)
        }'
}

operator_field_summary_json() {
    local summary_status_json="" summary_state="" summary_reason="" summary_file=""
    summary_status_json=$(measurement_summary_status_json 2> /dev/null || true)
    summary_state=$(jq -r '.state // "missing"' <<< "$summary_status_json" 2> /dev/null || echo "missing")
    summary_reason=$(jq -r '.reason // empty' <<< "$summary_status_json" 2> /dev/null || true)
    summary_file=$(jq -r '.summary_file // empty' <<< "$summary_status_json" 2> /dev/null || true)

    if [[ "$summary_state" == "ok" ]]; then
        jq -c \
            --arg summary_state "$summary_state" \
            --arg summary_file "$summary_file" \
            '.summary + {
                summary_state: $summary_state,
                summary_state_reason: null,
                summary_file: (if ($summary_file | length) > 0 then $summary_file else null end)
            }' <<< "$summary_status_json"
        return 0
    fi

    jq -n \
        --arg summary_state "$summary_state" \
        --arg summary_reason "$summary_reason" \
        --arg summary_file "$summary_file" '
        {
        field_verdict: "unknown",
        operator_recommendation: "unknown",
        operator_recommendation_reason: (if ($summary_reason | length) > 0 then $summary_reason else "n/a" end),
        coverage_verdict: "unknown",
        family_diversity_verdict: "unknown",
        long_term_verdict: "unknown",
        current_primary: null,
        current_primary_family: null,
        current_primary_stats: null,
        best_spare: null,
        best_spare_family: null,
        best_spare_stats: null,
        report_count: 0,
        network_tag_count: 0,
        provider_count: 0,
        region_count: 0,
        recommend_emergency: false,
        rotation_verdict: "collect-more-data",
        primary_weak_streak: 0,
        cooldown_families: [],
        cooldown_domains: [],
        promotion_candidate: null,
        promotion_block_reason: null,
        summary_state: $summary_state,
        summary_state_reason: (if ($summary_reason | length) > 0 then $summary_reason else null end),
        rotation_state_status: "unknown",
        rotation_state_reason: null,
        rotation_state_file: null,
        summary_file: (if ($summary_file | length) > 0 then $summary_file else null end),
        rotation_state: {
            primary_weak_streak: 0,
            cooldown_families: [],
            cooldown_domains: []
        }
    }'
}

operator_decision_overall_verdict() {
    local managed_present="$1"
    local service_state="$2"
    local config_state="$3"
    local self_check_verdict="$4"
    local decision_recommendation="$5"
    local coverage_verdict="$6"
    local summary_state="${7:-missing}"
    local rotation_state_status="${8:-missing}"

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

    if [[ "$summary_state" == "invalid" ]]; then
        printf '%s\n' "warning"
        return 0
    fi
    if [[ "$rotation_state_status" == "invalid" ]]; then
        printf '%s\n' "warning"
        return 0
    fi

    case "$decision_recommendation" in
        promote-spare | field-test-emergency | collect-more-data | watch-and-collect-more | hold-cooldown)
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

operator_decision_next_action() {
    local overall_verdict="$1"
    local decision_recommendation="$2"
    local recommend_emergency="$3"
    local summary_state="${4:-missing}"
    local rotation_state_status="${5:-missing}"

    case "$overall_verdict" in
        not-installed)
            printf '%s\n' "sudo xray-reality.sh install"
            ;;
        broken)
            printf '%s\n' "sudo xray-reality.sh repair --non-interactive --yes"
            ;;
        warning)
            if [[ "$summary_state" == "invalid" ]]; then
                printf '%s\n' "rebuild or reimport saved field reports before trusting promotion decisions"
                return 0
            fi
            if [[ "$rotation_state_status" == "invalid" ]]; then
                printf '%s\n' "reset or rebuild saved rotation state before trusting promotion decisions"
                return 0
            fi
            case "$decision_recommendation" in
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
                hold-cooldown)
                    printf '%s\n' "keep the current primary until cooldown expires and collect more field reports"
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

operator_decision_payload_json() {
    local runtime_json self_check_json field_json
    runtime_json=$(operator_runtime_state_json)
    self_check_json=$(operator_self_check_summary_json)
    field_json=$(operator_field_summary_json)

    local managed_present service_state config_state self_check_verdict decision_recommendation coverage_verdict recommend_emergency overall_verdict next_action summary_state rotation_state_status
    managed_present=$(jq -r '.managed_present' <<< "$runtime_json")
    service_state=$(jq -r '.service_state // "unknown"' <<< "$runtime_json")
    config_state=$(jq -r '.config_state // "missing"' <<< "$runtime_json")
    self_check_verdict=$(jq -r '.verdict // "unknown"' <<< "$self_check_json")
    coverage_verdict=$(jq -r '.coverage_verdict // "unknown"' <<< "$field_json")
    recommend_emergency=$(jq -r '.recommend_emergency // false' <<< "$field_json")
    summary_state=$(jq -r '.summary_state // "missing"' <<< "$field_json")
    rotation_state_status=$(jq -r '.rotation_state_status // "missing"' <<< "$field_json")

    decision_recommendation=$(jq -r '
        if (.promotion_candidate // null) != null then
            "promote-spare"
        elif (.promotion_block_reason // null) != null then
            "hold-cooldown"
        else
            (.operator_recommendation // "unknown")
        end
    ' <<< "$field_json")

    if [[ "$rotation_state_status" == "invalid" ]]; then
        decision_recommendation="hold-cooldown"
    fi

    if [[ "$decision_recommendation" == "promote-spare" ]] && [[ "${self_check_verdict,,}" != "broken" ]]; then
        if ! jq -e '(.primary_weak_streak // 0) >= 2' <<< "$field_json" > /dev/null 2>&1; then
            decision_recommendation=$(jq -r '.operator_recommendation // "unknown"' <<< "$field_json")
        fi
    fi

    overall_verdict=$(operator_decision_overall_verdict \
        "$managed_present" \
        "$service_state" \
        "$config_state" \
        "$self_check_verdict" \
        "$decision_recommendation" \
        "$coverage_verdict" \
        "$summary_state" \
        "$rotation_state_status")
    next_action=$(operator_decision_next_action "$overall_verdict" "$decision_recommendation" "$recommend_emergency" "$summary_state" "$rotation_state_status")

    jq -n \
        --argjson runtime "$runtime_json" \
        --argjson self_check "$self_check_json" \
        --argjson field "$field_json" \
        --arg decision_recommendation "$decision_recommendation" \
        --arg overall_verdict "$overall_verdict" \
        --arg next_action "$next_action" \
        '{
            runtime: $runtime,
            self_check: $self_check,
            field: $field,
            decision_recommendation: $decision_recommendation,
            decision_reason: (
                if (($field.summary_state // "missing") == "invalid") then
                    ($field.summary_state_reason // "saved measurement summary is invalid")
                elif (($field.rotation_state_status // "missing") == "invalid") then
                    ($field.rotation_state_reason // "saved rotation state is invalid")
                elif $decision_recommendation == "promote-spare" then
                    ($field.promotion_candidate.reason // $field.operator_recommendation_reason // "n/a")
                elif $decision_recommendation == "hold-cooldown" then
                    ($field.promotion_block_reason // "cooldown is still active")
                else
                    ($field.operator_recommendation_reason // "n/a")
                end
            ),
            overall_verdict: $overall_verdict,
            next_action: $next_action
        }'
}

operator_rotation_apply_observations() {
    local action_name="${1:-runtime-mutation}"
    local summary_json state_json last_verdict warning_streak weak_signal=false
    summary_json=$(operator_field_summary_json)
    state_json=$(measurement_rotation_state_resolved_json "$summary_json")
    last_verdict=$(self_check_last_verdict 2> /dev/null || echo "unknown")
    warning_streak=$(self_check_warning_streak_count 2> /dev/null || echo 0)
    [[ "$warning_streak" =~ ^[0-9]+$ ]] || warning_streak=0

    local current_primary current_family current_domain previous_primary previous_streak promotion_candidate_json promotion_block_reason
    current_primary=$(jq -r '.current_primary // empty' <<< "$summary_json")
    current_family=$(jq -r '.current_primary_family // .current_primary_stats.provider_family // empty' <<< "$summary_json")
    current_domain=$(jq -r '.current_primary_domain // .current_primary_stats.domain // empty' <<< "$summary_json")
    previous_primary=$(jq -r '.current_primary // empty' <<< "$state_json")
    previous_streak=$(jq -r '.primary_weak_streak // 0' <<< "$state_json")
    [[ "$previous_streak" =~ ^[0-9]+$ ]] || previous_streak=0
    promotion_candidate_json=$(jq -c '.promotion_candidate // null' <<< "$summary_json")
    promotion_block_reason=$(jq -r '.promotion_block_reason // empty' <<< "$summary_json")

    if [[ "$last_verdict" == "broken" ]]; then
        weak_signal=true
    elif ((warning_streak >= 2)); then
        weak_signal=true
    elif jq -e '
        ((.field_verdict // "unknown") == "broken")
        or (
            ((.current_primary_stats.recommended_success_rate_last5 // 0) < 60)
            and ((.current_primary_stats.rescue_success_rate_last5 // 0) < 80)
        )
    ' <<< "$summary_json" > /dev/null 2>&1; then
        weak_signal=true
    fi

    state_json=$(jq --arg now "$(measurement_now_utc)" '
        .generated = $now
        | .cooldown_families = (
            (.cooldown_families // [])
            | map(.remaining_actions = (((.remaining_actions // 0) | if type == "number" then . else 0 end) - 1))
            | map(select(.remaining_actions > 0))
        )
        | .cooldown_domains = (
            (.cooldown_domains // [])
            | map(.remaining_actions = (((.remaining_actions // 0) | if type == "number" then . else 0 end) - 1))
            | map(select(.remaining_actions > 0))
        )
    ' <<< "$state_json")

    if [[ -n "$current_primary" && "$previous_primary" != "$current_primary" ]]; then
        previous_streak=0
    fi

    local next_streak=0
    if [[ "$weak_signal" == "true" ]]; then
        next_streak=$((previous_streak + 1))
    fi

    local should_promote=false
    local promotion_name="" promotion_reason="" promotion_family="" promotion_domain=""
    if [[ -n "$promotion_candidate_json" && "$promotion_candidate_json" != "null" && -z "$promotion_block_reason" ]]; then
        promotion_name=$(jq -r '.config_name // empty' <<< "$promotion_candidate_json")
        promotion_reason=$(jq -r '.reason // empty' <<< "$promotion_candidate_json")
        promotion_family=$(jq -r '.candidate_provider_family // empty' <<< "$promotion_candidate_json")
        promotion_domain=$(jq -r '.candidate_domain // empty' <<< "$promotion_candidate_json")
        if [[ "$last_verdict" == "broken" || "$next_streak" -ge 2 ]]; then
            should_promote=true
        fi
    fi

    local stable_snapshot="null"
    if [[ "$weak_signal" != "true" ]] && jq -e '(.field_verdict // "unknown") != "unknown"' <<< "$summary_json" > /dev/null 2>&1; then
        stable_snapshot=$(jq -c '{
            generated: .generated,
            current_primary: .current_primary,
            current_primary_family: .current_primary_family,
            current_primary_domain: .current_primary_domain,
            recommended_success_rate_last5: (.current_primary_stats.recommended_success_rate_last5 // 0),
            rescue_success_rate_last5: (.current_primary_stats.rescue_success_rate_last5 // 0),
            trend_verdict: (.current_primary_stats.trend_verdict // "unknown"),
            field_verdict: (.field_verdict // "unknown")
        }' <<< "$summary_json")
    fi

    if [[ "$should_promote" == "true" && -n "$promotion_name" && "$promotion_name" != "$current_primary" ]]; then
        state_json=$(jq \
            --arg current_primary "$promotion_name" \
            --arg current_family "$promotion_family" \
            --arg current_domain "$promotion_domain" \
            --arg degrade_family "$current_family" \
            --arg degrade_domain "$current_domain" \
            --arg promotion_reason "$promotion_reason" \
            --argjson stable_snapshot "$stable_snapshot" '
            .current_primary = (if ($current_primary | length) > 0 then $current_primary else .current_primary end)
            | .current_primary_family = (if ($current_family | length) > 0 then $current_family else .current_primary_family end)
            | .current_primary_domain = (if ($current_domain | length) > 0 then $current_domain else .current_primary_domain end)
            | .primary_weak_streak = 0
            | .last_promotion_reason = (if ($promotion_reason | length) > 0 then $promotion_reason else .last_promotion_reason end)
            | .last_stable_summary_snapshot = (if $stable_snapshot != null then $stable_snapshot else .last_stable_summary_snapshot end)
            | .cooldown_families = (
                (.cooldown_families // [])
                | map(select(.family != $degrade_family))
                + (if ($degrade_family | length) > 0 then [{family: $degrade_family, reason: "rotated-away-weak-primary", remaining_actions: 2}] else [] end)
            )
            | .cooldown_domains = (
                (.cooldown_domains // [])
                | map(select(.domain != $degrade_domain))
                + (if ($degrade_domain | length) > 0 then [{domain: $degrade_domain, reason: "rotated-away-weak-primary", remaining_actions: 2}] else [] end)
            )
        ' <<< "$state_json")
    else
        state_json=$(jq \
            --arg current_primary "$current_primary" \
            --arg current_family "$current_family" \
            --arg current_domain "$current_domain" \
            --argjson next_streak "$next_streak" \
            --argjson stable_snapshot "$stable_snapshot" '
            .current_primary = (if ($current_primary | length) > 0 then $current_primary else .current_primary end)
            | .current_primary_family = (if ($current_family | length) > 0 then $current_family else .current_primary_family end)
            | .current_primary_domain = (if ($current_domain | length) > 0 then $current_domain else .current_primary_domain end)
            | .primary_weak_streak = $next_streak
            | .last_stable_summary_snapshot = (if $stable_snapshot != null then $stable_snapshot else .last_stable_summary_snapshot end)
        ' <<< "$state_json")
    fi

    measurement_write_rotation_state_json "$state_json"

    jq -n \
        --arg action_name "$action_name" \
        --argjson should_promote "$should_promote" \
        --arg promotion_name "$promotion_name" \
        --arg promotion_reason "$promotion_reason" \
        --arg promotion_block_reason "$promotion_block_reason" \
        --argjson next_streak "$next_streak" \
        --argjson state "$(measurement_rotation_state_resolved_json "$summary_json")" \
        '{
            action: $action_name,
            should_promote: $should_promote,
            promotion_name: (if ($promotion_name | length) > 0 then $promotion_name else null end),
            promotion_reason: (if ($promotion_reason | length) > 0 then $promotion_reason else null end),
            promotion_block_reason: (if ($promotion_block_reason | length) > 0 then $promotion_block_reason else null end),
            primary_weak_streak: $next_streak,
            rotation_state: $state
        }'
}
