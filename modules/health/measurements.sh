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

measurement_now_utc() {
    date -u '+%Y-%m-%dT%H:%M:%SZ'
}

measurement_reports_dir_path() {
    printf '%s\n' "${MEASUREMENTS_DIR:-/var/lib/xray/measurements}"
}

measurement_summary_file_path() {
    printf '%s\n' "${MEASUREMENTS_SUMMARY_FILE:-/var/lib/xray/measurements/latest-summary.json}"
}

measurement_ensure_storage() {
    local reports_dir summary_file
    reports_dir=$(measurement_reports_dir_path)
    summary_file=$(measurement_summary_file_path)
    mkdir -p "$reports_dir" "$(dirname "$summary_file")"
    chmod 750 "$reports_dir" "$(dirname "$summary_file")" 2> /dev/null || true
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
    jq -n \
        --arg generated "$(measurement_now_utc)" \
        --argjson reports "$reports_json" '
        def p50:
            (map(select(type == "number")) | sort) as $lat
            | if ($lat | length) == 0 then null else $lat[(($lat | length) / 2 | floor)] end;
        def avg_numbers:
            (map(select(type == "number"))) as $nums
            | if ($nums | length) == 0 then 0 else (($nums | add) / ($nums | length)) end;
        def success_rate:
            if length == 0 then 0
            else ((map(select(.success == true)) | length) / length * 100)
            end;
        def variant_window_stats($results):
            ($results | sort_by(.config_name, .variant_key)
            | group_by(.config_name, .variant_key)
            | map({
                config_name: (.[0].config_name // "unknown"),
                variant_key: (.[0].variant_key // "unknown"),
                attempts: length,
                successes: (map(select(.success == true)) | length),
                success_rate: success_rate,
                p50_latency_ms: (map(.latency_ms) | p50),
                latest_success: (.[-1].success // false),
                latest_error: (.[-1].reason // .[-1].error // null)
            }));
        def config_variant_value($stats; $variant_key; $field; $fallback):
            (($stats | map(select(.variant_key == $variant_key)) | .[0][$field]) // $fallback);
        def best_variant_stats($stats):
            (($stats | sort_by(-(.success_rate // 0), (.p50_latency_ms // 2147483647)) | .[0]) // null);
        def trend_verdict($recent_rate; $previous_rate; $recent_attempts; $previous_attempts):
            if (($recent_attempts // 0) < 2 and ($previous_attempts // 0) < 2) then "unknown"
            elif (($recent_rate // 0) < 60 and ($previous_rate // 0) < 60) then "weak"
            elif ((($recent_rate // 0) - ($previous_rate // 0)) >= 20) then "improving"
            elif ((($recent_rate // 0) - ($previous_rate // 0)) <= -20) then "degrading"
            else "stable"
            end;
        def trend_reason($trend; $recent_rate; $previous_rate):
            if $trend == "improving" then
                "recent recommended success improved from " + (($previous_rate // 0) | tostring) + "% to " + (($recent_rate // 0) | tostring) + "%"
            elif $trend == "degrading" then
                "recent recommended success fell from " + (($previous_rate // 0) | tostring) + "% to " + (($recent_rate // 0) | tostring) + "%"
            elif $trend == "weak" then
                "recommended success stayed weak across both recent windows"
            elif $trend == "stable" then
                "recommended success stayed broadly stable across recent windows"
            else
                "not enough history for a trend verdict"
            end;
        ($reports | sort_by(.generated // .checked_at // "") | reverse) as $sorted_reports
        | ($sorted_reports[:5]) as $recent_reports
        | ($sorted_reports[5:10]) as $previous_reports
        | ($reports | length) as $report_count
        | ($reports | map((.network_tag // "default") | tostring) | unique | sort) as $network_tags
        | ($reports | map((.provider // "unknown") | tostring) | unique | sort) as $providers
        | ($reports | map((.region // "unknown") | tostring) | unique | sort) as $regions
        | ($network_tags | length) as $network_tag_count
        | ($providers | length) as $provider_count
        | ($regions | length) as $region_count
        | (($sorted_reports
            | map(.configs[]? | {
                config_name: (.config_name // .name // "unknown"),
                domain: (.domain // null),
                provider_family: (.provider_family // .domain // .config_name // .name // "unknown"),
                primary_rank: (.primary_rank // 0)
            })
            | unique_by(.config_name)
            | sort_by(.primary_rank, .config_name))) as $config_meta
        | (if $report_count > 0 then $sorted_reports[0] else {} end) as $latest_report
        | (
            if (($latest_report.configs // []) | length) > 0 then
                ($latest_report.configs[0].config_name // $latest_report.configs[0].name // "Config 1")
            else
                null
            end
        ) as $current_primary
        | [$recent_reports[]?.results[]?] as $recent_results
        | [$previous_reports[]?.results[]?] as $previous_results
        | [$reports[]?.results[]?] as $all_results
        | (variant_window_stats($recent_results)) as $recent_variant_stats
        | (variant_window_stats($previous_results)) as $previous_variant_stats
        | (variant_window_stats($all_results)) as $all_variant_stats
        | ($recent_variant_stats | map({
            config_name,
            variant_key,
            attempts_last5: .attempts,
            successes_last5: .successes,
            success_rate_last5: .success_rate,
            p50_latency_ms_last5: .p50_latency_ms,
            latest_success,
            latest_error
          })) as $variant_stats
        | ($config_meta | map(
            . as $meta
            | ($recent_variant_stats | map(select(.config_name == $meta.config_name))) as $recent_for_config
            | ($previous_variant_stats | map(select(.config_name == $meta.config_name))) as $previous_for_config
            | ($all_variant_stats | map(select(.config_name == $meta.config_name))) as $all_for_config
            | (best_variant_stats($recent_for_config)) as $recent_best
            | (config_variant_value($recent_for_config; "recommended"; "success_rate"; 0)) as $recommended_last5
            | (config_variant_value($previous_for_config; "recommended"; "success_rate"; 0)) as $recommended_previous5
            | (config_variant_value($all_for_config; "recommended"; "success_rate"; 0)) as $recommended_all
            | (config_variant_value($recent_for_config; "rescue"; "success_rate"; 0)) as $rescue_last5
            | (config_variant_value($previous_for_config; "rescue"; "success_rate"; 0)) as $rescue_previous5
            | (config_variant_value($all_for_config; "rescue"; "success_rate"; 0)) as $rescue_all
            | (config_variant_value($recent_for_config; "emergency"; "success_rate"; 0)) as $emergency_last5
            | (config_variant_value($previous_for_config; "emergency"; "success_rate"; 0)) as $emergency_previous5
            | (config_variant_value($all_for_config; "emergency"; "success_rate"; 0)) as $emergency_all
            | (config_variant_value($recent_for_config; "recommended"; "attempts"; 0)) as $recommended_attempts_last5
            | (config_variant_value($previous_for_config; "recommended"; "attempts"; 0)) as $recommended_attempts_previous5
            | (trend_verdict($recommended_last5; $recommended_previous5; $recommended_attempts_last5; $recommended_attempts_previous5)) as $trend_verdict
            | {
                config_name: $meta.config_name,
                domain: $meta.domain,
                provider_family: $meta.provider_family,
                primary_rank: $meta.primary_rank,
                recommended_success_rate_last5: $recommended_last5,
                recommended_success_rate_previous5: $recommended_previous5,
                recommended_success_rate_all: $recommended_all,
                rescue_success_rate_last5: $rescue_last5,
                rescue_success_rate_previous5: $rescue_previous5,
                rescue_success_rate_all: $rescue_all,
                emergency_success_rate_last5: $emergency_last5,
                emergency_success_rate_previous5: $emergency_previous5,
                emergency_success_rate_all: $emergency_all,
                recommended_attempts_last5: $recommended_attempts_last5,
                recommended_attempts_previous5: $recommended_attempts_previous5,
                best_variant: ($recent_best.variant_key // null),
                best_variant_success_rate_last5: ($recent_best.success_rate // 0),
                best_variant_p50_latency_ms_last5: ($recent_best.p50_latency_ms // null),
                trend_verdict: $trend_verdict,
                trend_reason: (trend_reason($trend_verdict; $recommended_last5; $recommended_previous5))
            }
          )) as $configs
        | (($configs | map(.provider_family) | map(select(. != null and . != "")) | unique | sort)) as $config_provider_families
        | ($config_provider_families | length) as $config_provider_family_count
        | (($configs
            | sort_by(.provider_family, .config_name)
            | group_by(.provider_family)
            | map(
                . as $items
                | ((map(.recommended_success_rate_last5) | avg_numbers)) as $recommended_last5
                | ((map(.recommended_success_rate_previous5) | avg_numbers)) as $recommended_previous5
                | ((map(.recommended_success_rate_all) | avg_numbers)) as $recommended_all
                | ((map(.best_variant_success_rate_last5) | avg_numbers)) as $best_variant_last5
                | (trend_verdict($recommended_last5; $recommended_previous5; (length * 2); (length * 2))) as $trend_verdict
                | {
                    provider_family: (.[0].provider_family // "unknown"),
                    config_count: length,
                    config_names: map(.config_name),
                    recommended_success_rate_last5: $recommended_last5,
                    recommended_success_rate_previous5: $recommended_previous5,
                    recommended_success_rate_all: $recommended_all,
                    best_variant_success_rate_last5: $best_variant_last5,
                    trend_verdict: $trend_verdict,
                    trend_reason: (trend_reason($trend_verdict; $recommended_last5; $recommended_previous5)),
                    field_penalty: (
                        if $recommended_last5 < 40 then 80
                        elif $trend_verdict == "weak" then 60
                        elif $trend_verdict == "degrading" then 40
                        elif $recommended_last5 < 60 then 20
                        else 0
                        end
                    )
                }
            ))) as $provider_family_stats
        | ($configs | map(select(.config_name != $current_primary)) | sort_by(.recommended_success_rate_last5, (.best_variant_success_rate_last5 // 0)) | reverse | .[0]) as $best_spare
        | ($configs | map(select(.config_name == $current_primary)) | .[0]) as $primary_stats
        | (
            if ($configs | length) < 2 then "unknown"
            elif $config_provider_family_count < 2 then "warning"
            else "ok"
            end
        ) as $family_diversity_verdict
        | (
            if ($configs | length) < 2 then "only one managed config is present"
            elif $config_provider_family_count < 2 then "current config set collapses to one provider family"
            else "current config set spans multiple provider families"
            end
        ) as $family_diversity_reason
        | (
            if $report_count == 0 then "unknown"
            elif (($configs | map(select(.trend_verdict == "degrading" and (.recommended_success_rate_last5 // 0) < 60)) | length) > 0) then "warning"
            elif (($provider_family_stats | map(select(.trend_verdict == "degrading")) | length) > 0) then "warning"
            else "ok"
            end
        ) as $long_term_verdict
        | (
            if $report_count == 0 then "not enough saved reports for long-term review"
            elif (($configs | map(select(.trend_verdict == "degrading" and (.recommended_success_rate_last5 // 0) < 60)) | length) > 0) then "at least one managed config is degrading across recent report windows"
            elif (($provider_family_stats | map(select(.trend_verdict == "degrading")) | length) > 0) then "at least one provider family shows degrading recent performance"
            else "recent windows do not show a broad degrading trend"
            end
        ) as $long_term_reason
        | (
            if $report_count == 0 then "warning"
            elif $report_count < 2 then "warning"
            elif $network_tag_count < 2 and $provider_count < 2 then "warning"
            elif $network_tag_count < 2 then "warning"
            elif $provider_count < 2 then "warning"
            else "ok"
            end
        ) as $coverage_verdict
        | (
            if $report_count == 0 then "no saved field reports yet"
            elif $report_count < 2 then "need at least 2 saved reports before treating field data as representative"
            elif $network_tag_count < 2 and $provider_count < 2 then "field data covers only one network tag and one provider"
            elif $network_tag_count < 2 then "field data covers only one network tag"
            elif $provider_count < 2 then "field data covers only one provider"
            else "field data spans multiple providers and network tags"
            end
        ) as $coverage_reason
        | (
            if $report_count == 0 then
                null
            elif (($primary_stats.recommended_success_rate_last5 // 0) < 60)
               and (($primary_stats.rescue_success_rate_last5 // 0) < 80) then
                "primary recommended and rescue variants stay weak in recent field reports"
            else
                null
            end
        ) as $recommend_emergency_reason
        | (
            if $report_count == 0 then
                null
            elif (($primary_stats.recommended_success_rate_last5 // 0) < 60)
               and (($best_spare.recommended_success_rate_last5 // 0) >= 80) then
                (($primary_stats.provider_family // "") != "" and ($best_spare.provider_family // "") != "" and ($primary_stats.provider_family == $best_spare.provider_family)) as $same_family
                | {
                    config_name: $best_spare.config_name,
                    reason: (
                        "field reports show weak primary recommended success and a stronger spare"
                        + (if $same_family then "; the spare still uses the same provider family, so this is a short-term recovery rather than a diversity gain" else "" end)
                    ),
                    current_primary: $current_primary,
                    current_primary_provider_family: ($primary_stats.provider_family // "unknown"),
                    current_primary_recommended_success_rate_last5: ($primary_stats.recommended_success_rate_last5 // 0),
                    current_primary_rescue_success_rate_last5: ($primary_stats.rescue_success_rate_last5 // 0),
                    candidate_provider_family: ($best_spare.provider_family // "unknown"),
                    candidate_recommended_success_rate_last5: ($best_spare.recommended_success_rate_last5 // 0),
                    candidate_best_variant: ($best_spare.best_variant // null),
                    candidate_best_variant_success_rate_last5: ($best_spare.best_variant_success_rate_last5 // 0),
                    candidate_trend_verdict: ($best_spare.trend_verdict // "unknown"),
                    independence_verdict: (if $same_family then "weak" else "ok" end),
                    coverage_verdict: $coverage_verdict
                }
            else
                null
            end
        ) as $promotion_candidate
        | (
            if $report_count == 0 then
                "collect-more-data"
            elif $promotion_candidate != null then
                "promote-spare"
            elif (($primary_stats.recommended_success_rate_last5 // 0) >= 80) then
                "keep-current-primary"
            elif (($primary_stats.recommended_success_rate_last5 // 0) < 60)
                 and (($primary_stats.rescue_success_rate_last5 // 0) < 80) then
                "field-test-emergency"
            elif $coverage_verdict != "ok" then
                "collect-more-data"
            else
                "watch-and-collect-more"
            end
        ) as $operator_recommendation
        | (
            if $report_count == 0 then
                "save at least 2 field reports across different networks before trusting field decisions"
            elif $promotion_candidate != null then
                "promote " + ($promotion_candidate.config_name // "n/a")
                + ": primary recommended="
                + (($promotion_candidate.current_primary_recommended_success_rate_last5 // 0) | tostring)
                + "%, spare recommended="
                + (($promotion_candidate.candidate_recommended_success_rate_last5 // 0) | tostring)
                + "% over the latest saved reports"
                + (if ($promotion_candidate.independence_verdict // "ok") == "weak" then " (same provider family, so this is only a short-term recovery)" else "" end)
            elif (($primary_stats.recommended_success_rate_last5 // 0) >= 80) then
                "current primary recommended variant stays healthy in recent field reports"
            elif (($primary_stats.recommended_success_rate_last5 // 0) < 60)
                 and (($primary_stats.rescue_success_rate_last5 // 0) < 80) then
                "recommended and rescue are both weak; verify emergency only on real field clients"
            elif $coverage_verdict != "ok" then
                $coverage_reason
            else
                "keep collecting reports before changing primary order"
            end
        ) as $operator_recommendation_reason
        | {
            generated: $generated,
            report_count: $report_count,
            latest_report_generated: ($latest_report.generated // null),
            network_tags: $network_tags,
            providers: $providers,
            regions: $regions,
            config_provider_families: $config_provider_families,
            network_tag_count: $network_tag_count,
            provider_count: $provider_count,
            region_count: $region_count,
            config_provider_family_count: $config_provider_family_count,
            coverage_verdict: $coverage_verdict,
            coverage_reason: $coverage_reason,
            family_diversity_verdict: $family_diversity_verdict,
            family_diversity_reason: $family_diversity_reason,
            long_term_verdict: $long_term_verdict,
            long_term_reason: $long_term_reason,
            current_primary: $current_primary,
            current_primary_stats: ($primary_stats // null),
            current_primary_family: ($primary_stats.provider_family // null),
            best_spare: ($best_spare.config_name // null),
            best_spare_stats: ($best_spare // null),
            best_spare_family: ($best_spare.provider_family // null),
            best_spare_recommended_success_rate_last5: ($best_spare.recommended_success_rate_last5 // 0),
            recommend_emergency: (
                (($primary_stats.recommended_success_rate_last5 // 0) < 60)
                and (($primary_stats.rescue_success_rate_last5 // 0) < 80)
            ),
            recommend_emergency_reason: $recommend_emergency_reason,
            field_verdict: (
                if $report_count == 0 then "unknown"
                elif (($primary_stats.recommended_success_rate_last5 // 0) >= 80) then "ok"
                elif (($primary_stats.rescue_success_rate_last5 // 0) >= 60) or (($best_spare.recommended_success_rate_last5 // 0) >= 80) then "warning"
                else "broken"
                end
            ),
            operator_recommendation: $operator_recommendation,
            operator_recommendation_reason: $operator_recommendation_reason,
            promotion_candidate: $promotion_candidate,
            configs: $configs,
            provider_family_stats: $provider_family_stats,
            variant_stats: $variant_stats,
            reports: ($reports | map({
                generated,
                network_tag,
                provider,
                region,
                requested_variants,
                probe_urls,
                clients_json
            }))
        }'
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
            if (.promotion_candidate // null) == null then
                empty
            else
                "promotion reason: " + (.promotion_candidate.reason // "n/a")
            end
        )
    ' <<< "$summary_json"
}

measurement_refresh_summary() {
    measurement_ensure_storage
    local summary_file reports_json
    summary_file=$(measurement_summary_file_path)
    local -a files=()
    mapfile -t files < <(measurement_collect_report_files)
    reports_json=$(measurement_reports_json_from_files "${files[@]}")
    measurement_aggregate_reports_json "$reports_json" > "$summary_file"
    chmod 640 "$summary_file" 2> /dev/null || true
    chown "root:${XRAY_GROUP}" "$summary_file" 2> /dev/null || true
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
    printf '%s\n' "$report_json" > "$out_file"
    chmod 640 "$out_file" 2> /dev/null || true
    chown "root:${XRAY_GROUP}" "$out_file" 2> /dev/null || true
    measurement_refresh_summary
    printf '%s\n' "$out_file"
}

measurement_read_summary_json() {
    local summary_file
    summary_file=$(measurement_summary_file_path)
    [[ -f "$summary_file" ]] || return 1
    cat "$summary_file"
}

measurement_status_summary_tsv() {
    local summary_json
    summary_json=$(measurement_read_summary_json 2> /dev/null) || return 1
    jq -r '[
        (.field_verdict // "unknown"),
        (.operator_recommendation // "unknown"),
        (.operator_recommendation_reason // "n/a"),
        (.coverage_verdict // "unknown"),
        (.report_count // 0 | tostring),
        (.network_tag_count // 0 | tostring),
        (.provider_count // 0 | tostring),
        (.region_count // 0 | tostring),
        (.family_diversity_verdict // "unknown"),
        (.long_term_verdict // "unknown"),
        (.current_primary // "n/a"),
        (.current_primary_family // "n/a"),
        (.current_primary_stats.recommended_success_rate_last5 // 0 | tostring),
        (.current_primary_stats.rescue_success_rate_last5 // 0 | tostring),
        (.current_primary_stats.trend_verdict // "unknown"),
        (.best_spare // "n/a"),
        (.best_spare_family // "n/a"),
        (.best_spare_stats.recommended_success_rate_last5 // 0 | tostring),
        (.best_spare_stats.trend_verdict // "unknown"),
        (.recommend_emergency // false | tostring),
        (.latest_report_generated // "unknown")
    ] | @tsv' <<< "$summary_json"
}

measurement_promotion_candidate_json() {
    local summary_json
    summary_json=$(measurement_read_summary_json 2> /dev/null) || return 1
    jq -c '.promotion_candidate // null' <<< "$summary_json"
}

measurement_compare_reports_json() {
    local -a files=("$@")
    local reports_json
    reports_json=$(measurement_reports_json_from_files "${files[@]}")
    measurement_aggregate_reports_json "$reports_json"
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

    measurement_save_report "$report_json" "$out_file" > /dev/null
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
