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
