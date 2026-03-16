# audit runtime map

date: 2026-03-13
repository: `neket371/network-stealth-core`
branch: `ubuntu`
baseline snapshot: `ubuntu` working tree after maturity hardening wave

> historical snapshot only: this runtime map describes the audited tree on `2026-03-13`. workflow and runtime verification notes below are not live guarantees for later commits or uncommitted changes. later fixes such as node24-ready workflow pins and expanded export coverage are intentionally outside this archived snapshot.

## top-level execution chain

1. `xray-reality.sh` resolves a trusted module root, prints bootstrap pin warnings when mutating actions are run from a floating ref, and bootstraps the local/runtime tree.
2. `lib.sh` now acts mainly as a dispatcher/orchestration shell:
   - source global contracts and focused lib modules
   - validate runtime inputs
   - parse cli/env
   - dispatch actions
3. action flows branch into:
   - `install.sh` for `install`, `update`, `repair`, `migrate-stealth`, `rollback`, `diagnose`, `uninstall`
   - `modules/config/add_clients.sh` for `add-clients` / `add-keys`
   - `service.sh` for `status`, `logs`, `check-update`
4. `config.sh`, `service.sh`, `health.sh`, `export.sh`, and `modules/*` implement the shared runtime work.
5. artifacts and state land mainly in `/etc/xray`, `/etc/xray-reality`, `/etc/xray/private/keys`, `/var/lib/xray`, `/var/backups/xray`.

## verification bundle for audited snapshot

- local: `make ci-full` — pass
- local: `bash tests/lint.sh` — pass
- local: `pwsh scripts/windows/run-validation.ps1 -SkipRemote` — pass
- github: latest green `ci`, `packages`, and `ubuntu smoke` runs for the audited tree on `ubuntu` — success
- remote vm-lab lifecycle smoke on `185.218.204.206` — pass
- remote interactive raw install inside vm guest — one minisign prompt only (`prompt_count=1`, `logged_prompts=1`), `self-check=ok`, uninstall cleanup verified
- remote host production `xray` after vm-lab checks — still `active`
- vm proof-pack generation now exists as a sanitized artifact flow on top of vm-lab evidence

## runtime entrypoints

| file | role | main inputs | main outputs / side effects | current verdict |
|---|---|---|---|---|
| `xray-reality.sh` | bootstrap wrapper and trusted loader | env bootstrap refs, repo url, pinning, local script dir | cloned/synced runtime tree, sourced module dir | works; trust boundary is explicit, and mutating floating bootstrap now warns harder |
| `lib.sh` | central orchestrator | cli args, env, runtime files, policy/state paths | action dispatch, module sourcing, validation, runtime defaults | works; now materially narrower after focused module extraction |
| `install.sh` | mutating lifecycle entrypoint | install/update/repair/migrate/uninstall args, current managed state | xray install/update, config creation, rollback, and composition over focused output/selection/xray-runtime helpers | works; now mostly orchestration |
| `config.sh` | config orchestration entrypoint | planner outputs, ports, keys, domains, transport settings | `config.json`, environment snapshot, and composition over focused config modules | works; now mainly orchestrates planner, runtime-contract, runtime-apply, and artifact modules |
| `service.sh` | service/runtime ops | existing managed install and systemd state | `status`, `logs`, `check-update`, and service-level orchestration over focused modules | works; now mainly composes focused runtime and uninstall modules |
| `health.sh` | health/diagnostics entry | runtime state, domain health data, timers | health script/timer content, diagnose helpers | works; heavy lifting is mostly delegated to modules |
| `export.sh` | export entry helpers | generated clients/artifacts | export files and capability notes | works; most logic now lives in export module |

## modules — lib layer

