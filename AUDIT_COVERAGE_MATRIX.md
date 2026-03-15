# audit coverage matrix

date: 2026-03-13
repository: `neket371/network-stealth-core`
branch: `ubuntu`
baseline snapshot: `ubuntu` working tree after maturity hardening wave
total repo-tracked files reviewed: **146**

> historical snapshot only: this matrix records coverage for the audited tree on `2026-03-13`. it is not an automatic claim that later commits or local modifications were reviewed.

review depth meanings:
- `manual semantic` — file behavior and contracts were traced manually.
- `contract consistency` — file was reviewed against current runtime/docs/workflow contracts.
- `inventory-only` — file was inventoried and classified, but has no deep runtime semantics.

| file | lines | class | role | review depth | status | notes |
|---|---:|---|---|---|---|---|
| `.dockerignore` | 6 | repo meta | docker build exclusion rules | inventory-only | reviewed | — |
| `.gitattributes` | 8 | repo meta | git attribute rules | inventory-only | reviewed | — |
| `.github/CONTRIBUTING.md` | 136 | doc | english maintainer/contributor doc | contract consistency | reviewed | — |
| `.github/CONTRIBUTING.ru.md` | 136 | doc | russian maintainer/contributor doc | contract consistency | reviewed | — |
| `.github/SECURITY.md` | 152 | doc | english security policy doc | contract consistency | reviewed | — |
| `.github/SECURITY.ru.md` | 152 | doc | russian security policy doc | contract consistency | reviewed | — |
| `.github/workflows/ci.yml` | 296 | workflow | primary ci workflow | contract consistency | reviewed | — |
| `.github/workflows/nightly-smoke.yml` | 111 | workflow | nightly smoke workflow | contract consistency | reviewed | — |
| `.github/workflows/os-matrix-smoke.yml` | 55 | workflow | os support smoke workflow | contract consistency | reviewed | — |
| `.github/workflows/packages.yml` | 91 | workflow | package/build workflow | contract consistency | reviewed | — |
| `.github/workflows/release.yml` | 307 | workflow | tagged release workflow | contract consistency | reviewed | — |
| `.github/workflows/self-hosted-smoke.yml` | 77 | workflow | self-hosted smoke workflow | contract consistency | reviewed | — |
| `.markdownlint.json` | 11 | repo meta | markdown lint policy | inventory-only | reviewed | — |
| `AUDIT_COVERAGE_MATRIX.md` | 165 | doc | audit inventory and review coverage matrix | contract consistency | reviewed | — |
| `AUDIT_FINDINGS_BACKLOG.md` | 39 | doc | prioritized audit backlog | contract consistency | reviewed | — |
| `AUDIT_REPORT_FULL.md` | 219 | doc | full audit narrative and findings | contract consistency | reviewed | — |
| `AUDIT_RUNTIME_MAP.md` | 167 | doc | per-script runtime responsibility map | contract consistency | reviewed | — |
| `config.sh` | 384 | runtime entrypoint | config orchestration over planner, runtime-contract, runtime-apply, and artifact modules | manual semantic | reviewed | now mainly composes focused config modules instead of carrying the heavy runtime/apply surface itself |
| `data/domains/catalog.json` | 4618 | data contract | canonical domain metadata catalog | manual semantic | reviewed | active xhttp planner tiers now read catalog-first; side maps remain fallback/legacy-only |
| `Dockerfile` | 50 | build/tooling | container packaging and smoke runtime image | manual semantic | reviewed | runtime bundle now ships neutral transport endpoint seed file |
| `docs/en/ARCHITECTURE.md` | 162 | doc | english architecture doc | contract consistency | reviewed | — |
| `docs/en/CHANGELOG.md` | 145 | doc | english changelog doc | contract consistency | reviewed | — |
| `docs/en/COMMUNITY.md` | 56 | doc | english community doc | contract consistency | reviewed | — |
| `docs/en/FAQ.md` | 109 | doc | english faq doc | contract consistency | reviewed | — |
| `docs/en/GLOSSARY.md` | 82 | doc | english glossary doc | contract consistency | reviewed | — |
| `docs/en/INDEX.md` | 57 | doc | english index doc | contract consistency | reviewed | — |
| `docs/en/MAINTAINER-LAB.md` | 128 | doc | english maintainer-lab doc | contract consistency | reviewed | — |
| `docs/en/OPERATIONS.md` | 250 | doc | english operations doc | contract consistency | reviewed | — |
| `docs/en/ROADMAP.md` | 35 | doc | english roadmap doc | contract consistency | reviewed | — |
| `docs/en/TROUBLESHOOTING.md` | 126 | doc | english troubleshooting doc | contract consistency | reviewed | — |
| `docs/ru/ARCHITECTURE.md` | 162 | doc | russian architecture doc | contract consistency | reviewed | — |
| `docs/ru/CHANGELOG.md` | 132 | doc | russian changelog doc | contract consistency | reviewed | — |
| `docs/ru/COMMUNITY.md` | 56 | doc | russian community doc | contract consistency | reviewed | — |
| `docs/ru/FAQ.md` | 109 | doc | russian faq doc | contract consistency | reviewed | — |
| `docs/ru/GLOSSARY.md` | 82 | doc | russian glossary doc | contract consistency | reviewed | — |
| `docs/ru/INDEX.md` | 57 | doc | russian index doc | contract consistency | reviewed | — |
| `docs/ru/MAINTAINER-LAB.md` | 128 | doc | russian maintainer-lab doc | contract consistency | reviewed | — |
| `docs/ru/OPERATIONS.md` | 250 | doc | russian operations doc | contract consistency | reviewed | — |
| `docs/ru/ROADMAP.md` | 35 | doc | russian roadmap doc | contract consistency | reviewed | — |
| `docs/ru/TROUBLESHOOTING.md` | 126 | doc | russian troubleshooting doc | contract consistency | reviewed | — |
| `domains.tiers` | 237 | data contract | legacy tier domain fallback source | manual semantic | reviewed | active xhttp planner tiers no longer require this file when catalog metadata is present |
| `export.sh` | 328 | runtime entrypoint | client export entry helpers | manual semantic | reviewed | — |
| `transport_endpoints.map` | 202 | data contract | neutral legacy transport endpoint seed source for grpc/http2 compatibility | manual semantic | reviewed | active xhttp path no longer references grpc-named seed files |
| `health.sh` | 719 | runtime entrypoint | health diagnostics and monitor entry helpers | manual semantic | reviewed | — |
| `install.sh` | 605 | runtime entrypoint | install/update/repair/migrate/rollback entry flows | manual semantic | reviewed | install output/runtime-mode, profile/count selection, and xray/minisign runtime helpers moved into focused modules; runtime log files are precreated with service ownership before first start |
| `lib.sh` | 961 | runtime entrypoint | global runtime orchestrator and action dispatcher | manual semantic | reviewed | materially reduced from the former monolith; now mainly composes focused lib modules |
| `LICENSE` | 21 | repo meta | license text | inventory-only | reviewed | — |
| `Makefile` | 78 | build/tooling | local qa and audit entrypoints | manual semantic | reviewed | — |
| `modules/config/add_clients.sh` | 686 | runtime module | add-clients runtime flow | manual semantic | reviewed | — |
| `modules/config/client_artifacts.sh` | 26 | runtime module | thin loader for focused client format and client state helpers | manual semantic | reviewed | now only sources focused client-artifact submodules |
| `modules/config/client_formats.sh` | 873 | runtime module | client link/json/text rendering, raw-xray client export generation, and key-file output | manual semantic | reviewed | extracted from `modules/config/client_artifacts.sh` to isolate output/rendering concerns |
| `modules/config/client_state.sh` | 434 | runtime module | clients.json normalization, self-check readiness, public-key recovery, and artifact rebuild helpers | manual semantic | reviewed | extracted from `modules/config/client_artifacts.sh` to isolate state/rebuild concerns |
| `modules/config/domain_planner.sh` | 510 | runtime module | domain selection, provider diversity, and plan assembly helpers | manual semantic | reviewed | active xhttp tier planning is now catalog-first; runtime profile helpers were extracted into a focused sibling module |
| `modules/config/runtime_apply.sh` | 188 | runtime module | xray config-test execution, atomic config apply, and environment snapshot persistence | manual semantic | reviewed | extracted from `config.sh` to keep runtime apply and env persistence out of the root orchestrator |
| `modules/config/runtime_contract.sh` | 267 | runtime module | inbound/outbound/routing contract generation, feature gating, mux setup, and vless encryption helpers | manual semantic | reviewed | extracted from `config.sh` to keep xray contract generation and feature checks focused |
| `modules/config/runtime_profiles.sh` | 476 | runtime module | port allocation, xhttp/legacy endpoint payload generation, and key helpers | manual semantic | reviewed | extracted from `modules/config/domain_planner.sh` to keep planner scope narrower |
| `modules/service/runtime.sh` | 480 | runtime module | systemd unit creation, firewall apply, service startup, and runtime update helpers | manual semantic | reviewed | extracted from `service.sh` to narrow service runtime orchestration scope |
| `modules/service/uninstall.sh` | 461 | runtime module | uninstall file removal, account cleanup, and destructive guard helpers | manual semantic | reviewed | extracted from `service.sh` to narrow root entrypoint scope |
| `modules/config/shared_helpers.sh` | 162 | runtime module | transport/tier/helper formatting and compatibility helpers | manual semantic | reviewed | transport compatibility helpers are now transport-neutral where active |
| `modules/export/capabilities.sh` | 141 | runtime module | export capability matrix and compatibility notes helpers | manual semantic | reviewed | — |
| `modules/health/measurements.sh` | 312 | runtime module | measurement import/compare/prune helpers | manual semantic | reviewed | — |
| `modules/health/self_check.sh` | 777 | runtime module | post-action transport-aware self-check engine | manual semantic | reviewed | — |
| `modules/install/bootstrap.sh` | 438 | runtime module | install/update bootstrap staging helpers | manual semantic | reviewed | bootstrap now ships neutral transport endpoint seed file |
| `modules/install/output.sh` | 277 | runtime module | install success summary, runtime-mode notice, and quick-start link rendering | manual semantic | reviewed | extracted from `install.sh` to narrow root entrypoint scope |
| `modules/install/selection.sh` | 234 | runtime module | install profile/count selection and strongest-default auto-selection helpers | manual semantic | reviewed | extracted from `install.sh` to narrow root entrypoint scope |
| `modules/install/xray_runtime.sh` | 523 | runtime module | minisign fallback, xray download, signature verification, and binary install helpers | manual semantic | reviewed | extracted from `install.sh` to narrow root entrypoint scope |
| `modules/lib/cli.sh` | 533 | runtime module | cli parsing and runtime override resolution | manual semantic | reviewed | — |
| `modules/lib/common_utils.sh` | 18 | runtime module | shared low-level helper primitives | manual semantic | reviewed | — |
| `modules/lib/contract_gate.sh` | 91 | runtime module | legacy/pre-v7 mutating gate logic | manual semantic | reviewed | — |
| `modules/lib/domain_sources.sh` | 370 | runtime module | domain/map loading helpers | manual semantic | reviewed | normalizes catalog values and now supports catalog-first active tier loading cleanly on windows line endings too |
| `modules/lib/firewall.sh` | 203 | runtime module | firewall mutation helpers | manual semantic | reviewed | — |
| `modules/lib/globals_contract.sh` | 218 | runtime module | global variable defaults and contracts | manual semantic | reviewed | transport endpoint seed contract now has neutral primary naming |
| `modules/lib/lifecycle.sh` | 216 | runtime module | backup/rollback/cleanup helpers | manual semantic | reviewed | — |
| `modules/lib/policy.sh` | 225 | runtime module | policy.json load/save helpers | manual semantic | reviewed | — |
| `modules/lib/runtime_reuse.sh` | 266 | runtime module | runtime reuse and existing-config extraction | manual semantic | reviewed | — |
| `modules/lib/tty.sh` | 359 | runtime module | interactive tty normalization and yes/no prompts | manual semantic | reviewed | — |
| `modules/lib/usage.sh` | 83 | runtime module | public help text contract | manual semantic | reviewed | — |
| `modules/lib/validation.sh` | 189 | runtime module | input validation helpers | manual semantic | reviewed | — |
| `README.md` | 244 | doc | english user-facing entry doc | contract consistency | reviewed | — |
| `README.ru.md` | 244 | doc | russian user-facing entry doc | contract consistency | reviewed | — |
| `scripts/check-dead-functions.sh` | 163 | qa/release script | dead function guard | manual semantic | reviewed | — |
| `scripts/check-docs-commands.sh` | 92 | qa/release script | docs command contract guard | manual semantic | reviewed | — |
| `scripts/check-release-consistency.sh` | 154 | qa/release script | release/changelog consistency guard | manual semantic | reviewed | — |
| `scripts/check-security-baseline.sh` | 150 | qa/release script | security baseline guard | manual semantic | reviewed | — |
| `scripts/check-shell-complexity.sh` | 135 | qa/release script | shell complexity gate | manual semantic | reviewed | — |
| `scripts/check-shellcheck-advisory.sh` | 36 | qa/release script | advisory shellcheck pass | manual semantic | reviewed | — |
| `scripts/check-workflow-pinning.sh` | 46 | qa/release script | workflow action pinning guard | manual semantic | reviewed | — |
| `scripts/lab/collect-container-artifacts.sh` | 95 | lab script | container lab artifact collector | manual semantic | reviewed | — |
| `scripts/lab/collect-vm-artifacts.sh` | 109 | lab script | vm lab artifact collector | manual semantic | reviewed | — |
| `scripts/lab/common.sh` | 276 | lab script | shared lab helpers and defaults | manual semantic | reviewed | — |
| `scripts/lab/enter-vm-smoke.sh` | 79 | lab script | vm guest entry helper | manual semantic | reviewed | — |
| `scripts/lab/guest-vm-lifecycle.sh` | 202 | lab script | vm guest bootstrap and helper installation | manual semantic | reviewed | — |
| `scripts/lab/prepare-host-safe-smoke.sh` | 46 | lab script | busy-host safe container prep | manual semantic | reviewed | — |
| `scripts/lab/prepare-vm-smoke.sh` | 131 | lab script | vm lab image and state prep | manual semantic | reviewed | — |
| `scripts/lab/run-container-smoke.sh` | 160 | lab script | host-safe container smoke runner | manual semantic | reviewed | — |
| `scripts/lab/run-vm-lifecycle-smoke.sh` | 346 | lab script | full vm lifecycle smoke runner | manual semantic | reviewed | — |
| `scripts/markdownlint.ps1` | 67 | qa/release script | windows markdown lint wrapper | manual semantic | reviewed | — |
| `scripts/measure-stealth.sh` | 519 | qa/release script | field measurement operator tool | manual semantic | reviewed | — |
| `scripts/release-policy-gate.sh` | 98 | qa/release script | release artifact policy gate | manual semantic | reviewed | — |
| `scripts/release.sh` | 253 | qa/release script | release cut helper | manual semantic | reviewed | — |
| `scripts/windows/detect-bash.ps1` | 112 | windows helper | windows bash discovery helper | manual semantic | reviewed | — |
| `scripts/windows/run-validation.ps1` | 164 | windows helper | windows validation orchestrator | manual semantic | reviewed | — |
| `service.sh` | 484 | runtime entrypoint | status/logs/check-update flows plus service runtime module composition | manual semantic | reviewed | service runtime and uninstall behavior now live in focused modules |
| `sni_pools.map` | 202 | data contract | sni pool fallback source | manual semantic | reviewed | active xhttp planner tiers no longer require this file when catalog metadata is present |
| `tests/bats/config_generation.bats` | 106 | bats test | bats suite: config_generation | manual semantic | reviewed | — |
| `tests/bats/domain_loading.bats` | 396 | bats test | bats suite: domain_loading | manual semantic | reviewed | covers catalog-first active tier loading and legacy endpoint-seed fallback behavior |
| `tests/bats/download.bats` | 172 | bats test | bats suite: download | manual semantic | reviewed | — |
| `tests/bats/error_handling.bats` | 213 | bats test | bats suite: error_handling | manual semantic | reviewed | — |
| `tests/bats/health.bats` | 598 | bats test | bats suite: health | manual semantic | reviewed | — |
| `tests/bats/helpers/mocks.bash` | 61 | bats test | shared bats mocks | manual semantic | reviewed | — |
| `tests/bats/input_validation.bats` | 290 | bats test | bats suite: input_validation | manual semantic | reviewed | — |
| `tests/bats/integration.bats` | 1008 | bats test | bats suite: integration | manual semantic | reviewed | — |
| `tests/bats/rollback.bats` | 53 | bats test | bats suite: rollback | manual semantic | reviewed | — |
| `tests/bats/smoke.bats` | 46 | bats test | bats suite: smoke | manual semantic | reviewed | — |
| `tests/bats/transport.bats` | 76 | bats test | bats suite: transport | manual semantic | reviewed | — |
| `tests/bats/unit.bats` | 3895 | bats test | bats suite: unit | manual semantic | reviewed | — |
| `tests/bats/validation.bats` | 636 | bats test | bats suite: validation | manual semantic | reviewed | — |
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
| `tests/e2e/minimal_install_contract.sh` | 137 | e2e test | e2e scenario: minimal_install_contract | manual semantic | reviewed | — |
| `tests/e2e/minisign_bootstrap_allow_unverified.sh` | 83 | e2e test | e2e scenario: minisign_bootstrap_allow_unverified | manual semantic | reviewed | — |
| `tests/e2e/minisign_fail_cleans_temp.sh` | 129 | e2e test | e2e scenario: minisign_fail_cleans_temp | manual semantic | reviewed | — |
| `tests/e2e/nightly_smoke_install_add_update_uninstall.sh` | 411 | e2e test | e2e scenario: nightly_smoke_install_add_update_uninstall | manual semantic | reviewed | — |
| `tests/e2e/os_matrix_smoke.sh` | 114 | e2e test | e2e scenario: os_matrix_smoke | manual semantic | reviewed | — |
| `tests/lint.sh` | 177 | test helper | full lint entrypoint outside make | manual semantic | reviewed | — |
| `xray-reality.sh` | 550 | runtime entrypoint | bootstrap wrapper and trusted module loader | manual semantic | reviewed | — |
| `.github/ISSUE_TEMPLATE/bug_report.yml` | 96 | repo meta | bug-report issue template | contract consistency | reviewed | new public hygiene template for reproducible bug reports |
| `.github/ISSUE_TEMPLATE/config.yml` | 9 | repo meta | issue template chooser config | contract consistency | reviewed | disables blank issues and links users toward discussions/docs |
| `.github/ISSUE_TEMPLATE/feature_request.yml` | 41 | repo meta | feature-request issue template | contract consistency | reviewed | new public hygiene template for scoped proposals |
| `.github/ISSUE_TEMPLATE/support_request.yml` | 63 | repo meta | support-request issue template | contract consistency | reviewed | new public hygiene template for operator/support cases |
| `.github/PULL_REQUEST_TEMPLATE.md` | 20 | doc | pull request template | contract consistency | reviewed | new public hygiene template for contribution quality |
| `modules/lib/downloads.sh` | 221 | runtime module | allowlisted download and mirror helpers | manual semantic | reviewed | extracted from `lib.sh` to narrow bootstrap/download responsibility |
| `modules/lib/config_loading.sh` | 90 | runtime module | env/config loading helpers for `.env` and managed runtime identity defaults | manual semantic | reviewed | extracted from `modules/lib/runtime_inputs.sh` to isolate config loading from strict validation |
| `modules/lib/path_safety.sh` | 255 | runtime module | destructive path guards, safe path validation, and systemd-safe value helpers | manual semantic | reviewed | extracted from `modules/lib/runtime_inputs.sh` to isolate path safety from runtime normalization |
| `modules/lib/runtime_inputs.sh` | 625 | runtime module | runtime normalization, install validation, and strict action-level input checks | manual semantic | reviewed | narrowed after moving config loading and path safety into dedicated lib modules |
| `modules/lib/system_runtime.sh` | 139 | runtime module | systemd/listening/runtime inspection helpers | manual semantic | reviewed | extracted from `lib.sh` to narrow runtime/system helpers |
| `modules/lib/ui_logging.sh` | 591 | runtime module | log rendering, progress, tty-safe output, and logging backend helpers | manual semantic | reviewed | extracted from `lib.sh` to narrow orchestration ui/logging |
| `scripts/lab/generate-vm-proof-pack.sh` | 194 | lab script | sanitized vm proof-pack generator | manual semantic | reviewed | packages vm-lab lifecycle evidence without shipping secrets |

## current audit-level watch items referenced by matrix

- `w-002` — the remaining config-side watch items are focused modules like `modules/config/client_formats.sh`, not the root `config.sh` entrypoint anymore.
