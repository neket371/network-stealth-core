# Shell Audit Coverage Matrix

Date: 2026-03-04  
Branch: `ubuntu`  
Audited files: 43/43

| File | Lines | Review status |
|---|---:|---|
| config.sh | 1002 | Reviewed (Automated + Manual) |
| export.sh | 501 | Reviewed (Automated + Manual) |
| health.sh | 709 | Reviewed (Automated + Manual) |
| install.sh | 1004 | Reviewed (Automated + Manual) |
| lib.sh | 2451 | Reviewed (Automated + Manual) |
| modules/config/add_clients.sh | 789 | Reviewed (Automated + Manual) |
| modules/config/domain_planner.sh | 728 | Reviewed (Automated + Manual) |
| modules/config/shared_helpers.sh | 98 | Reviewed (Automated + Manual) |
| modules/install/bootstrap.sh | 376 | Reviewed (Automated + Manual) |
| modules/lib/cli.sh | 478 | Reviewed (Automated + Manual) |
| modules/lib/common_utils.sh | 16 | Reviewed (Automated + Manual) |
| modules/lib/domain_sources.sh | 202 | Reviewed (Automated + Manual) |
| modules/lib/firewall.sh | 194 | Reviewed (Automated + Manual) |
| modules/lib/globals_contract.sh | 156 | Reviewed (Automated + Manual) |
| modules/lib/lifecycle.sh | 198 | Reviewed (Automated + Manual) |
| modules/lib/runtime_reuse.sh | 147 | Reviewed (Automated + Manual) |
| modules/lib/validation.sh | 157 | Reviewed (Automated + Manual) |
| scripts/check-dead-functions.sh | 50 | Reviewed (Automated + Manual) |
| scripts/check-docs-commands.sh | 53 | Reviewed (Automated + Manual) |
| scripts/check-release-consistency.sh | 138 | Reviewed (Automated + Manual) |
| scripts/check-security-baseline.sh | 133 | Reviewed (Automated + Manual) |
| scripts/check-shell-complexity.sh | 124 | Reviewed (Automated + Manual) |
| scripts/check-shellcheck-advisory.sh | 30 | Reviewed (Automated + Manual) |
| scripts/check-workflow-pinning.sh | 38 | Reviewed (Automated + Manual) |
| scripts/release-policy-gate.sh | 86 | Reviewed (Automated + Manual) |
| scripts/release.sh | 225 | Reviewed (Automated + Manual) |
| service.sh | 1035 | Reviewed (Automated + Manual) |
| tests/bats/helpers/mocks.bash | 54 | Reviewed (Automated + Manual) |
| tests/e2e/add_clients_enospc_rollback.sh | 99 | Reviewed (Automated + Manual) |
| tests/e2e/broken_config_rollback_smoke.sh | 109 | Reviewed (Automated + Manual) |
| tests/e2e/download_failure_preserves_binary.sh | 56 | Reviewed (Automated + Manual) |
| tests/e2e/forced_restart_failure_rolls_back.sh | 110 | Reviewed (Automated + Manual) |
| tests/e2e/idempotent_install_uninstall.sh | 79 | Reviewed (Automated + Manual) |
| tests/e2e/install_status_add_uninstall.sh | 68 | Reviewed (Automated + Manual) |
| tests/e2e/interactive_install_add_keys_uninstall.sh | 114 | Reviewed (Automated + Manual) |
| tests/e2e/ipv6_install_add_uninstall.sh | 82 | Reviewed (Automated + Manual) |
| tests/e2e/lib.sh | 65 | Reviewed (Automated + Manual) |
| tests/e2e/minisign_bootstrap_allow_unverified.sh | 68 | Reviewed (Automated + Manual) |
| tests/e2e/minisign_fail_cleans_temp.sh | 110 | Reviewed (Automated + Manual) |
| tests/e2e/nightly_smoke_install_add_update_uninstall.sh | 210 | Reviewed (Automated + Manual) |
| tests/e2e/os_matrix_smoke.sh | 97 | Reviewed (Automated + Manual) |
| tests/lint.sh | 160 | Reviewed (Automated + Manual) |
| xray-reality.sh | 381 | Reviewed (Automated + Manual) |

## Verification bundle used

- `make ci`
- `bash scripts/check-shellcheck-advisory.sh`
- `bash tests/lint.sh --fast`
- `bash tests/lint.sh`

