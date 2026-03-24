#!/usr/bin/env bats

@test "check_update_flow version regex keeps literal dash in prerelease suffix" {
    run bash -eo pipefail -c '
    grep -Fq '\''([-.][0-9A-Za-z]+)*$'\'' ./service.sh
    ! grep -Fq '\''([.-][0-9A-Za-z]+)*$'\'' ./service.sh
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "sync_transport_endpoint_file_contract prefers neutral seed path" {
    run bash -eo pipefail -c '
    source ./modules/lib/globals_contract.sh
    tmpdir=$(mktemp -d)
    trap "rm -rf \"$tmpdir\"" EXIT
    XRAY_DATA_DIR="$tmpdir"
    : > "$tmpdir/transport_endpoints.map"
    XRAY_TRANSPORT_ENDPOINTS_FILE=""
    XRAY_GRPC_SERVICES_FILE=""
    sync_transport_endpoint_file_contract
    echo "primary=$XRAY_TRANSPORT_ENDPOINTS_FILE"
    echo "alias=$XRAY_GRPC_SERVICES_FILE"
  '
    [ "$status" -eq 0 ]
    [[ "${lines[0]}" == primary=*transport_endpoints.map ]]
    [ "${lines[1]}" = "alias=${lines[0]#primary=}" ]
}

@test "sync_transport_endpoint_file_contract falls back to legacy grpc map when needed" {
    run bash -eo pipefail -c '
    source ./modules/lib/globals_contract.sh
    tmpdir=$(mktemp -d)
    trap "rm -rf \"$tmpdir\"" EXIT
    XRAY_DATA_DIR="$tmpdir"
    : > "$tmpdir/grpc_services.map"
    XRAY_TRANSPORT_ENDPOINTS_FILE=""
    XRAY_GRPC_SERVICES_FILE=""
    sync_transport_endpoint_file_contract
    echo "primary=$XRAY_TRANSPORT_ENDPOINTS_FILE"
    echo "alias=$XRAY_GRPC_SERVICES_FILE"
  '
    [ "$status" -eq 0 ]
    [[ "${lines[0]}" == primary=*grpc_services.map ]]
    [ "${lines[1]}" = "alias=${lines[0]#primary=}" ]
}

@test "_path_has_parent_segments matches real traversal segments only" {
    run bash -eo pipefail -c '
    source ./lib.sh
    _path_has_parent_segments "/etc/xray/dir/../config.json"
    ! _path_has_parent_segments "/etc/xray/config..json"
    ! _path_has_parent_segments "/etc/xray/dir..name/config.json"
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "rand_u32 fallback widens RANDOM entropy beyond 15 bits" {
    run bash -eo pipefail -c '
    source ./lib.sh
    od() { return 1; }
    openssl() { return 1; }
    rand_u32 > /dev/null
    (( RAND_U32_MAX > 32767 ))
    (( RAND_U32_VALUE >= 0 ))
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "resolve_paths preserves custom data-file overrides" {
    run bash -eo pipefail -c '
    source ./lib.sh
    log() { :; }
    _resolve_path() {
      local var_name="$1"
      case "$var_name" in
        XRAY_BIN) printf -v "$var_name" "%s" "/opt/xray/bin/xray" ;;
        XRAY_GEO_DIR) printf -v "$var_name" "%s" "/opt/xray/share" ;;
        XRAY_CONFIG) printf -v "$var_name" "%s" "/opt/xray/etc/config.json" ;;
        XRAY_KEYS) printf -v "$var_name" "%s" "/opt/xray/etc/private/keys" ;;
        MINISIGN_KEY) printf -v "$var_name" "%s" "/opt/xray/etc/minisign.pub" ;;
        XRAY_ENV) printf -v "$var_name" "%s" "/opt/xray/etc/config.env" ;;
        XRAY_POLICY) printf -v "$var_name" "%s" "/opt/xray/etc/policy.json" ;;
        XRAY_LOGS) printf -v "$var_name" "%s" "/opt/xray/log" ;;
        XRAY_HOME) printf -v "$var_name" "%s" "/opt/xray/data" ;;
        MEASUREMENTS_DIR) printf -v "$var_name" "%s" "/opt/xray/data/measurements" ;;
        XRAY_BACKUP) printf -v "$var_name" "%s" "/opt/xray/backups" ;;
        XRAY_DATA_DIR) printf -v "$var_name" "%s" "/opt/xray/share" ;;
      esac
      return 0
    }

    XRAY_DATA_DIR="/usr/local/share/xray-reality"
    XRAY_TIERS_FILE="/custom/domains.tiers"
    XRAY_SNI_POOLS_FILE="/custom/sni_pools.map"
    XRAY_TRANSPORT_ENDPOINTS_FILE="/custom/transport_endpoints.map"
    XRAY_GRPC_SERVICES_FILE="/custom/grpc_services.map"
    XRAY_DOMAIN_CATALOG_FILE="/custom/catalog.json"

    resolve_paths

    [[ "$XRAY_TIERS_FILE" == "/custom/domains.tiers" ]]
    [[ "$XRAY_SNI_POOLS_FILE" == "/custom/sni_pools.map" ]]
    [[ "$XRAY_TRANSPORT_ENDPOINTS_FILE" == "/custom/transport_endpoints.map" ]]
    [[ "$XRAY_GRPC_SERVICES_FILE" == "/custom/grpc_services.map" ]]
    [[ "$XRAY_DOMAIN_CATALOG_FILE" == "/custom/catalog.json" ]]
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "resolve_paths rebinds managed default data files to resolved data dir" {
    run bash -eo pipefail -c '
    source ./lib.sh
    log() { :; }
    _resolve_path() {
      local var_name="$1"
      case "$var_name" in
        XRAY_BIN) printf -v "$var_name" "%s" "/opt/xray/bin/xray" ;;
        XRAY_GEO_DIR) printf -v "$var_name" "%s" "/opt/xray/share" ;;
        XRAY_CONFIG) printf -v "$var_name" "%s" "/opt/xray/etc/config.json" ;;
        XRAY_KEYS) printf -v "$var_name" "%s" "/opt/xray/etc/private/keys" ;;
        MINISIGN_KEY) printf -v "$var_name" "%s" "/opt/xray/etc/minisign.pub" ;;
        XRAY_ENV) printf -v "$var_name" "%s" "/opt/xray/etc/config.env" ;;
        XRAY_POLICY) printf -v "$var_name" "%s" "/opt/xray/etc/policy.json" ;;
        XRAY_LOGS) printf -v "$var_name" "%s" "/opt/xray/log" ;;
        XRAY_HOME) printf -v "$var_name" "%s" "/opt/xray/data" ;;
        MEASUREMENTS_DIR) printf -v "$var_name" "%s" "/opt/xray/data/measurements" ;;
        XRAY_BACKUP) printf -v "$var_name" "%s" "/opt/xray/backups" ;;
        XRAY_DATA_DIR) printf -v "$var_name" "%s" "/opt/xray/share" ;;
      esac
      return 0
    }

    XRAY_DATA_DIR="/usr/local/share/xray-reality"
    XRAY_TIERS_FILE="/usr/local/share/xray-reality/domains.tiers"
    XRAY_SNI_POOLS_FILE="/usr/local/share/xray-reality/sni_pools.map"
    XRAY_TRANSPORT_ENDPOINTS_FILE="/usr/local/share/xray-reality/transport_endpoints.map"
    XRAY_GRPC_SERVICES_FILE="/usr/local/share/xray-reality/transport_endpoints.map"
    XRAY_DOMAIN_CATALOG_FILE="/usr/local/share/xray-reality/data/domains/catalog.json"

    resolve_paths

    [[ "$XRAY_TIERS_FILE" == "/opt/xray/share/domains.tiers" ]]
    [[ "$XRAY_SNI_POOLS_FILE" == "/opt/xray/share/sni_pools.map" ]]
    [[ "$XRAY_TRANSPORT_ENDPOINTS_FILE" == "/opt/xray/share/transport_endpoints.map" ]]
    [[ "$XRAY_GRPC_SERVICES_FILE" == "/opt/xray/share/transport_endpoints.map" ]]
    [[ "$XRAY_DOMAIN_CATALOG_FILE" == "/opt/xray/share/data/domains/catalog.json" ]]
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}
