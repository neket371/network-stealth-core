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
}