| file | role | current verdict |
|---|---|---|
| `modules/lib/cli.sh` | cli parsing, long-option normalization, runtime override resolution | works |
| `modules/lib/common_utils.sh` | tiny shared utility wrapper layer | works; minimal surface |
| `modules/lib/contract_gate.sh` | blocks invalid mutating flows on legacy/pre-v7 contracts | works; fresh install and legacy gating behave correctly |
| `modules/lib/domain_sources.sh` | loads tiers/maps/catalog data | works; active xhttp tier planning is now catalog-first and the remaining side maps are fallback/compatibility inputs |
| `modules/lib/downloads.sh` | allowlisted download, mirror, and https validation helpers | works; extracted from `lib.sh` and now carries the download trust contract clearly |
| `modules/lib/config_loading.sh` | env/config loading helpers for `.env` and policy-adjacent runtime defaults | works; isolates config loading from broader runtime normalization |
| `modules/lib/firewall.sh` | ufw/iptables/nftables mutation helpers | works in tested paths |
| `modules/lib/globals_contract.sh` | default globals and env contract | works; neutral transport-endpoint contract is primary, grpc alias is compatibility-only |
| `modules/lib/lifecycle.sh` | backup session, restore, cleanup, runtime reconciliation | works; rollback semantics are a project strength |
| `modules/lib/policy.sh` | managed `policy.json` save/load helpers | works; policy/state separation is explicit |
| `modules/lib/path_safety.sh` | path guards, destructive-scope checks, and systemd-safe path/value helpers | works; isolates destructive/runtime path safety from broader normalization |
| `modules/lib/runtime_inputs.sh` | runtime normalization, install validation, and strict action-level input checks | works; noticeably narrower after config-loading and path-safety extraction |
| `modules/lib/runtime_reuse.sh` | extracts reusable settings from current runtime | works; compatibility-aware and covered |
| `modules/lib/system_runtime.sh` | systemd/listening/runtime inspection helpers | works; narrowed out of `lib.sh` |
| `modules/lib/tty.sh` | tty normalization and interactive prompt parsing | works; vm-lab interactive minisign check confirmed single prompt path |
| `modules/lib/ui_logging.sh` | log rendering, progress, tty-safe output, and file-backed logging helpers | works; narrowed out of `lib.sh` |
| `modules/lib/usage.sh` | help text and public command contract | works; matches current v7 command surface |
| `modules/lib/validation.sh` | validators for inputs, paths, domains, transports, schedules | works; coverage is strong |

## modules — config/export/health/install/service layers

| file | role | current verdict |
|---|---|---|
| `modules/config/add_clients.sh` | `add-clients` flow, append + artifact rebuild | works; rebuild-from-config behavior is correct |
| `modules/config/client_artifacts.sh` | thin client-artifact loader | works; keeps `config.sh` stable while focused artifact modules evolve underneath |
| `modules/config/client_formats.sh` | client link/json/text rendering, raw-xray client export generation, and key-file output | works; isolates rendering/export concerns from rebuild/state behavior |
| `modules/config/client_state.sh` | clients.json normalization, self-check readiness, public-key recovery, and artifact rebuild helpers | works; isolates artifact-state and rebuild semantics from rendering code |
| `modules/config/domain_planner.sh` | domain selection, provider diversity, and plan assembly | works; active xhttp tiers are catalog-first and the planner no longer carries port/key/runtime-profile helpers |
| `modules/config/runtime_apply.sh` | xray `-test` execution, atomic config apply, and environment snapshot persistence | works; meaningfully narrows `config.sh` and centralizes config-apply semantics |
| `modules/config/runtime_contract.sh` | xray config contract generation, feature gates, mux setup, and vless encryption helpers | works; keeps contract generation and feature checks out of the root entrypoint |
| `modules/config/runtime_profiles.sh` | port allocation, path/service payload generation, and key helpers | works; focused extraction narrowed planner breadth without changing config/add-clients behavior |
| `modules/config/shared_helpers.sh` | transport/tier labels and compatibility helpers | works; active helpers are transport-neutral, legacy labels remain scoped to grpc/http2 branches |
| `modules/export/capabilities.sh` | capability matrix and compatibility notes generation | works; export honesty is good |
| `modules/health/measurements.sh` | field report import/summary/prune helpers | works; measurement surface is present and coherent |
| `modules/health/self_check.sh` | transport-aware self-check engine and persisted verdicts | works; bounded process cleanup and fallback behavior verified |
| `modules/install/bootstrap.sh` | installed runtime tree sync and wrapper deployment | works; packages neutral transport endpoint seeds for legacy transport compatibility |
| `modules/install/output.sh` | install success summary, runtime-mode notice, and quick-start link rendering | works; meaningfully narrows `install.sh` while preserving install ux |
| `modules/install/selection.sh` | profile selection, count prompts, and manual override helpers | works; interactive install now asks for explicit count unless the count was already supplied |
| `modules/install/xray_runtime.sh` | minisign fallback, xray archive download, and verified binary install helpers | works; isolates noisy install bootstrap logic from `install.sh` |
| `modules/service/runtime.sh` | systemd unit creation, firewall apply, service startup, and runtime update helpers | works; meaningfully narrows `service.sh` while keeping service/runtime behavior cohesive |
| `modules/service/uninstall.sh` | uninstall file removal, destructive path guards, account cleanup, and service teardown helpers | works; meaningfully narrows `service.sh` while preserving uninstall semantics |

