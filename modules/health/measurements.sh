#!/usr/bin/env bash
# shellcheck shell=bash

GLOBAL_CONTRACT_MODULE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../lib" && pwd)/globals_contract.sh"
if [[ ! -f "$GLOBAL_CONTRACT_MODULE" && -n "${XRAY_DATA_DIR:-}" ]]; then
    GLOBAL_CONTRACT_MODULE="$XRAY_DATA_DIR/modules/lib/globals_contract.sh"
fi
if [[ ! -f "$GLOBAL_CONTRACT_MODULE" ]]; then
    echo "ERROR: не найден модуль global contract: $GLOBAL_CONTRACT_MODULE" >&2
    exit 1
fi
# shellcheck source=modules/lib/globals_contract.sh
source "$GLOBAL_CONTRACT_MODULE"

MEASUREMENTS_MODULE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MEASUREMENTS_AGGREGATE_JQ="${MEASUREMENTS_MODULE_DIR}/measurements_aggregate.jq"
if [[ ! -f "$MEASUREMENTS_AGGREGATE_JQ" && -n "${XRAY_DATA_DIR:-}" ]]; then
    MEASUREMENTS_AGGREGATE_JQ="$XRAY_DATA_DIR/modules/health/measurements_aggregate.jq"
fi

measurement_now_utc() {
    date -u '+%Y-%m-%dT%H:%M:%SZ'
}

measurement_reports_dir_path() {
    printf '%s\n' "${MEASUREMENTS_DIR:-/var/lib/xray/measurements}"
}

measurement_summary_file_path() {
    printf '%s\n' "${MEASUREMENTS_SUMMARY_FILE:-/var/lib/xray/measurements/latest-summary.json}"
}

measurement_rotation_state_file_path() {
    printf '%s\n' "${MEASUREMENTS_ROTATION_STATE_FILE:-$(dirname "$(measurement_summary_file_path)")/rotation-state.json}"
}

measurement_ensure_private_storage_dir() {
    local dir="${1:-}"
    local existed=false

    [[ -n "$dir" ]] || return 1
    if [[ -d "$dir" ]]; then
        existed=true
    fi

    mkdir -p "$dir" || return 1
    if [[ "$existed" != true ]]; then
        chmod 750 "$dir" 2> /dev/null || true
    fi
}

measurement_ensure_storage() {
    local reports_dir summary_file rotation_state_file
    reports_dir=$(measurement_reports_dir_path)
    summary_file=$(measurement_summary_file_path)
    rotation_state_file=$(measurement_rotation_state_file_path)
    measurement_ensure_private_storage_dir "$reports_dir" || return 1
    measurement_ensure_private_storage_dir "$(dirname "$summary_file")" || return 1
    measurement_ensure_private_storage_dir "$(dirname "$rotation_state_file")" || return 1
}

measurement_publish_json_file() {
    local out_file="$1"
    local mode="${2:-0640}"
    local json_content="${3:-}"
    local owner_spec="${4:-}"
    local tmp_file=""

    [[ -n "$out_file" ]] || return 1
    mkdir -p "$(dirname "$out_file")" || return 1

    tmp_file=$(mktemp "${out_file}.tmp.XXXXXX") || return 1
    if ! printf '%s\n' "$json_content" > "$tmp_file"; then
        rm -f "$tmp_file"
        return 1
    fi
    if ! mv -f "$tmp_file" "$out_file"; then
        rm -f "$tmp_file"
        return 1
    fi

    if [[ -n "$mode" ]]; then
        chmod "$mode" "$out_file" 2> /dev/null || true
    fi
    if [[ -n "$owner_spec" ]]; then
        chown "$owner_spec" "$out_file" 2> /dev/null || true
    fi
}

measurement_publish_managed_json_file() {
    local out_file="$1"
    local mode="${2:-0640}"
    local json_content="${3:-}"
    measurement_publish_json_file "$out_file" "$mode" "$json_content" "root:${XRAY_GROUP}"
}

measurement_publish_explicit_output_json_file() {
    local out_file="$1"
    local json_content="${2:-}"
    measurement_publish_json_file "$out_file" "" "$json_content"
}

