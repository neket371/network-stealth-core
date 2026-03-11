# audit coverage matrix

date: 2026-03-11
repository: `neket371/network-stealth-core`
branch: `ubuntu`
baseline commit: `c848ef7ca8ed3679d7e2cfe5ac6649ee21ff24f4`
total repo-tracked files reviewed: **123**

review depth meanings:
- `manual semantic` — file behavior and contracts were traced manually.
- `contract consistency` — file was reviewed against current runtime/docs/workflow contracts.
- `inventory-only` — file was inventoried and classified, but has no deep runtime semantics.

| file | lines | class | role | review depth | status | notes |
|---|---:|---|---|---|---|---|
| `.dockerignore` | 6 | repo meta | docker build exclusion rules | inventory-only | reviewed | — |
| `.gitattributes` | 8 | repo meta | git attribute rules | inventory-only | reviewed | — |
| `.github/CONTRIBUTING.md` | 127 | doc | english maintainer/contributor doc | contract consistency | reviewed | — |
| `.github/CONTRIBUTING.ru.md` | 127 | doc | russian maintainer/contributor doc | contract consistency | reviewed | — |
| `.github/SECURITY.md` | 152 | doc | english security policy doc | contract consistency | reviewed | — |
| `.github/SECURITY.ru.md` | 152 | doc | russian security policy doc | contract consistency | reviewed | — |
| `.github/workflows/ci.yml` | 296 | workflow | primary ci workflow | contract consistency | reviewed | — |
| `.github/workflows/nightly-smoke.yml` | 83 | workflow | nightly smoke workflow | contract consistency | reviewed | — |
| `.github/workflows/os-matrix-smoke.yml` | 55 | workflow | os support smoke workflow | contract consistency | reviewed | — |
| `.github/workflows/packages.yml` | 91 | workflow | package/build workflow | contract consistency | reviewed | — |
| `.github/workflows/release.yml` | 307 | workflow | tagged release workflow | contract consistency | reviewed | — |
| `.github/workflows/self-hosted-smoke.yml` | 49 | workflow | self-hosted smoke workflow | contract consistency | reviewed | — |
| `.markdownlint.json` | 11 | repo meta | markdown lint policy | inventory-only | reviewed | — |
| `AUDIT_COVERAGE_MATRIX.md` | 144 | doc | audit inventory and review coverage matrix | contract consistency | reviewed | — |
| `AUDIT_FINDINGS_BACKLOG.md` | 80 | doc | prioritized audit backlog | contract consistency | reviewed | — |
| `AUDIT_REPORT_FULL.md` | 242 | doc | full audit narrative and findings | contract consistency | reviewed | — |
| `AUDIT_RUNTIME_MAP.md` | 145 | doc | per-script runtime responsibility map | contract consistency | reviewed | — |
| `config.sh` | 730 | runtime entrypoint | config builder and config/runtime apply helpers | manual semantic | reviewed | client artifact logic moved into focused module; f-003 remains open elsewhere |
| `data/domains/catalog.json` | 4618 | data contract | canonical domain metadata catalog | manual semantic | reviewed | planner still combines catalog with side maps and tier files |
| `Dockerfile` | 50 | build/tooling | container packaging and smoke runtime image | manual semantic | reviewed | runtime bundle now ships neutral transport endpoint seed file |
| `docs/en/ARCHITECTURE.md` | 152 | doc | english architecture doc | contract consistency | reviewed | — |
| `docs/en/CHANGELOG.md` | 130 | doc | english changelog doc | contract consistency | reviewed | — |
| `docs/en/COMMUNITY.md` | 54 | doc | english community doc | contract consistency | reviewed | — |
| `docs/en/FAQ.md` | 104 | doc | english faq doc | contract consistency | reviewed | — |
| `docs/en/GLOSSARY.md` | 82 | doc | english glossary doc | contract consistency | reviewed | — |
| `docs/en/INDEX.md` | 57 | doc | english index doc | contract consistency | reviewed | — |
| `docs/en/MAINTAINER-LAB.md` | 95 | doc | english maintainer-lab doc | contract consistency | reviewed | — |
| `docs/en/OPERATIONS.md` | 241 | doc | english operations doc | contract consistency | reviewed | — |
| `docs/en/ROADMAP.md` | 35 | doc | english roadmap doc | contract consistency | reviewed | — |
| `docs/en/TROUBLESHOOTING.md` | 125 | doc | english troubleshooting doc | contract consistency | reviewed | — |
| `docs/ru/ARCHITECTURE.md` | 152 | doc | russian architecture doc | contract consistency | reviewed | — |
| `docs/ru/CHANGELOG.md` | 117 | doc | russian changelog doc | contract consistency | reviewed | — |
| `docs/ru/COMMUNITY.md` | 54 | doc | russian community doc | contract consistency | reviewed | — |
| `docs/ru/FAQ.md` | 104 | doc | russian faq doc | contract consistency | reviewed | — |
| `docs/ru/GLOSSARY.md` | 82 | doc | russian glossary doc | contract consistency | reviewed | — |
| `docs/ru/INDEX.md` | 57 | doc | russian index doc | contract consistency | reviewed | — |
| `docs/ru/MAINTAINER-LAB.md` | 95 | doc | russian maintainer-lab doc | contract consistency | reviewed | — |
| `docs/ru/OPERATIONS.md` | 241 | doc | russian operations doc | contract consistency | reviewed | — |
| `docs/ru/ROADMAP.md` | 35 | doc | russian roadmap doc | contract consistency | reviewed | — |
| `docs/ru/TROUBLESHOOTING.md` | 125 | doc | russian troubleshooting doc | contract consistency | reviewed | — |
| `domains.tiers` | 237 | data contract | legacy tier domain source | manual semantic | reviewed | planner still uses multi-source domain contract alongside catalog |
| `export.sh` | 328 | runtime entrypoint | client export entry helpers | manual semantic | reviewed | — |
| `transport_endpoints.map` | 202 | data contract | neutral legacy transport endpoint seed source for grpc/http2 compatibility | manual semantic | reviewed | active xhttp path no longer references grpc-named seed files |
| `health.sh` | 719 | runtime entrypoint | health diagnostics and monitor entry helpers | manual semantic | reviewed | — |
| `install.sh` | 1406 | runtime entrypoint | install/update/repair/migrate/rollback entry flows | manual semantic | reviewed | f-003: still large and action-dense |
| `lib.sh` | 2513 | runtime entrypoint | global runtime orchestrator and action dispatcher | manual semantic | reviewed | f-003: file remains large |
| `LICENSE` | 21 | repo meta | license text | inventory-only | reviewed | — |
| `Makefile` | 75 | build/tooling | local qa and audit entrypoints | manual semantic | reviewed | — |
| `modules/config/add_clients.sh` | 686 | runtime module | add-clients runtime flow | manual semantic | reviewed | — |
| `modules/config/client_artifacts.sh` | 1146 | runtime module | client artifact rendering, json normalization, rebuild, and self-check readiness helpers | manual semantic | reviewed | extracted from `config.sh` to narrow root entrypoint scope |
| `modules/config/domain_planner.sh` | 933 | runtime module | domain planning and profile generation helpers | manual semantic | reviewed | legacy transport seeds renamed; planner still has multi-source complexity |
| `modules/service/uninstall.sh` | 461 | runtime module | uninstall file removal, account cleanup, and destructive guard helpers | manual semantic | reviewed | extracted from `service.sh` to narrow root entrypoint scope |
| `modules/config/shared_helpers.sh` | 162 | runtime module | transport/tier/helper formatting and compatibility helpers | manual semantic | reviewed | transport compatibility helpers are now transport-neutral where active |
| `modules/export/capabilities.sh` | 141 | runtime module | export capability matrix and compatibility notes helpers | manual semantic | reviewed | — |
| `modules/health/measurements.sh` | 312 | runtime module | measurement import/compare/prune helpers | manual semantic | reviewed | — |
| `modules/health/self_check.sh` | 777 | runtime module | post-action transport-aware self-check engine | manual semantic | reviewed | — |
| `modules/install/bootstrap.sh` | 427 | runtime module | install/update bootstrap staging helpers | manual semantic | reviewed | bootstrap now ships neutral transport endpoint seed file |
| `modules/lib/cli.sh` | 531 | runtime module | cli parsing and runtime override resolution | manual semantic | reviewed | — |
| `modules/lib/common_utils.sh` | 18 | runtime module | shared low-level helper primitives | manual semantic | reviewed | — |
| `modules/lib/contract_gate.sh` | 91 | runtime module | legacy/pre-v7 mutating gate logic | manual semantic | reviewed | — |
| `modules/lib/domain_sources.sh` | 348 | runtime module | domain/map loading helpers | manual semantic | reviewed | — |
| `modules/lib/firewall.sh` | 203 | runtime module | firewall mutation helpers | manual semantic | reviewed | — |
| `modules/lib/globals_contract.sh` | 198 | runtime module | global variable defaults and contracts | manual semantic | reviewed | transport endpoint seed contract now has neutral primary naming |
| `modules/lib/lifecycle.sh` | 216 | runtime module | backup/rollback/cleanup helpers | manual semantic | reviewed | — |
| `modules/lib/policy.sh` | 225 | runtime module | policy.json load/save helpers | manual semantic | reviewed | — |
| `modules/lib/runtime_reuse.sh` | 266 | runtime module | runtime reuse and existing-config extraction | manual semantic | reviewed | — |
| `modules/lib/tty.sh` | 359 | runtime module | interactive tty normalization and yes/no prompts | manual semantic | reviewed | — |
| `modules/lib/usage.sh` | 83 | runtime module | public help text contract | manual semantic | reviewed | — |
| `modules/lib/validation.sh` | 189 | runtime module | input validation helpers | manual semantic | reviewed | — |
| `README.md` | 240 | doc | english user-facing entry doc | contract consistency | reviewed | — |
| `README.ru.md` | 240 | doc | russian user-facing entry doc | contract consistency | reviewed | — |
| `scripts/check-dead-functions.sh` | 162 | qa/release script | dead function guard | manual semantic | reviewed | — |
| `scripts/check-docs-commands.sh` | 67 | qa/release script | docs command contract guard | manual semantic | reviewed | — |
| `scripts/check-release-consistency.sh` | 154 | qa/release script | release/changelog consistency guard | manual semantic | reviewed | — |
| `scripts/check-security-baseline.sh` | 150 | qa/release script | security baseline guard | manual semantic | reviewed | — |
| `scripts/check-shell-complexity.sh` | 135 | qa/release script | shell complexity gate | manual semantic | reviewed | — |
| `scripts/check-shellcheck-advisory.sh` | 36 | qa/release script | advisory shellcheck pass | manual semantic | reviewed | — |
| `scripts/check-workflow-pinning.sh` | 46 | qa/release script | workflow action pinning guard | manual semantic | reviewed | — |
| `scripts/lab/collect-container-artifacts.sh` | 95 | lab script | container lab artifact collector | manual semantic | reviewed | — |
| `scripts/lab/collect-vm-artifacts.sh` | 105 | lab script | vm lab artifact collector | manual semantic | reviewed | — |
| `scripts/lab/common.sh` | 265 | lab script | shared lab helpers and defaults | manual semantic | reviewed | — |
| `scripts/lab/enter-vm-smoke.sh` | 79 | lab script | vm guest entry helper | manual semantic | reviewed | — |
| `scripts/lab/guest-vm-lifecycle.sh` | 201 | lab script | vm guest bootstrap and helper installation | manual semantic | reviewed | — |
| `scripts/lab/prepare-host-safe-smoke.sh` | 46 | lab script | busy-host safe container prep | manual semantic | reviewed | — |
| `scripts/lab/prepare-vm-smoke.sh` | 131 | lab script | vm lab image and state prep | manual semantic | reviewed | — |
| `scripts/lab/run-container-smoke.sh` | 160 | lab script | host-safe container smoke runner | manual semantic | reviewed | — |
| `scripts/lab/run-vm-lifecycle-smoke.sh` | 299 | lab script | full vm lifecycle smoke runner | manual semantic | reviewed | — |
| `scripts/markdownlint.ps1` | 67 | qa/release script | windows markdown lint wrapper | manual semantic | reviewed | — |
| `scripts/measure-stealth.sh` | 519 | qa/release script | field measurement operator tool | manual semantic | reviewed | — |
| `scripts/release-policy-gate.sh` | 98 | qa/release script | release artifact policy gate | manual semantic | reviewed | — |
| `scripts/release.sh` | 253 | qa/release script | release cut helper | manual semantic | reviewed | — |
| `scripts/windows/detect-bash.ps1` | 112 | windows helper | windows bash discovery helper | manual semantic | reviewed | — |
| `scripts/windows/run-validation.ps1` | 164 | windows helper | windows validation orchestrator | manual semantic | reviewed | — |
| `service.sh` | 902 | runtime entrypoint | systemd status/logs/check-update service control and module composition | manual semantic | reviewed | uninstall cleanup moved into focused module; f-003 remains open elsewhere |
| `sni_pools.map` | 202 | data contract | legacy sni pool source | manual semantic | reviewed | planner still uses multi-source domain contract alongside catalog |
| `tests/bats/config_generation.bats` | 106 | bats test | bats suite: config_generation | manual semantic | reviewed | — |
| `tests/bats/domain_loading.bats` | 350 | bats test | bats suite: domain_loading | manual semantic | reviewed | — |
| `tests/bats/download.bats` | 172 | bats test | bats suite: download | manual semantic | reviewed | — |
| `tests/bats/error_handling.bats` | 213 | bats test | bats suite: error_handling | manual semantic | reviewed | — |
| `tests/bats/health.bats` | 598 | bats test | bats suite: health | manual semantic | reviewed | — |
| `tests/bats/helpers/mocks.bash` | 61 | bats test | shared bats mocks | manual semantic | reviewed | — |
| `tests/bats/input_validation.bats` | 290 | bats test | bats suite: input_validation | manual semantic | reviewed | — |
| `tests/bats/integration.bats` | 808 | bats test | bats suite: integration | manual semantic | reviewed | — |
| `tests/bats/rollback.bats` | 53 | bats test | bats suite: rollback | manual semantic | reviewed | — |
| `tests/bats/smoke.bats` | 28 | bats test | bats suite: smoke | manual semantic | reviewed | — |
| `tests/bats/transport.bats` | 76 | bats test | bats suite: transport | manual semantic | reviewed | — |
| `tests/bats/unit.bats` | 3599 | bats test | bats suite: unit | manual semantic | reviewed | — |
| `tests/bats/validation.bats` | 565 | bats test | bats suite: validation | manual semantic | reviewed | — |
| `tests/e2e/add_clients_enospc_rollback.sh` | 114 | e2e test | e2e scenario: add_clients_enospc_rollback | manual semantic | reviewed | — |
| `tests/e2e/broken_config_rollback_smoke.sh` | 125 | e2e test | e2e scenario: broken_config_rollback_smoke | manual semantic | reviewed | — |
| `tests/e2e/download_failure_preserves_binary.sh` | 69 | e2e test | e2e scenario: download_failure_preserves_binary | manual semantic | reviewed | — |
| `tests/e2e/forced_restart_failure_rolls_back.sh` | 128 | e2e test | e2e scenario: forced_restart_failure_rolls_back | manual semantic | reviewed | — |
| `tests/e2e/idempotent_install_uninstall.sh` | 96 | e2e test | e2e scenario: idempotent_install_uninstall | manual semantic | reviewed | — |
| `tests/e2e/install_status_add_uninstall.sh` | 85 | e2e test | e2e scenario: install_status_add_uninstall | manual semantic | reviewed | — |
| `tests/e2e/interactive_install_add_keys_uninstall.sh` | 136 | e2e test | e2e scenario: interactive_install_add_keys_uninstall | manual semantic | reviewed | — |
| `tests/e2e/ipv6_install_add_uninstall.sh` | 107 | e2e test | e2e scenario: ipv6_install_add_uninstall | manual semantic | reviewed | — |
| `tests/e2e/lib.sh` | 147 | e2e test | shared e2e helper library | manual semantic | reviewed | — |
| `tests/e2e/migrate_legacy_transport_to_xhttp.sh` | 130 | e2e test | e2e scenario: migrate_legacy_transport_to_xhttp | manual semantic | reviewed | — |
| `tests/e2e/minimal_install_contract.sh` | 131 | e2e test | e2e scenario: minimal_install_contract | manual semantic | reviewed | — |
| `tests/e2e/minisign_bootstrap_allow_unverified.sh` | 83 | e2e test | e2e scenario: minisign_bootstrap_allow_unverified | manual semantic | reviewed | — |
| `tests/e2e/minisign_fail_cleans_temp.sh` | 129 | e2e test | e2e scenario: minisign_fail_cleans_temp | manual semantic | reviewed | — |
| `tests/e2e/nightly_smoke_install_add_update_uninstall.sh` | 271 | e2e test | e2e scenario: nightly_smoke_install_add_update_uninstall | manual semantic | reviewed | — |
| `tests/e2e/os_matrix_smoke.sh` | 114 | e2e test | e2e scenario: os_matrix_smoke | manual semantic | reviewed | — |
| `tests/lint.sh` | 177 | test helper | full lint entrypoint outside make | manual semantic | reviewed | — |
| `xray-reality.sh` | 509 | runtime entrypoint | bootstrap wrapper and trusted module loader | manual semantic | reviewed | — |

## current audit-level findings referenced by matrix

- `f-003` — core root entrypoints remain large enough to raise maintainability and refactor risk, though `config.sh` and `service.sh` were already reduced by focused module extraction.
