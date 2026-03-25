#!/usr/bin/env bats

@test "measurement summary exposes operator recommendation and coverage metadata" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./health.sh
    tmp_dir=$(mktemp -d)
    trap "rm -rf \"$tmp_dir\"" EXIT
    report_a="$tmp_dir/a.json"
    report_b="$tmp_dir/b.json"
    cat > "$report_a" <<EOF
{"generated":"2026-03-26T10:00:00Z","network_tag":"home","provider":"isp-a","region":"msk","configs":[{"config_name":"Config 1","success":false},{"config_name":"Config 2","success":true}],"results":[{"config_name":"Config 1","variant_key":"recommended","success":false,"latency_ms":0,"reason":"blocked"},{"config_name":"Config 1","variant_key":"rescue","success":false,"latency_ms":0,"reason":"blocked"},{"config_name":"Config 2","variant_key":"recommended","success":true,"latency_ms":120}]}
EOF
    cat > "$report_b" <<EOF
{"generated":"2026-03-26T11:00:00Z","network_tag":"mobile","provider":"isp-b","region":"spb","configs":[{"config_name":"Config 1","success":false},{"config_name":"Config 2","success":true}],"results":[{"config_name":"Config 1","variant_key":"recommended","success":false,"latency_ms":0,"reason":"blocked"},{"config_name":"Config 1","variant_key":"rescue","success":false,"latency_ms":0,"reason":"blocked"},{"config_name":"Config 2","variant_key":"recommended","success":true,"latency_ms":140}]}
EOF
    summary=$(measurement_compare_reports_json "$report_a" "$report_b")
    jq -e ".coverage_verdict == \"ok\"" <<< "$summary" > /dev/null
    jq -e ".operator_recommendation == \"promote-spare\"" <<< "$summary" > /dev/null
    jq -e ".network_tag_count == 2 and .provider_count == 2 and .region_count == 2" <<< "$summary" > /dev/null
    text=$(measurement_render_summary_text "$summary")
    [[ "$text" == *"operator recommendation: promote-spare"* ]]
    [[ "$text" == *"coverage: ok | reports=2 | networks=2 | providers=2 | regions=2"* ]]
    [[ "$text" == *"promotion candidate: Config 2 (primary recommended=0%, spare recommended=100%)"* ]]
    echo ok
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "measure-stealth summarize prints recommendation and coverage details" {
    run bash -eo pipefail -c '
    tmp_dir=$(mktemp -d)
    trap "rm -rf \"$tmp_dir\"" EXIT
    cat > "$tmp_dir/a.json" <<EOF
{"generated":"2026-03-26T10:00:00Z","network_tag":"home","provider":"isp-a","region":"msk","configs":[{"config_name":"Config 1","success":false},{"config_name":"Config 2","success":true}],"results":[{"config_name":"Config 1","variant_key":"recommended","success":false,"latency_ms":0,"reason":"blocked"},{"config_name":"Config 1","variant_key":"rescue","success":false,"latency_ms":0,"reason":"blocked"},{"config_name":"Config 2","variant_key":"recommended","success":true,"latency_ms":120}]}
EOF
    cat > "$tmp_dir/b.json" <<EOF
{"generated":"2026-03-26T11:00:00Z","network_tag":"mobile","provider":"isp-b","region":"spb","configs":[{"config_name":"Config 1","success":false},{"config_name":"Config 2","success":true}],"results":[{"config_name":"Config 1","variant_key":"recommended","success":false,"latency_ms":0,"reason":"blocked"},{"config_name":"Config 1","variant_key":"rescue","success":false,"latency_ms":0,"reason":"blocked"},{"config_name":"Config 2","variant_key":"recommended","success":true,"latency_ms":140}]}
EOF
    bash ./scripts/measure-stealth.sh summarize --dir "$tmp_dir"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"operator recommendation: promote-spare"* ]]
    [[ "$output" == *"coverage: ok | reports=2 | networks=2 | providers=2 | regions=2"* ]]
    [[ "$output" == *"promotion reason: field reports show weak primary recommended success and a stronger spare"* ]]
}

@test "status_flow_render_verbose_measurements shows enriched operator summary" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./service.sh
    measurement_status_summary_tsv() {
      printf "warning\tpromote-spare\tpromote Config 2: primary recommended=20%%, spare recommended=100%% over the latest saved reports\tok\t3\t2\t2\t2\tConfig 1\t20\t40\tConfig 2\t100\tfalse\t2026-03-26T11:00:00Z\n"
    }
    status_flow_render_verbose_measurements
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"Recommendation: promote-spare"* ]]
    [[ "$output" == *"Reason: promote Config 2: primary recommended=20%, spare recommended=100% over the latest saved reports"* ]]
    [[ "$output" == *"Coverage: ok (3 reports, 2 networks, 2 providers, 2 regions)"* ]]
    [[ "$output" == *"Current primary: Config 1 (recommended 20%, rescue 40%)"* ]]
    [[ "$output" == *"Best spare: Config 2 (recommended 100%)"* ]]
}

