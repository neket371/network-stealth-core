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
