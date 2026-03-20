#!/usr/bin/env bats

@test "export_compatibility_notes writes non-empty text artifact" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./export.sh
    export_dir=$(mktemp -d)
    tmp=$(mktemp)
    export_capabilities_json "$export_dir" "$export_dir/capabilities.json"
    export_compatibility_notes "$export_dir/capabilities.json" "$tmp"
    grep -q "network stealth core export notes" "$tmp"
    grep -q "raw-xray: native" "$tmp"
    echo ok
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "export_capabilities_notes_from_json renders capability rows from json" {
    run bash -eo pipefail -c '
    source ./modules/export/capabilities.sh
    tmp_dir=$(mktemp -d)
    trap "rm -rf \"$tmp_dir\"" EXIT
    capabilities="$tmp_dir/capabilities.json"
    notes="$tmp_dir/compatibility-notes.txt"
    cat > "$capabilities" <<'"'"'JSON'"'"'
{
  "formats": [
    {
      "name": "raw-xray",
      "status": "native",
      "artifact": "/tmp/raw-xray",
      "xray_min_version": "25.9.5",
      "requires": ["xhttp", "xtls-rprx-vision"],
      "reason": "canonical artifact"
    },
    {
      "name": "sing-box",
      "status": "unsupported",
      "artifact": null,
      "xray_min_version": "25.9.5",
      "requires": ["xhttp"],
      "reason": "not generated"
    }
  ]
}
JSON
    TRANSPORT="xhttp"
    export_capabilities_notes_from_json "$capabilities" "$notes"
    grep -Fq "transport: xhttp" "$notes"
    grep -Fq -- "- raw-xray: native -> /tmp/raw-xray" "$notes"
    grep -Fq "requires: xhttp, xtls-rprx-vision" "$notes"
    grep -Fq -- "- sing-box: unsupported" "$notes"
    echo ok
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "export_capabilities_json writes xhttp capability matrix into a new parent directory" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./export.sh
    tmp_dir=$(mktemp -d)
    XRAY_KEYS="$tmp_dir/keys"
    mkdir -p "$XRAY_KEYS"
    export_capabilities_json "$tmp_dir/new-parent/export" "$tmp_dir/new-parent/export/capabilities.json"
    jq -e '\''.schema_version == 2'\'' "$tmp_dir/new-parent/export/capabilities.json" > /dev/null
    jq -e '\''.transport == "xhttp"'\'' "$tmp_dir/new-parent/export/capabilities.json" > /dev/null
    jq -e '\''any(.formats[]; .name == "clients-links.txt" and .status == "native")'\'' "$tmp_dir/new-parent/export/capabilities.json" > /dev/null
    jq -e '\''any(.formats[]; .name == "raw-xray" and .status == "native")'\'' "$tmp_dir/new-parent/export/capabilities.json" > /dev/null
    jq -e '\''any(.formats[]; .name == "canary-bundle" and .status == "native")'\'' "$tmp_dir/new-parent/export/capabilities.json" > /dev/null
    jq -e '\''any(.formats[]; .name == "sing-box" and .status == "unsupported")'\'' "$tmp_dir/new-parent/export/capabilities.json" > /dev/null
    echo ok
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "save_policy_file writes strongest-direct policy" {
    run bash -eo pipefail -c '
    source ./lib.sh
    tmp_dir=$(mktemp -d)
    trap "rm -rf \"$tmp_dir\"" EXIT
    XRAY_POLICY="$tmp_dir/policy.json"
    DOMAIN_PROFILE="ru-auto"
    DOMAIN_TIER="tier_ru"
    NUM_CONFIGS=3
    TRANSPORT="xhttp"
    XRAY_DIRECT_FLOW="xtls-rprx-vision"
    XRAY_CLIENT_MIN_VERSION="25.9.5"
    save_policy_file
    jq -e '\''.transport.name == "xhttp"'\'' "$XRAY_POLICY" > /dev/null
    jq -e '\''.transport.flow == "xtls-rprx-vision"'\'' "$XRAY_POLICY" > /dev/null
    jq -e '\''.measurement.variants == ["recommended","rescue","emergency"]'\'' "$XRAY_POLICY" > /dev/null
    jq -e '\''.update.replan == false'\'' "$XRAY_POLICY" > /dev/null
    echo ok
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "export_canary_bundle succeeds when parent directory is created on demand" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./export.sh
    tmp_dir=$(mktemp -d)
    XRAY_KEYS="$tmp_dir"
    XRAY_GROUP="root"
    mkdir -p "$tmp_dir/export/raw-xray"
    printf "{}\n" > "$tmp_dir/export/raw-xray/config-1-recommended-ipv4.json"
    printf "{}\n" > "$tmp_dir/export/raw-xray/config-1-rescue-ipv4.json"
    printf "{}\n" > "$tmp_dir/export/raw-xray/config-1-emergency-ipv4.json"
    cat > "$tmp_dir/clients.json" <<JSON
{
  "schema_version": 3,
  "stealth_contract_version": "7.1.0",
  "xray_min_version": "25.9.5",
  "generated": "2026-03-07T00:00:00Z",
  "transport": "xhttp",
  "configs": [
    {
      "name": "Config 1",
      "domain": "disk.yandex.ru",
      "recommended_variant": "recommended",
      "variants": [
        {
          "key": "recommended",
          "category": "primary",
          "mode": "auto",
          "requires": {"browser_dialer": false},
          "import_hint": "hint",
          "xray_client_file_v4": "$tmp_dir/export/raw-xray/config-1-recommended-ipv4.json"
        },
        {
          "key": "rescue",
          "category": "fallback",
          "mode": "packet-up",
          "requires": {"browser_dialer": false},
          "import_hint": "hint",
          "xray_client_file_v4": "$tmp_dir/export/raw-xray/config-1-rescue-ipv4.json"
        },
        {
          "key": "emergency",
          "category": "emergency",
          "mode": "stream-up",
          "requires": {"browser_dialer": true},
          "import_hint": "hint",
          "xray_client_file_v4": "$tmp_dir/export/raw-xray/config-1-emergency-ipv4.json"
        }
      ]
    }
  ]
}
JSON
    export_canary_bundle "$tmp_dir/clients.json" "$tmp_dir/new-parent/export/canary"
    jq -e ".source.configs[0].variants | length == 3" "$tmp_dir/new-parent/export/canary/manifest.json" > /dev/null
    test -f "$tmp_dir/new-parent/export/canary/measure-linux.sh"
    rm -rf "$tmp_dir"
  '
    [ "$status" -eq 0 ]
}

@test "export_canary_bundle fails with clear error when source JSON build fails" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./export.sh
    tmp_dir=$(mktemp -d)
    trap "rm -rf \"$tmp_dir\"" EXIT
    XRAY_KEYS="$tmp_dir"
    XRAY_GROUP="root"
    mkdir -p "$tmp_dir/export/canary" "$tmp_dir/export/raw-xray"
    printf "sentinel-manifest\n" > "$tmp_dir/export/canary/manifest.json"
    printf "{}\n" > "$tmp_dir/export/raw-xray/config-1-recommended-ipv4.json"
    cat > "$tmp_dir/clients.json" <<JSON
{
  "schema_version": 3,
  "stealth_contract_version": "7.5.5",
  "xray_min_version": "25.9.5",
  "generated": "2026-03-19T00:00:00Z",
  "transport": "xhttp",
  "configs": [
    {
      "name": "Config 1",
      "domain": "disk.yandex.ru",
      "recommended_variant": "recommended",
      "variants": [
        {
          "key": "recommended",
          "category": "primary",
          "mode": "auto",
          "requires": {"browser_dialer": false},
          "import_hint": "hint",
          "xray_client_file_v4": "$tmp_dir/export/raw-xray/config-1-recommended-ipv4.json"
        }
      ]
    }
  ]
}
JSON
    real_jq=$(command -v jq)
    mockbin=$(mktemp -d)
    trap "rm -rf \"$tmp_dir\" \"$mockbin\"" EXIT
    cat > "$mockbin/jq" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\${1:-}" == "-r" ]]; then
  exec "$real_jq" "\$@"
fi
exit 1
EOF
    chmod 755 "$mockbin/jq"
    PATH="$mockbin:$PATH"
    set +e
    export_canary_bundle "$tmp_dir/clients.json" "$tmp_dir/export/canary"
    rc=$?
    set -e
    echo "rc=$rc"
    cat "$tmp_dir/export/canary/manifest.json"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"export_canary_bundle: не удалось сформировать source JSON"* ]]
    [[ "$output" == *"rc=1"* ]]
    [[ "$output" == *"sentinel-manifest"* ]]
}