@test "maybe_promote_runtime_primary_from_observations logs rich measured promotion reason" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./install.sh
    NUM_CONFIGS=2
    PORTS=(443 444)
    PORTS_V6=()
    UUIDS=(u1 u2)
    SHORT_IDS=(s1 s2)
    PRIVATE_KEYS=(k1 k2)
    PUBLIC_KEYS=(p1 p2)
    CONFIG_DOMAINS=(d1 d2)
    CONFIG_DESTS=(dest1 dest2)
    CONFIG_SNIS=(sni1 sni2)
    CONFIG_FPS=(fp1 fp2)
    CONFIG_TRANSPORT_ENDPOINTS=(ep1 ep2)
    CONFIG_PROVIDER_FAMILIES=(fam1 fam2)
    CONFIG_VLESS_ENCRYPTIONS=(enc1 enc2)
    CONFIG_VLESS_DECRYPTIONS=(dec1 dec2)
    runtime_config_name_at_index() { [[ "${1:-0}" == "0" ]] && echo "Config 1" || echo "Config 2"; }
    runtime_config_index_by_name() { [[ "${1:-}" == "Config 2" ]] && echo 1 || echo 0; }
    self_check_last_verdict() { echo "ok"; }
    self_check_warning_streak_count() { echo 0; }
    measurement_read_summary_json() { return 1; }
    measurement_promotion_candidate_json() {
      cat <<EOF
{"config_name":"Config 2","reason":"promote Config 2: primary recommended=20%, spare recommended=100% over the latest saved reports"}
EOF
    }
    log() { printf "%s %s\n" "$1" "$2"; }
    maybe_promote_runtime_primary_from_observations
    [[ "${PORTS[0]}" == "444" ]]
    [[ "${UUIDS[0]}" == "u2" ]]
    echo ok
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"Primary client order обновлён: Config 2"* ]]
    [[ "$output" == *"Причина promotion: promote Config 2: primary recommended=20%, spare recommended=100% over the latest saved reports"* ]]
    [[ "$output" == *"ok"* ]]
}

@test "maybe_promote_runtime_primary_from_observations uses measured best spare on broken verdict" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./install.sh
    NUM_CONFIGS=2
    PORTS=(443 444)
    PORTS_V6=()
    UUIDS=(u1 u2)
    SHORT_IDS=(s1 s2)
    PRIVATE_KEYS=(k1 k2)
    PUBLIC_KEYS=(p1 p2)
    CONFIG_DOMAINS=(d1 d2)
    CONFIG_DESTS=(dest1 dest2)
    CONFIG_SNIS=(sni1 sni2)
    CONFIG_FPS=(fp1 fp2)
    CONFIG_TRANSPORT_ENDPOINTS=(ep1 ep2)
    CONFIG_PROVIDER_FAMILIES=(fam1 fam2)
    CONFIG_VLESS_ENCRYPTIONS=(enc1 enc2)
    CONFIG_VLESS_DECRYPTIONS=(dec1 dec2)
    runtime_config_name_at_index() { [[ "${1:-0}" == "0" ]] && echo "Config 1" || echo "Config 2"; }
    runtime_config_index_by_name() { [[ "${1:-}" == "Config 2" ]] && echo 1 || echo 0; }
    self_check_last_verdict() { echo "broken"; }
    self_check_warning_streak_count() { echo 0; }
    measurement_read_summary_json() {
      cat <<EOF
{"best_spare":"Config 2","best_spare_stats":{"recommended_success_rate_last5":100,"best_variant":"rescue","best_variant_success_rate_last5":100}}
EOF
    }
    measurement_promotion_candidate_json() { echo "null"; }
    log() { printf "%s %s\n" "$1" "$2"; }
    maybe_promote_runtime_primary_from_observations
    [[ "${PORTS[0]}" == "444" ]]
    echo ok
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"Primary client order обновлён: Config 2"* ]]
    [[ "$output" == *"Причина promotion: last self-check verdict is broken; field summary prefers Config 2 (recommended 100%, best rescue 100%)"* ]]
    [[ "$output" == *"ok"* ]]
}
