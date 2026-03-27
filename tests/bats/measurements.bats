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
{"generated":"2026-03-26T10:00:00Z","network_tag":"home","provider":"isp-a","region":"msk","configs":[{"config_name":"Config 1","domain":"vk.com","provider_family":"vk","primary_rank":0,"success":false},{"config_name":"Config 2","domain":"yandex.ru","provider_family":"yandex","primary_rank":1,"success":true}],"results":[{"config_name":"Config 1","variant_key":"recommended","success":false,"latency_ms":0,"reason":"blocked"},{"config_name":"Config 1","variant_key":"rescue","success":false,"latency_ms":0,"reason":"blocked"},{"config_name":"Config 2","variant_key":"recommended","success":true,"latency_ms":120}]}
EOF
    cat > "$report_b" <<EOF
{"generated":"2026-03-26T11:00:00Z","network_tag":"mobile","provider":"isp-b","region":"spb","configs":[{"config_name":"Config 1","domain":"vk.com","provider_family":"vk","primary_rank":0,"success":false},{"config_name":"Config 2","domain":"yandex.ru","provider_family":"yandex","primary_rank":1,"success":true}],"results":[{"config_name":"Config 1","variant_key":"recommended","success":false,"latency_ms":0,"reason":"blocked"},{"config_name":"Config 1","variant_key":"rescue","success":false,"latency_ms":0,"reason":"blocked"},{"config_name":"Config 2","variant_key":"recommended","success":true,"latency_ms":140}]}
EOF
    summary=$(measurement_compare_reports_json "$report_a" "$report_b")
    jq -e ".coverage_verdict == \"ok\"" <<< "$summary" > /dev/null
    jq -e ".operator_recommendation == \"promote-spare\"" <<< "$summary" > /dev/null
    jq -e ".rotation_verdict == \"promote-spare\"" <<< "$summary" > /dev/null
    jq -e ".primary_weak_streak == 0" <<< "$summary" > /dev/null
    jq -e ".family_diversity_verdict == \"ok\"" <<< "$summary" > /dev/null
    jq -e ".config_provider_family_count == 2" <<< "$summary" > /dev/null
    jq -e ".network_tag_count == 2 and .provider_count == 2 and .region_count == 2" <<< "$summary" > /dev/null
    text=$(measurement_render_summary_text "$summary")
    [[ "$text" == *"operator recommendation: promote-spare"* ]]
    [[ "$text" == *"rotation verdict: promote-spare"* ]]
    [[ "$text" == *"primary weak streak: 0"* ]]
    [[ "$text" == *"coverage: ok | reports=2 | networks=2 | providers=2 | regions=2"* ]]
    [[ "$text" == *"family diversity: ok | config families=2"* ]]
    [[ "$text" == *"promotion candidate: Config 2 (primary recommended=0%, spare recommended=100%, candidate family=yandex, independence=ok)"* ]]
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
{"generated":"2026-03-26T10:00:00Z","network_tag":"home","provider":"isp-a","region":"msk","configs":[{"config_name":"Config 1","domain":"vk.com","provider_family":"vk","primary_rank":0,"success":false},{"config_name":"Config 2","domain":"yandex.ru","provider_family":"yandex","primary_rank":1,"success":true}],"results":[{"config_name":"Config 1","variant_key":"recommended","success":false,"latency_ms":0,"reason":"blocked"},{"config_name":"Config 1","variant_key":"rescue","success":false,"latency_ms":0,"reason":"blocked"},{"config_name":"Config 2","variant_key":"recommended","success":true,"latency_ms":120}]}
EOF
    cat > "$tmp_dir/b.json" <<EOF
{"generated":"2026-03-26T11:00:00Z","network_tag":"mobile","provider":"isp-b","region":"spb","configs":[{"config_name":"Config 1","domain":"vk.com","provider_family":"vk","primary_rank":0,"success":false},{"config_name":"Config 2","domain":"yandex.ru","provider_family":"yandex","primary_rank":1,"success":true}],"results":[{"config_name":"Config 1","variant_key":"recommended","success":false,"latency_ms":0,"reason":"blocked"},{"config_name":"Config 1","variant_key":"rescue","success":false,"latency_ms":0,"reason":"blocked"},{"config_name":"Config 2","variant_key":"recommended","success":true,"latency_ms":140}]}
EOF
    bash ./scripts/measure-stealth.sh summarize --dir "$tmp_dir"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"operator recommendation: promote-spare"* ]]
    [[ "$output" == *"rotation verdict: promote-spare"* ]]
    [[ "$output" == *"coverage: ok | reports=2 | networks=2 | providers=2 | regions=2"* ]]
    [[ "$output" == *"family diversity: ok | config families=2"* ]]
    [[ "$output" == *"provider families:"* ]]
    [[ "$output" == *"  - yandex | penalty=0 | recommended=100% | trend=improving"* ]]
    [[ "$output" == *"promotion reason: field reports show weak primary recommended success and a stronger spare"* ]]
}