## qa / release / lab scripts

| file/group | role | current verdict |
|---|---|---|
| `scripts/check-*.sh` | guard rails for dead code, docs commands, release consistency, security baseline, complexity, workflow pinning, advisory shellcheck | works; useful and actively wired into qa |
| `scripts/release.sh` + `scripts/release-policy-gate.sh` | release cut and artifact policy validation | works; release flow is mature |
| `scripts/measure-stealth.sh` | operator measurement tool with run/import/compare/summarize/prune | works; audit treats it as public operator surface |
| `scripts/lab/*.sh` | safe container/vm smoke orchestration, proof-pack generation, and artifact collection | works; vm-lab is now the correct full-fidelity isolated test path and proof source |
| `scripts/windows/*.ps1` | windows developer validation helpers | works; needed for local validation on windows host |

## workflows and ci surface

| workflow | role | audited verdict |
|---|---|---|
| `ci.yml` | main lint/test/release-check/audit path | green on the audited tree |
| `packages.yml` | build/package pipeline | green on the audited tree |
| `release.yml` | tagged release pipeline | stable for the audited tree |
| `nightly-smoke.yml` | deeper smoke schedule | now capable of generating and uploading vm proof-pack artifacts |
| `os-matrix-smoke.yml` | supported os smoke path | contract is still documented and tested |
| `self-hosted-smoke.yml` | isolated self-hosted smoke path | works; can now generate and upload vm proof-pack artifacts when `/dev/kvm` is present |

## test surface

| suite | role | audited verdict |
|---|---|---|
| `tests/bats/*.bats` | unit/integration/validation/health/runtime contract suites | strong coverage: audited `bats` total was 442 passing tests inside `make ci-full` |
| `tests/e2e/*.sh` | install/add/update/rollback/migrate contract scenarios | strong coverage for product paths and regressions |
| `tests/lint.sh` | broader standalone lint harness | passes and currently covers all workflows, including self-hosted |

## data and contract files

| file | role | current verdict |
|---|---|---|
| `data/domains/catalog.json` | canonical domain metadata with provider-family awareness | works; active xhttp tier planning is now catalog-first |
| `domains.tiers` | tier domain fallback/source list | fallback/compatibility only when canonical catalog metadata is unavailable |
| `sni_pools.map` | sni fallback/source list | fallback/compatibility only when canonical catalog metadata is unavailable |
| `transport_endpoints.map` | neutral legacy transport endpoint seed source for grpc/http2 compatibility | legacy-only, no longer part of active xhttp naming |
| `Makefile` | primary local qa contract | works; workflow lint scope is aligned with `tests/lint.sh`, and vm proof-pack is now a first-class target |
| `Dockerfile` | packaged smoke/runtime image | works; ships neutral transport endpoint seeds, not grpc-named planner inputs |

## docs surface

user-facing docs and bilingual ops docs are broadly aligned with the current v7 contract:

- `readme*`, `docs/en/*`, `docs/ru/*`, `.github/contributing*`, `.github/security*`
- pinned bootstrap by commit is now visually first-class for real-server quick start
- maintainer lab guidance is correctly split out of user-facing readmes
- docs command checker passes
- public issue/pr intake templates exist and are linked from community/contributing docs

## dead code / unnecessary code verdict

current verdict is strict:

- no confirmed dead runtime functions in the current baseline
- `scripts/check-dead-functions.sh` passes
- no obvious orphaned public actions or unreachable e2e flows were found
- the bigger issue is no longer root-script sprawl, but a few still-broad focused modules and the intentionally narrow platform scope

that means:

- legacy transport endpoint seeds are **not dead today**
- they still matter for grpc/http2 compatibility and migration helpers
- but they are no longer the active xhttp naming contract
- the remaining structural watch item is not planner source order anymore; it is the breadth of a few focused modules

## audit bottom line

- runtime correctness: **good**
- rollback and safety posture: **good**
- test and smoke coverage: **strong**
- public contract consistency: **good**
- confirmed dead code: **none found in the audited active path**
- biggest remaining watch items:
  1. broad-but-contained focused modules such as `modules/config/client_formats.sh`
  2. intentionally narrow support matrix centered on ubuntu 24.04
