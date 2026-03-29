#!/usr/bin/env bash
# shellcheck shell=bash

CLIENT_ARTIFACTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

CONFIG_CLIENT_FORMATS_MODULE="${CLIENT_ARTIFACTS_DIR}/client_formats.sh"
if [[ ! -f "$CONFIG_CLIENT_FORMATS_MODULE" && "${XRAY_SOURCE_TREE_STRICT:-false}" != "true" && -n "${XRAY_DATA_DIR:-}" ]]; then
    CONFIG_CLIENT_FORMATS_MODULE="$XRAY_DATA_DIR/modules/config/client_formats.sh"
fi
if [[ ! -f "$CONFIG_CLIENT_FORMATS_MODULE" ]]; then
    log ERROR "Не найден модуль client formats: $CONFIG_CLIENT_FORMATS_MODULE"
    exit 1
fi
# shellcheck source=modules/config/client_formats.sh
source "$CONFIG_CLIENT_FORMATS_MODULE"

CONFIG_CLIENT_STATE_MODULE="${CLIENT_ARTIFACTS_DIR}/client_state.sh"
if [[ ! -f "$CONFIG_CLIENT_STATE_MODULE" && "${XRAY_SOURCE_TREE_STRICT:-false}" != "true" && -n "${XRAY_DATA_DIR:-}" ]]; then
    CONFIG_CLIENT_STATE_MODULE="$XRAY_DATA_DIR/modules/config/client_state.sh"
fi
if [[ ! -f "$CONFIG_CLIENT_STATE_MODULE" ]]; then
    log ERROR "Не найден модуль client state: $CONFIG_CLIENT_STATE_MODULE"
    exit 1
fi
# shellcheck source=modules/config/client_state.sh
source "$CONFIG_CLIENT_STATE_MODULE"
