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

measurement_reports_json_from_files() {
    local -a files=("$@")
    if ((${#files[@]} == 0)); then
        printf '%s\n' '[]'
        return 0
    fi
    jq -s '.' "${files[@]}"
}

measurement_aggregate_reports_json() {
    local reports_json="${1:-[]}"
    jq -n \
        --arg generated "$(measurement_now_utc)" \
        --argjson reports "$reports_json" '
        def p50:
            (map(select(type == "number")) | sort) as $lat
            | if ($lat | length) == 0 then null else $lat[(($lat | length) / 2 | floor)] end;
        def success_rate:
            if length == 0 then 0
            else ((map(select(.success == true)) | length) / length * 100)
            end;
        def latest_n($n):
            sort_by(.generated // .checked_at // "")
            | reverse
            | .[:$n];
        ($reports | latest_n(5)) as $recent_reports
        | ($reports | length) as $report_count
        | ($reports | map((.network_tag // "default") | tostring) | unique | sort) as $network_tags
        | ($reports | map((.provider // "unknown") | tostring) | unique | sort) as $providers
        | ($reports | map((.region // "unknown") | tostring) | unique | sort) as $regions
        | ($network_tags | length) as $network_tag_count
        | ($providers | length) as $provider_count
        | ($regions | length) as $region_count
        | (if $report_count > 0 then $reports[-1] else {} end) as $latest_report
        | (
            if (($latest_report.configs // []) | length) > 0 then
                ($latest_report.configs[0].config_name // $latest_report.configs[0].name // "Config 1")
            else
                null
            end
        ) as $current_primary
        | [$recent_reports[]?.results[]?] as $recent_results
        | [$reports[]?.results[]?] as $all_results
        | (($recent_results | sort_by(.config_name, .variant_key))
            | group_by(.config_name, .variant_key)
            | map({
                config_name: (.[0].config_name // "unknown"),
                variant_key: (.[0].variant_key // "unknown"),
                attempts_last5: length,
                successes_last5: (map(select(.success == true)) | length),
                success_rate_last5: success_rate,
                p50_latency_ms_last5: (map(.latency_ms) | p50),
                latest_success: (.[-1].success // false),
                latest_error: (.[-1].reason // .[-1].error // null)
            })) as $variant_stats
        | (($variant_stats | sort_by(.config_name)) | group_by(.config_name) | map({
            config_name: .[0].config_name,
            recommended_success_rate_last5: ((map(select(.variant_key == "recommended")) | .[0].success_rate_last5) // 0),
            rescue_success_rate_last5: ((map(select(.variant_key == "rescue")) | .[0].success_rate_last5) // 0),
            emergency_success_rate_last5: ((map(select(.variant_key == "emergency")) | .[0].success_rate_last5) // 0),
            best_variant: ((sort_by(.success_rate_last5, (.p50_latency_ms_last5 // 2147483647)) | reverse | .[0].variant_key) // null),
            best_variant_success_rate_last5: ((sort_by(.success_rate_last5, (.p50_latency_ms_last5 // 2147483647)) | reverse | .[0].success_rate_last5) // 0),
            best_variant_p50_latency_ms_last5: ((sort_by(.success_rate_last5, (.p50_latency_ms_last5 // 2147483647)) | reverse | .[0].p50_latency_ms_last5) // null)
          })) as $configs
        | ($configs | map(select(.config_name != $current_primary)) | sort_by(.recommended_success_rate_last5, (.best_variant_success_rate_last5 // 0)) | reverse | .[0]) as $best_spare
        | ($configs | map(select(.config_name == $current_primary)) | .[0]) as $primary_stats
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
                {
                    config_name: $best_spare.config_name,
                    reason: "field reports show weak primary recommended success and a stronger spare",
                    current_primary: $current_primary,
                    current_primary_recommended_success_rate_last5: ($primary_stats.recommended_success_rate_last5 // 0),
                    current_primary_rescue_success_rate_last5: ($primary_stats.rescue_success_rate_last5 // 0),
                    candidate_recommended_success_rate_last5: ($best_spare.recommended_success_rate_last5 // 0),
                    candidate_best_variant: ($best_spare.best_variant // null),
                    candidate_best_variant_success_rate_last5: ($best_spare.best_variant_success_rate_last5 // 0),
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
            network_tag_count: $network_tag_count,
            provider_count: $provider_count,
            region_count: $region_count,
            coverage_verdict: $coverage_verdict,
            coverage_reason: $coverage_reason,
            current_primary: $current_primary,
            current_primary_stats: ($primary_stats // null),
            best_spare: ($best_spare.config_name // null),
            best_spare_stats: ($best_spare // null),
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
                + "%)"
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
        (.current_primary // "n/a"),
        (.current_primary_stats.recommended_success_rate_last5 // 0 | tostring),
        (.current_primary_stats.rescue_success_rate_last5 // 0 | tostring),
        (.best_spare // "n/a"),
        (.best_spare_stats.recommended_success_rate_last5 // 0 | tostring),
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

    local report_json network_tag provider region out_file hash suffix
    report_json=$(cat "$source_file")
    network_tag=$(jq -r '.network_tag // "default"' <<< "$report_json" 2> /dev/null || echo "default")
    provider=$(jq -r '.provider // "unknown"' <<< "$report_json" 2> /dev/null || echo "unknown")
    region=$(jq -r '.region // "unknown"' <<< "$report_json" 2> /dev/null || echo "unknown")
    hash=$(printf '%s' "$report_json" | sha256sum | awk '{print $1}')
    suffix="${hash:0:12}"
    out_file="$(measurement_reports_dir_path)/$(measurement_report_filename "$network_tag" "$provider" "$region" | sed "s/\\.json$/-${suffix}.json/")"

    measurement_save_report "$report_json" "$out_file" > /dev/null
    printf '%s\n' "$out_file"
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
