#!/usr/bin/env bash
# shellcheck shell=bash

print_usage() {
    cat << 'USAGE'
Usage: xray-reality.sh <command> [options]

Commands:
  install                        Install Network Stealth Core (auto для РФ)
  add-clients [N]                Add N configs to existing setup (tier-aware limit)
  add-keys [N]                   Alias of add-clients [N]
  update                         Update Xray-core
  repair                         Re-apply units/firewall/monitoring and recover artifacts
  migrate-stealth                Convert managed legacy or pre-v7 xhttp installs to strongest direct stack
  status                         Show current configuration and status
  logs [xray|health|all]         View service logs (default: all)
  diagnose                       Collect diagnostics
  rollback [dir]                 Roll back to backup
  uninstall                      Full removal (ports, configs, user, all)
  check-update                   Check for available updates

Options:
  --config <file>                Load config file (key=value)
  --dry-run                      Show actions without executing
  --verbose                      More logging (also: detailed status)
  --yes, --non-interactive       Skip prompts (automation mode)
  --advanced                     Enable manual domain-profile prompt flow
  --num-configs <N>              Number of configs (tier-aware limit)
  --domain-profile <ru|ru-auto|global-50|global-50-auto|custom>
                                   Domain profile for install/add (default install path: ru-auto)
  --start-port <1-65535>         Starting port (default: 443)
  --transport <xhttp>            Transport mode (fixed to xhttp in v7)
  --replan                       Rebuild client priority from latest self-check + field measurements
  --progress-mode <mode>         Progress output: auto|bar|plain|none
  --require-minisign             Fail when minisign is unavailable or signature is missing
  --allow-no-systemd             Allow install/update/repair without systemd (compat mode)
  --server-ip <ipv4>             Set server IPv4
  --server-ip6 <ipv6>            Set server IPv6
  --primary-domain-mode <mode>   First domain mode: adaptive|pinned
  --primary-pin-domain <domain>  Pinned first domain when mode=pinned
  --primary-adaptive-top-n <N>   Top-N candidate pool for adaptive mode
  --domain-check-parallelism <N> Max parallel domain probes during install check
  --domain-quarantine-fail-streak <N>
                                 Quarantine threshold by fail streak
  --domain-quarantine-cooldown-min <minutes>
                                 Quarantine cooldown window
  --xray-version <ver>           Override Xray version
  --help                         Show this help

Environment variables:
  XRAY_DOMAIN_PROFILE            Domain profile (ru|ru-auto|global-50|global-50-auto|custom; legacy aliases global-ms10*)
  TRANSPORT                      Transport mode (xhttp only in v7)
  SELF_CHECK_ENABLED             Enable transport-aware post-action self-check (default: true)
  SELF_CHECK_URLS                Comma-separated probe URLs for xhttp self-check
  SELF_CHECK_TIMEOUT_SEC         Curl timeout per self-check probe (default: 8)
  XRAY_ADVANCED                  Enable manual domain-profile prompt flow
  SHORT_ID_BYTES_MIN             Min Reality ShortID bytes (default: 8)
  SHORT_ID_BYTES_MAX             Max Reality ShortID bytes (default: 8)
  DOMAIN_HEALTH_RANKING          Use adaptive domain ranking (default: true)
  DOMAIN_HEALTH_PROBE_TIMEOUT    Domain probe timeout in health monitor (default: 2)
  DOMAIN_HEALTH_RATE_LIMIT_MS    Min delay between domain probes in health monitor (default: 250)
  DOMAIN_HEALTH_MAX_PROBES       Max domains probed per health cycle (default: 20)
  DOMAIN_HEALTH_FILE             Domain health score file path
  DOMAIN_CHECK_PARALLELISM       Parallel domain checks during install (default: 16)
  DOMAIN_QUARANTINE_FAIL_STREAK  Quarantine threshold by fail streak (default: 4)
  DOMAIN_QUARANTINE_COOLDOWN_MIN Quarantine cooldown in minutes (default: 120)
  PRIMARY_DOMAIN_MODE            First config domain mode: adaptive|pinned (default: adaptive)
  PRIMARY_PIN_DOMAIN             First config domain in pinned mode (default: first domain from tiers)
  PRIMARY_ADAPTIVE_TOP_N         Top-N candidates used in adaptive mode (default: 5)
  PROGRESS_MODE                  Progress output mode: auto|bar|plain|none (default: auto)
  DOWNLOAD_HOST_ALLOWLIST        Allowlist for critical download hosts (comma-separated)
  GH_PROXY_BASE                  Optional proxy base for github release mirrors
  XRAY_FAILURE_PROOF_DIR         Maintainer-only directory for failure proof artifacts
  ALLOW_UNVERIFIED_MINISIGN_BOOTSTRAP
                                  Allow minisign bootstrap download (default: false)
  REQUIRE_MINISIGN               Require minisign on install/update/repair (default: false)
  ALLOW_NO_SYSTEMD               Allow install/update/repair without systemd (default: false)
  GEO_VERIFY_HASH                Verify GeoIP/GeoSite SHA256 in updater (default: true)
  GEO_VERIFY_STRICT              Fail update when checksum file is unavailable (default: false)
  HEALTH_CHECK_INTERVAL          Health timer interval in seconds (default: 120)
  LOG_RETENTION_DAYS             Health log retention (default: 30)
  LOG_MAX_SIZE_MB                Max health log size in MB (default: 10)
USAGE
}