@test "status_flow_render_verbose_measurements shows enriched operator summary" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./service.sh
    operator_decision_payload_json() {
      cat <<EOF
{"decision_recommendation":"promote-spare","decision_reason":"promote Config 2: primary recommended=20%, spare recommended=100% over the latest saved reports","field":{"field_verdict":"warning","coverage_verdict":"ok","report_count":3,"network_tag_count":2,"provider_count":2,"region_count":2,"family_diversity_verdict":"ok","long_term_verdict":"stable","rotation_verdict":"promote-spare","primary_weak_streak":2,"current_primary":"Config 1","current_primary_family":"vk","current_primary_stats":{"recommended_success_rate_last5":20,"rescue_success_rate_last5":40,"trend_verdict":"degrading"},"best_spare":"Config 2","best_spare_family":"yandex","best_spare_stats":{"recommended_success_rate_last5":100,"trend_verdict":"improving"},"recommend_emergency":false,"latest_report_generated":"2026-03-26T11:00:00Z","cooldown_families":["vk"],"cooldown_domains":["vk.com"]}}
EOF
    }
    status_flow_render_verbose_measurements
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"Recommendation: promote-spare"* ]]
    [[ "$output" == *"Reason: promote Config 2: primary recommended=20%, spare recommended=100% over the latest saved reports"* ]]
    [[ "$output" == *"Coverage: ok (3 reports, 2 networks, 2 providers, 2 regions)"* ]]
    [[ "$output" == *"Family diversity: ok"* ]]
    [[ "$output" == *"Long-term trend: stable"* ]]
    [[ "$output" == *"Rotation: promote-spare (weak streak 2)"* ]]
    [[ "$output" == *"Current primary: Config 1 [vk] (recommended 20%, rescue 40%, trend degrading)"* ]]
    [[ "$output" == *"Best spare: Config 2 [yandex] (recommended 100%, trend improving)"* ]]
    [[ "$output" == *"Cooldowns: families=vk, domains=vk.com"* ]]
}

@test "measure-stealth import recurses into nested dirs and skips invalid duplicates cleanly" {
    run bash -eo pipefail -c '
    tmp_dir=$(mktemp -d)
    trap "rm -rf \"$tmp_dir\"" EXIT
    mkdir -p "$tmp_dir/remote/a" "$tmp_dir/remote/b"
    report="$tmp_dir/remote/a/report.json"
    duplicate="$tmp_dir/remote/b/report-copy.json"
    invalid="$tmp_dir/remote/manifest.json"
    cat > "$report" <<EOF
{"generated":"2026-03-26T10:00:00Z","network_tag":"home","provider":"isp-a","region":"msk","configs":[{"config_name":"Config 1","domain":"vk.com","provider_family":"vk","primary_rank":0,"success":true}],"results":[{"config_name":"Config 1","variant_key":"recommended","success":true,"latency_ms":120}]}
EOF
    cp "$report" "$duplicate"
    cat > "$invalid" <<EOF
{"kind":"manifest"}
EOF
    MEASUREMENTS_DIR="$tmp_dir/measurements" \
    MEASUREMENTS_SUMMARY_FILE="$tmp_dir/measurements/latest-summary.json" \
      bash ./scripts/measure-stealth.sh import --dir "$tmp_dir/remote"
   '
    [ "$status" -eq 0 ]
    jq -e '.scanned_count == 3' <<< "$output" > /dev/null
    jq -e '.imported_count == 1' <<< "$output" > /dev/null
    jq -e '.duplicate_count == 1' <<< "$output" > /dev/null
    jq -e '.skipped_invalid_count == 1' <<< "$output" > /dev/null
    jq -e '.summary.report_count == 1' <<< "$output" > /dev/null
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
    operator_rotation_apply_observations() {
      cat <<EOF
{"should_promote":true,"promotion_name":"Config 2","promotion_reason":"promote Config 2: primary recommended=20%, spare recommended=100% over the latest saved reports"}
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
    operator_rotation_apply_observations() {
      cat <<EOF
{"should_promote":true,"promotion_name":"Config 2","promotion_reason":"field summary prefers Config 2 after a broken self-check"}
EOF
    }
    log() { printf "%s %s\n" "$1" "$2"; }
    maybe_promote_runtime_primary_from_observations
    [[ "${PORTS[0]}" == "444" ]]
    echo ok
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"Primary client order обновлён: Config 2"* ]]
    [[ "$output" == *"Причина promotion: field summary prefers Config 2 after a broken self-check"* ]]
    [[ "$output" == *"ok"* ]]
}