measurement_invalid_summary_reason() {
    printf '%s\n' "saved measurement summary is invalid; rebuild or reimport reports"
}

measurement_invalid_rotation_state_reason() {
    printf '%s\n' "saved rotation state is invalid; reset or rebuild measurement rotation state"
}

measurement_rotation_state_default_json() {
    local current_primary="${1:-}"
    local current_family="${2:-}"
    local current_domain="${3:-}"
    jq -n \
        --arg generated "$(measurement_now_utc)" \
        --arg current_primary "$current_primary" \
        --arg current_family "$current_family" \
        --arg current_domain "$current_domain" \
        '{
            generated: $generated,
            current_primary: (if ($current_primary | length) > 0 then $current_primary else null end),
            current_primary_family: (if ($current_family | length) > 0 then $current_family else null end),
            current_primary_domain: (if ($current_domain | length) > 0 then $current_domain else null end),
            primary_weak_streak: 0,
            cooldown_families: [],
            cooldown_domains: [],
            last_promotion_reason: null,
            last_stable_summary_snapshot: null
        }'
}

measurement_rotation_state_trim_json() {
    local state_json="${1:-}"
    [[ -n "$state_json" ]] || state_json='{}'
    jq '
        .primary_weak_streak = ((.primary_weak_streak // 0) | if type == "number" then . else 0 end)
        | .cooldown_families = (
            (.cooldown_families // [])
            | map(
                select((.family // "") != "")
                | {
                    family: .family,
                    reason: (.reason // null),
                    remaining_actions: ((.remaining_actions // 0) | if type == "number" then . else 0 end)
                }
            )
            | map(select(.remaining_actions > 0))
        )
        | .cooldown_domains = (
            (.cooldown_domains // [])
            | map(
                select((.domain // "") != "")
                | {
                    domain: .domain,
                    reason: (.reason // null),
                    remaining_actions: ((.remaining_actions // 0) | if type == "number" then . else 0 end)
                }
            )
            | map(select(.remaining_actions > 0))
        )
    ' <<< "$state_json"
}

measurement_rotation_state_status_json() {
    local summary_json="${1:-"{}"}"
    local state_file current_primary current_family current_domain state_json=""
    local default_state_json=""
    state_file=$(measurement_rotation_state_file_path)
    current_primary=$(jq -r '.current_primary // empty' <<< "$summary_json" 2> /dev/null || true)
    current_family=$(jq -r '.current_primary_family // .current_primary_stats.provider_family // empty' <<< "$summary_json" 2> /dev/null || true)
    current_domain=$(jq -r '.current_primary_stats.domain // empty' <<< "$summary_json" 2> /dev/null || true)
    default_state_json=$(measurement_rotation_state_default_json "$current_primary" "$current_family" "$current_domain")

    if [[ ! -f "$state_file" ]]; then
        jq -n \
            --arg state "missing" \
            --arg reason "no saved rotation state yet" \
            --arg state_file "$state_file" \
            --argjson rotation_state "$default_state_json" \
            '{
                state: $state,
                reason: $reason,
                state_file: $state_file,
                rotation_state: $rotation_state
            }'
        return 0
    fi

    if ! jq -e 'type == "object"' "$state_file" > /dev/null 2>&1; then
        jq -n \
            --arg state "invalid" \
            --arg reason "$(measurement_invalid_rotation_state_reason)" \
            --arg state_file "$state_file" \
            --argjson rotation_state "$default_state_json" \
            '{
                state: $state,
                reason: $reason,
                state_file: $state_file,
                rotation_state: $rotation_state
            }'
        return 0
    fi

    state_json=$(cat "$state_file")
    state_json=$(measurement_rotation_state_trim_json "$state_json" |
        jq \
            --arg current_primary "$current_primary" \
            --arg current_family "$current_family" \
            --arg current_domain "$current_domain" '
            .current_primary = (
                if ((.current_primary // "") | length) > 0 then
                    .current_primary
                elif ($current_primary | length) > 0 then
                    $current_primary
                else
                    null
                end
            )
            | .current_primary_family = (
                if ((.current_primary_family // "") | length) > 0 then
                    .current_primary_family
                elif ($current_family | length) > 0 then
                    $current_family
                else
                    null
                end
            )
            | .current_primary_domain = (
                if ((.current_primary_domain // "") | length) > 0 then
                    .current_primary_domain
                elif ($current_domain | length) > 0 then
                    $current_domain
                else
                    null
                end
            )') || {
        jq -n \
            --arg state "invalid" \
            --arg reason "$(measurement_invalid_rotation_state_reason)" \
            --arg state_file "$state_file" \
            --argjson rotation_state "$default_state_json" \
            '{
                state: $state,
                reason: $reason,
                state_file: $state_file,
                rotation_state: $rotation_state
            }'
        return 0
    }

    jq -n \
        --arg state "ok" \
        --arg state_file "$state_file" \
        --argjson rotation_state "$state_json" \
        '{
            state: $state,
            reason: null,
            state_file: $state_file,
            rotation_state: $rotation_state
        }'
}

measurement_rotation_state_resolved_json() {
    local summary_json="${1:-"{}"}"
    local status_json=""
    status_json=$(measurement_rotation_state_status_json "$summary_json")
    jq -c '.rotation_state' <<< "$status_json"
}

measurement_write_rotation_state_json() {
    local state_json="${1:-}"
    [[ -n "$state_json" ]] || return 1
    measurement_ensure_storage
    local state_file
    state_file=$(measurement_rotation_state_file_path)
    state_json=$(measurement_rotation_state_trim_json "$state_json")

    measurement_publish_managed_json_file "$state_file" 0640 "$state_json" || return 1
    measurement_refresh_summary
}

measurement_overlay_rotation_state() {
    local summary_json="${1:-"{}"}"
    local rotation_state_status_json=""
    local state_json=""
    local raw_candidate_json="null"
    local current_primary_domain=""
    local candidate_domain=""
    local candidate_family=""
    local cooldown_families_json="[]"
    local cooldown_domains_json="[]"
    local promotion_block_reason=""
    local rotation_verdict="keep-current-primary"
    local rotation_state_status="missing"
    local rotation_state_reason=""
    local rotation_state_file=""
    local field_verdict="unknown"
    local coverage_verdict="unknown"
    rotation_state_status_json=$(measurement_rotation_state_status_json "$summary_json")
    state_json=$(jq -c '.rotation_state' <<< "$rotation_state_status_json")
    rotation_state_status=$(jq -r '.state // "missing"' <<< "$rotation_state_status_json")
    rotation_state_reason=$(jq -r '.reason // empty' <<< "$rotation_state_status_json")
    rotation_state_file=$(jq -r '.state_file // empty' <<< "$rotation_state_status_json")

    raw_candidate_json=$(jq -c '.promotion_candidate // null' <<< "$summary_json")
    current_primary_domain=$(jq -r '.current_primary_stats.domain // ""' <<< "$summary_json")
    candidate_domain=$(jq -r '
        (.promotion_candidate // null) as $candidate
        | if $candidate == null then
            ""
          else
            (
                .best_spare_stats.domain
                // ([.configs[]? | select(.config_name == ($candidate.config_name // "")) | .domain][0] // "")
            )
          end
    ' <<< "$summary_json")
    candidate_family=$(jq -r '.promotion_candidate.candidate_provider_family // ""' <<< "$summary_json")
    cooldown_families_json=$(jq -c '
        (.cooldown_families // [])
        | map(select((.remaining_actions // 0) > 0) | .family)
        | map(select(. != null and . != ""))
        | unique
        | sort
    ' <<< "$state_json")
    cooldown_domains_json=$(jq -c '
        (.cooldown_domains // [])
        | map(select((.remaining_actions // 0) > 0) | .domain)
        | map(select(. != null and . != ""))
        | unique
        | sort
    ' <<< "$state_json")
    field_verdict=$(jq -r '.field_verdict // "unknown"' <<< "$summary_json")
    coverage_verdict=$(jq -r '.coverage_verdict // "unknown"' <<< "$summary_json")

    if [[ "$rotation_state_status" == "invalid" ]]; then
        promotion_block_reason="$rotation_state_reason"
        rotation_verdict="invalid-rotation-state"
    elif [[ "$raw_candidate_json" == "null" ]]; then
        promotion_block_reason=""
        if [[ "$field_verdict" == "unknown" ]]; then
            rotation_verdict="collect-more-data"
        else
            rotation_verdict="keep-current-primary"
        fi
    elif [[ "$field_verdict" == "unknown" ]]; then
        promotion_block_reason="field summary is still unknown"
        rotation_verdict="hold-cooldown"
    elif [[ "$coverage_verdict" != "ok" ]]; then
        promotion_block_reason="field coverage is not representative enough yet"
        rotation_verdict="hold-cooldown"
    elif jq -e --arg family "$candidate_family" 'index($family) != null' <<< "$cooldown_families_json" > /dev/null 2>&1; then
        promotion_block_reason="candidate provider family is cooling down after recent weak-primary rotation"
        rotation_verdict="hold-cooldown"
    elif [[ -n "$candidate_domain" ]] && jq -e --arg domain "$candidate_domain" 'index($domain) != null' <<< "$cooldown_domains_json" > /dev/null 2>&1; then
        promotion_block_reason="candidate domain is cooling down after recent weak-primary rotation"
        rotation_verdict="hold-cooldown"
    else
        promotion_block_reason=""
        rotation_verdict="promote-spare"
    fi

    jq \
        --argjson state "$state_json" \
        --argjson raw_candidate "$raw_candidate_json" \
        --arg candidate_domain "$candidate_domain" \
        --arg current_primary_domain "$current_primary_domain" \
        --arg promotion_block_reason "$promotion_block_reason" \
        --arg rotation_verdict "$rotation_verdict" \
        --arg rotation_state_status "$rotation_state_status" \
        --arg rotation_state_reason "$rotation_state_reason" \
        --arg rotation_state_file "$rotation_state_file" \
        --argjson cooldown_families "$cooldown_families_json" \
        --argjson cooldown_domains "$cooldown_domains_json" '
        . + {
            raw_promotion_candidate: $raw_candidate,
            promotion_candidate: (
                if $raw_candidate != null and ($promotion_block_reason | length) == 0 then
                    ($raw_candidate + {
                        candidate_domain: (if ($candidate_domain | length) > 0 then $candidate_domain else null end)
                    })
                else
                    null
                end
            ),
            promotion_block_reason: (if ($promotion_block_reason | length) > 0 then $promotion_block_reason else null end),
            rotation_verdict: $rotation_verdict,
            rotation_state_status: $rotation_state_status,
            rotation_state_reason: (if ($rotation_state_reason | length) > 0 then $rotation_state_reason else null end),
            rotation_state_file: (if ($rotation_state_file | length) > 0 then $rotation_state_file else null end),
            primary_weak_streak: ($state.primary_weak_streak // 0),
            cooldown_families: $cooldown_families,
            cooldown_domains: $cooldown_domains,
            rotation_state: $state,
            current_primary_domain: (if ($current_primary_domain | length) > 0 then $current_primary_domain else null end)
        }
    ' <<< "$summary_json"
}

measurement_report_slug() {
    local value="${1:-default}"
    value=$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')
    value=$(printf '%s' "$value" | sed -E 's/[^a-z0-9._-]+/-/g; s/^-+|-+$//g')
    [[ -n "$value" ]] || value="default"
    printf '%s\n' "$value"
}

measurement_report_filename() {
    local network_tag="${1:-default}"
    local provider="${2:-unknown}"
    local region="${3:-unknown}"
    printf '%s-%s-%s-%s.json\n' \
        "$(date -u '+%Y%m%dT%H%M%SZ')" \
        "$(measurement_report_slug "$network_tag")" \
        "$(measurement_report_slug "$provider")" \
        "$(measurement_report_slug "$region")"
}

measurement_collect_report_files() {
    local reports_dir
    local summary_file
    local summary_base
    reports_dir=$(measurement_reports_dir_path)
    summary_file=$(measurement_summary_file_path)
    summary_base=$(basename "$summary_file")
    [[ -d "$reports_dir" ]] || return 0
    find "$reports_dir" -maxdepth 1 -type f -name '*.json' ! -name "$summary_base" | sort
}

measurement_filter_valid_report_files() {
    local file
    for file in "$@"; do
        [[ -n "$file" && -f "$file" ]] || continue
        if measurement_validate_report_json "$file" > /dev/null 2>&1; then
            printf '%s\n' "$file"
        fi
    done
}

measurement_report_hash() {
    local file="$1"
    [[ -n "$file" && -f "$file" ]] || return 1

    if command -v sha256sum > /dev/null 2>&1; then
        sha256sum "$file" | awk '{print $1}'
        return 0
    fi
    if command -v shasum > /dev/null 2>&1; then
        shasum -a 256 "$file" | awk '{print $1}'
        return 0
    fi
    if command -v openssl > /dev/null 2>&1; then
        openssl dgst -sha256 "$file" | awk '{print $NF}'
        return 0
    fi
    return 1
}

measurement_find_existing_report_by_hash() {
    local hash="$1"
    [[ -n "$hash" ]] || return 1

    local file existing_hash
    while IFS= read -r file; do
        [[ -n "$file" ]] || continue
        existing_hash=$(measurement_report_hash "$file" 2> /dev/null || true)
        [[ -n "$existing_hash" && "$existing_hash" == "$hash" ]] || continue
        printf '%s\n' "$file"
        return 0
    done < <(measurement_collect_report_files)
    return 1
}

measurement_reports_json_from_files() {
    local -a files=("$@")
    local -a valid_files=()

    if ((${#files[@]} > 0)); then
        mapfile -t valid_files < <(measurement_filter_valid_report_files "${files[@]}")
    fi

    if ((${#valid_files[@]} == 0)); then
        printf '%s\n' '[]'
        return 0
    fi
    jq -s '.' "${valid_files[@]}"
}

measurement_aggregate_reports_json() {
    local reports_json="${1:-[]}"
    local jq_program="$MEASUREMENTS_AGGREGATE_JQ"
    [[ -f "$jq_program" ]] || {
        echo "ERROR: не найден jq-модуль агрегатора измерений: $jq_program" >&2
        return 1
    }

    jq -n \
        --arg generated "$(measurement_now_utc)" \
        --argjson reports "$reports_json" \
        -f "$jq_program"
}

measurement_render_summary_text() {
    local summary_json="${1:-}"
    [[ -n "$summary_json" ]] || return 1

    jq -r '
        "field verdict: " + (.field_verdict // "unknown"),
        "operator recommendation: " + (.operator_recommendation // "unknown"),
        "recommendation reason: " + (.operator_recommendation_reason // "n/a"),
        "coverage: " + (.coverage_verdict // "unknown")
          + " | reports=" + ((.report_count // 0) | tostring)
          + " | networks=" + ((.network_tag_count // 0) | tostring)
          + " | providers=" + ((.provider_count // 0) | tostring)
          + " | regions=" + ((.region_count // 0) | tostring),
        "coverage reason: " + (.coverage_reason // "n/a"),
        "family diversity: " + (.family_diversity_verdict // "unknown")
          + " | config families=" + ((.config_provider_family_count // 0) | tostring),
        "family diversity reason: " + (.family_diversity_reason // "n/a"),
        "long-term: " + (.long_term_verdict // "unknown"),
        "long-term reason: " + (.long_term_reason // "n/a"),
        (
            if ((.network_tags // []) | length) == 0 then
                "network tags: n/a"
            else
                "network tags: " + ((.network_tags // []) | join(", "))
            end
        ),
        (
            if ((.providers // []) | length) == 0 then
                "providers: n/a"
            else
                "providers: " + ((.providers // []) | join(", "))
            end
        ),
        (
            if ((.regions // []) | length) == 0 then
                "regions: n/a"
            else
                "regions: " + ((.regions // []) | join(", "))
            end
        ),
        (
            if ((.config_provider_families // []) | length) == 0 then
                "config families: n/a"
            else
                "config families: " + ((.config_provider_families // []) | join(", "))
            end
        ),
        "latest report: " + (.latest_report_generated // "unknown"),
        "",
        "current primary: " + (.current_primary // "n/a"),
        (
            if (.current_primary_stats // null) == null then
                "  recent stats: n/a"
            else
                "  recommended success last5: " + ((.current_primary_stats.recommended_success_rate_last5 // 0) | tostring) + "%"
            end
        ),
        (
            if (.current_primary_stats // null) == null then
                empty
            else
                "  provider family: " + ((.current_primary_stats.provider_family // "n/a") | tostring)
            end
        ),
        (
            if (.current_primary_stats // null) == null then
                empty
            else
                "  rescue success last5: " + ((.current_primary_stats.rescue_success_rate_last5 // 0) | tostring) + "%"
            end
        ),
        (
            if (.current_primary_stats // null) == null then
                empty
            else
                "  emergency success last5: " + ((.current_primary_stats.emergency_success_rate_last5 // 0) | tostring) + "%"
            end
        ),
        (
            if (.current_primary_stats // null) == null then
                empty
            else
                "  trend: " + ((.current_primary_stats.trend_verdict // "unknown") | tostring)
            end
        ),
        (
            if (.current_primary_stats // null) == null then
                empty
            else
                "  best recent variant: "
                + ((.current_primary_stats.best_variant // "n/a") | tostring)
                + " (" + ((.current_primary_stats.best_variant_success_rate_last5 // 0) | tostring) + "%"
                + ", " + ((.current_primary_stats.best_variant_p50_latency_ms_last5 // "n/a") | tostring) + "ms)"
            end
        ),
        "best spare: " + (.best_spare // "n/a"),
        (
            if (.best_spare_stats // null) == null then
                "  recent stats: n/a"
            else
                "  recommended success last5: " + ((.best_spare_stats.recommended_success_rate_last5 // 0) | tostring) + "%"
            end
        ),
        (
            if (.best_spare_stats // null) == null then
                empty
            else
                "  provider family: " + ((.best_spare_stats.provider_family // "n/a") | tostring)
            end
        ),
        (
            if (.best_spare_stats // null) == null then
                empty
            else
                "  rescue success last5: " + ((.best_spare_stats.rescue_success_rate_last5 // 0) | tostring) + "%"
            end
        ),
        (
            if (.best_spare_stats // null) == null then
                empty
            else
                "  emergency success last5: " + ((.best_spare_stats.emergency_success_rate_last5 // 0) | tostring) + "%"
            end
        ),
        (
            if (.best_spare_stats // null) == null then
                empty
            else
                "  trend: " + ((.best_spare_stats.trend_verdict // "unknown") | tostring)
            end
        ),
        (
            if (.best_spare_stats // null) == null then
                empty
            else
                "  best recent variant: "
                + ((.best_spare_stats.best_variant // "n/a") | tostring)
                + " (" + ((.best_spare_stats.best_variant_success_rate_last5 // 0) | tostring) + "%"
                + ", " + ((.best_spare_stats.best_variant_p50_latency_ms_last5 // "n/a") | tostring) + "ms)"
            end
        ),
        "recommend emergency: " + ((.recommend_emergency // false) | tostring),
        (
            if (.recommend_emergency_reason // null) == null then
                "recommend emergency reason: n/a"
            else
                "recommend emergency reason: " + .recommend_emergency_reason
            end
        ),
        "rotation verdict: " + (.rotation_verdict // "keep-current-primary"),
        (
            if (.rotation_state_status // "ok") == "invalid" then
                "rotation state: invalid | " + ((.rotation_state_reason // "n/a") | tostring)
            else
                empty
            end
        ),
        "primary weak streak: " + ((.primary_weak_streak // 0) | tostring),
        (
            if ((.cooldown_families // []) | length) == 0 then
                "cooldown families: n/a"
            else
                "cooldown families: " + ((.cooldown_families // []) | join(", "))
            end
        ),
        (
            if ((.cooldown_domains // []) | length) == 0 then
                "cooldown domains: n/a"
            else
                "cooldown domains: " + ((.cooldown_domains // []) | join(", "))
            end
        ),
        (
            if (.promotion_candidate // null) == null then
                "promotion candidate: n/a"
            else
                "promotion candidate: "
                + (.promotion_candidate.config_name // "n/a")
                + " (primary recommended="
                + ((.promotion_candidate.current_primary_recommended_success_rate_last5 // 0) | tostring)
                + "%, spare recommended="
                + ((.promotion_candidate.candidate_recommended_success_rate_last5 // 0) | tostring)
                + "%, candidate family="
                + ((.promotion_candidate.candidate_provider_family // "unknown") | tostring)
                + ", independence="
                + ((.promotion_candidate.independence_verdict // "unknown") | tostring)
                + ")"
            end
        ),
        (
            if (.promotion_candidate // null) == null and (.promotion_block_reason // null) == null then
                empty
            elif (.promotion_candidate // null) == null then
                "promotion block: " + (.promotion_block_reason // "n/a")
            else
                "promotion reason: " + (.promotion_candidate.reason // "n/a")
            end
        )
    ' <<< "$summary_json"
}

measurement_refresh_summary() {
    measurement_ensure_storage
    local summary_file reports_json aggregated_summary
    summary_file=$(measurement_summary_file_path)
    local -a files=()
    mapfile -t files < <(measurement_collect_report_files)
    reports_json=$(measurement_reports_json_from_files "${files[@]}")
    aggregated_summary=$(measurement_aggregate_reports_json "$reports_json")
    aggregated_summary=$(measurement_overlay_rotation_state "$aggregated_summary") || return 1
    measurement_publish_managed_json_file "$summary_file" 0640 "$aggregated_summary"
}

measurement_save_report() {
    local report_json="$1"
    local out_file="${2:-}"
    measurement_ensure_storage
    if [[ -z "$out_file" ]]; then
        local reports_dir network_tag provider region
        reports_dir=$(measurement_reports_dir_path)
        network_tag=$(jq -r '.network_tag // "default"' <<< "$report_json" 2> /dev/null || echo "default")
        provider=$(jq -r '.provider // "unknown"' <<< "$report_json" 2> /dev/null || echo "unknown")
        region=$(jq -r '.region // "unknown"' <<< "$report_json" 2> /dev/null || echo "unknown")
        out_file="${reports_dir}/$(measurement_report_filename "$network_tag" "$provider" "$region")"
    fi
    measurement_publish_managed_json_file "$out_file" 0640 "$report_json" || return 1
    measurement_refresh_summary
    printf '%s\n' "$out_file"
}

measurement_summary_status_json() {
    local summary_file
    summary_file=$(measurement_summary_file_path)
    if [[ ! -f "$summary_file" ]]; then
        jq -n \
            --arg state "missing" \
            --arg reason "no saved field reports yet" \
            --arg summary_file "$summary_file" \
            '{
                state: $state,
                reason: $reason,
                summary_file: $summary_file
            }'
        return 0
    fi

    if jq -e 'type == "object"' "$summary_file" > /dev/null 2>&1; then
        local summary_json=""
        summary_json=$(cat "$summary_file")
        if summary_json=$(measurement_overlay_rotation_state "$summary_json" 2> /dev/null); then
            if jq -e 'type == "object"' <<< "$summary_json" > /dev/null 2>&1; then
                jq -n \
                    --arg state "ok" \
                    --arg summary_file "$summary_file" \
                    --argjson summary "$summary_json" \
                    '{
                        state: $state,
                        reason: null,
                        summary_file: $summary_file,
                        summary: $summary
                    }'
                return 0
            fi
        fi
    fi

    jq -n \
        --arg state "invalid" \
        --arg reason "$(measurement_invalid_summary_reason)" \
        --arg summary_file "$summary_file" \
        '{
            state: $state,
            reason: $reason,
            summary_file: $summary_file
        }'
}

measurement_read_summary_json() {
    local status_json summary_state
    status_json=$(measurement_summary_status_json)
    summary_state=$(jq -r '.state // "invalid"' <<< "$status_json" 2> /dev/null || echo "invalid")
    [[ "$summary_state" == "ok" ]] || return 1
    jq -c '.summary' <<< "$status_json"
}

measurement_compare_reports_json() {
    local -a files=("$@")
    local reports_json aggregated_summary
    reports_json=$(measurement_reports_json_from_files "${files[@]}")
    aggregated_summary=$(measurement_aggregate_reports_json "$reports_json")
    measurement_overlay_rotation_state "$aggregated_summary"
}

measurement_validate_report_json() {
    local report_file="$1"
    [[ -f "$report_file" ]] || return 1
    jq -e '
        type == "object"
        and ((.generated // "") | type == "string" and length > 0)
        and (.configs | type == "array")
        and (.results | type == "array")
    ' "$report_file" > /dev/null 2>&1
}

measurement_import_report_file() {
    local source_file="$1"
    [[ -n "$source_file" ]] || {
        echo "measurement import requires a source file" >&2
        return 1
    }
    [[ -f "$source_file" ]] || {
        echo "measurement report not found: $source_file" >&2
        return 1
    }
    measurement_validate_report_json "$source_file" || {
        echo "measurement report has invalid schema: $source_file" >&2
        return 1
    }

    local report_json network_tag provider region out_file hash suffix existing_file
    report_json=$(cat "$source_file")
    network_tag=$(jq -r '.network_tag // "default"' <<< "$report_json" 2> /dev/null || echo "default")
    provider=$(jq -r '.provider // "unknown"' <<< "$report_json" 2> /dev/null || echo "unknown")
    region=$(jq -r '.region // "unknown"' <<< "$report_json" 2> /dev/null || echo "unknown")
    hash=$(measurement_report_hash "$source_file" 2> /dev/null || true)

    if [[ -n "$hash" ]]; then
        existing_file=$(measurement_find_existing_report_by_hash "$hash" 2> /dev/null || true)
        if [[ -n "$existing_file" ]]; then
            jq -n \
                --arg status "duplicate" \
                --arg source_file "$source_file" \
                --arg stored_file "$existing_file" \
                --arg hash "$hash" \
                '{
                    status: $status,
                    source_file: $source_file,
                    stored_file: $stored_file,
                    hash: $hash
                }'
            return 0
        fi
    fi

    suffix="${hash:0:12}"
    [[ -n "$suffix" ]] || suffix="$(date -u '+%H%M%S%N' | cut -c1-12)"
    out_file="$(measurement_reports_dir_path)/$(measurement_report_filename "$network_tag" "$provider" "$region" | sed "s/\\.json$/-${suffix}.json/")"

    measurement_save_report "$report_json" "$out_file" > /dev/null || {
        echo "measurement import could not persist report: $source_file" >&2
        return 1
    }
    jq -n \
        --arg status "imported" \
        --arg source_file "$source_file" \
        --arg stored_file "$out_file" \
        --arg hash "$hash" \
        '{
            status: $status,
            source_file: $source_file,
            stored_file: $stored_file,
            hash: $hash
        }'
}

measurement_prune_reports() {
    local keep_last="${1:-0}"
    local dry_run="${2:-false}"
    local reports_dir
    reports_dir=$(measurement_reports_dir_path)
    [[ "$keep_last" =~ ^[0-9]+$ ]] || {
        echo "keep_last must be a non-negative integer" >&2
        return 1
    }
    ((keep_last > 0)) || {
        echo "keep_last must be greater than zero" >&2
        return 1
    }

    local -a files=()
    mapfile -t files < <(measurement_collect_report_files | sort -r)

    local index=0
    local removed=0
    local -a deleted_files=()
    local file
    for file in "${files[@]}"; do
        ((index += 1))
        if ((index <= keep_last)); then
            continue
        fi
        deleted_files+=("$file")
        if [[ "$dry_run" != "true" ]]; then
            rm -f "$file"
        fi
        ((removed += 1))
    done

    if [[ "$dry_run" != "true" ]]; then
        measurement_refresh_summary
    fi

    jq -n \
        --arg reports_dir "$reports_dir" \
        --argjson keep_last "$keep_last" \
        --argjson dry_run "$(if [[ "$dry_run" == "true" ]]; then echo true; else echo false; fi)" \
        --argjson removed "$removed" \
        --argjson deleted "$(printf '%s\n' "${deleted_files[@]}" | sed '/^$/d' | jq -R . | jq -s .)" \
        '{
            reports_dir: $reports_dir,
            keep_last: $keep_last,
            dry_run: $dry_run,
            removed_count: $removed,
            deleted_files: $deleted
        }'
}
