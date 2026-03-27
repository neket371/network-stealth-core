#!/usr/bin/env bash
# shellcheck shell=bash

: "${MUX_MODE:=off}" # ignored on normal xhttp-first installs
# legacy grpc/mux compatibility knobs remain only for migrate-stealth and explicit legacy rebuilds.
: "${MUX_ENABLED:=false}"
: "${MUX_CONCURRENCY:=0}"
: "${MUX_CONCURRENCY_MIN:=3}"
: "${MUX_CONCURRENCY_MAX:=20}"
: "${GRPC_IDLE_TIMEOUT_MIN:=60}"
: "${GRPC_IDLE_TIMEOUT_MAX:=1800}"
: "${GRPC_HEALTH_TIMEOUT_MIN:=10}"
: "${GRPC_HEALTH_TIMEOUT_MAX:=30}"
: "${TCP_KEEPALIVE_MIN:=20}"
: "${TCP_KEEPALIVE_MAX:=45}"

transport_normalize() {
    local transport="${1:-${TRANSPORT:-xhttp}}"
    transport="${transport,,}"
    case "$transport" in
        "" | xhttp)
            printf '%s\n' "xhttp"
            ;;
        http2 | h2 | http/2)
            printf '%s\n' "http2"
            ;;
        grpc)
            printf '%s\n' "grpc"
            ;;
        *)
            printf '%s\n' "$transport"
            ;;
    esac
}

transport_normalize_assign() {
    local out_name="$1"
    local raw_value="${2:-}"
    local -n out_ref="$out_name"

    if [[ -z "$raw_value" ]]; then
        raw_value="${out_ref:-${TRANSPORT:-xhttp}}"
    fi
    out_ref="$(transport_normalize "$raw_value")"
}

transport_is_xhttp() {
    [[ "$(transport_normalize "${1:-${TRANSPORT:-xhttp}}")" == "xhttp" ]]
}

transport_is_legacy() {
    case "$(transport_normalize "${1:-${TRANSPORT:-xhttp}}")" in
        grpc | http2) return 0 ;;
        *) return 1 ;;
    esac
}