@test "measurement_read_summary_json exposes cooldown block metadata from rotation state" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./health.sh
    tmp_dir=$(mktemp -d)
    trap "rm -rf \"$tmp_dir\"" EXIT
    MEASUREMENTS_DIR="$tmp_dir/measurements"
    MEASUREMENTS_SUMMARY_FILE="$tmp_dir/measurements/latest-summary.json"
    MEASUREMENTS_ROTATION_STATE_FILE="$tmp_dir/measurements/rotation-state.json"
    mkdir -p "$MEASUREMENTS_DIR"
    cat > "$MEASUREMENTS_SUMMARY_FILE" <<EOF
{"field_verdict":"warning","coverage_verdict":"ok","operator_recommendation":"promote-spare","operator_recommendation_reason":"rotate to Config 2","current_primary":"Config 1","current_primary_family":"vk","current_primary_stats":{"domain":"vk.com","recommended_success_rate_last5":20,"rescue_success_rate_last5":40},"best_spare":"Config 2","best_spare_family":"yandex","best_spare_stats":{"domain":"yandex.ru","recommended_success_rate_last5":100},"promotion_candidate":{"config_name":"Config 2","reason":"rotate to Config 2","candidate_provider_family":"yandex"},"configs":[{"config_name":"Config 1","domain":"vk.com","provider_family":"vk"},{"config_name":"Config 2","domain":"yandex.ru","provider_family":"yandex"}]}
EOF
    cat > "$MEASUREMENTS_ROTATION_STATE_FILE" <<EOF
{"primary_weak_streak":2,"cooldown_families":[{"family":"yandex","remaining_actions":2,"reason":"rotated-away-weak-primary"}],"cooldown_domains":[]}
EOF
    summary=$(measurement_read_summary_json)
    jq -e ".rotation_verdict == \"hold-cooldown\"" <<< "$summary" > /dev/null
    jq -e ".promotion_candidate == null" <<< "$summary" > /dev/null
    jq -e ".promotion_block_reason == \"candidate provider family is cooling down after recent weak-primary rotation\"" <<< "$summary" > /dev/null
    jq -e ".cooldown_families == [\"yandex\"]" <<< "$summary" > /dev/null
    echo ok
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "invalid measurement summary becomes explicit degraded operator state" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./health.sh
    tmp_dir=$(mktemp -d)
    trap "rm -rf \"$tmp_dir\"" EXIT
    MEASUREMENTS_DIR="$tmp_dir/measurements"
    MEASUREMENTS_SUMMARY_FILE="$tmp_dir/measurements/latest-summary.json"
    MEASUREMENTS_ROTATION_STATE_FILE="$tmp_dir/measurements/rotation-state.json"
    mkdir -p "$MEASUREMENTS_DIR"
    printf "{broken\n" > "$MEASUREMENTS_SUMMARY_FILE"
    operator_runtime_state_json() {
      cat <<EOF
{"managed_present":true,"service_state":"active","config_state":"ok","transport":"xhttp","installed_version":"25.9.5"}
EOF
    }
    payload=$(operator_decision_payload_json)
    jq -e ".field.summary_state == \"invalid\"" <<< "$payload" > /dev/null
    jq -e ".field.summary_state_reason == \"saved measurement summary is invalid; rebuild or reimport reports\"" <<< "$payload" > /dev/null
    jq -e ".overall_verdict == \"warning\"" <<< "$payload" > /dev/null
    jq -e ".decision_reason == \"saved measurement summary is invalid; rebuild or reimport reports\"" <<< "$payload" > /dev/null
    jq -e ".next_action == \"rebuild or reimport saved field reports before trusting promotion decisions\"" <<< "$payload" > /dev/null
    echo ok
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}