@test "export_canary_bundle fails closed on raw basename collision" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./export.sh
    tmp_dir=$(mktemp -d)
    trap "rm -rf \"$tmp_dir\"" EXIT
    XRAY_KEYS="$tmp_dir"
    XRAY_GROUP="root"
    mkdir -p "$tmp_dir/export/canary" "$tmp_dir/a" "$tmp_dir/b"
    printf "sentinel-manifest\n" > "$tmp_dir/export/canary/manifest.json"
    printf "{}\n" > "$tmp_dir/a/config-1-recommended-ipv4.json"
    printf "{}\n" > "$tmp_dir/b/config-1-recommended-ipv4.json"
    cat > "$tmp_dir/clients.json" <<JSON
{
  "schema_version": 3,
  "stealth_contract_version": "7.5.5",
  "xray_min_version": "25.9.5",
  "generated": "2026-03-19T00:00:00Z",
  "transport": "xhttp",
  "configs": [
    {
      "name": "Config 1",
      "domain": "disk.yandex.ru",
      "recommended_variant": "recommended",
      "variants": [
        {
          "key": "recommended",
          "category": "primary",
          "mode": "auto",
          "requires": {"browser_dialer": false},
          "import_hint": "hint",
          "xray_client_file_v4": "$tmp_dir/a/config-1-recommended-ipv4.json"
        },
        {
          "key": "rescue",
          "category": "fallback",
          "mode": "packet-up",
          "requires": {"browser_dialer": false},
          "import_hint": "hint",
          "xray_client_file_v4": "$tmp_dir/b/config-1-recommended-ipv4.json"
        }
      ]
    }
  ]
}
JSON
    set +e
    export_canary_bundle "$tmp_dir/clients.json" "$tmp_dir/export/canary"
    rc=$?
    set -e
    echo "rc=$rc"
    cat "$tmp_dir/export/canary/manifest.json"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"export_canary_bundle: коллизия raw-xray имени: config-1-recommended-ipv4.json"* ]]
    [[ "$output" == *"rc=1"* ]]
    [[ "$output" == *"sentinel-manifest"* ]]
}
