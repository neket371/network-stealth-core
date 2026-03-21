# shellcheck shell=bash

: "${STEALTH_CONTRACT_VERSION_DEFAULT:=7.3.8}"
: "${XRAY_CLIENT_MIN_VERSION_DEFAULT:=25.9.5}"

# managed strongest-direct contract epoch; this is independent from the release tag.
: "${STEALTH_CONTRACT_VERSION:=${STEALTH_CONTRACT_VERSION_DEFAULT}}"
: "${XRAY_CLIENT_MIN_VERSION:=${XRAY_CLIENT_MIN_VERSION_DEFAULT}}"
