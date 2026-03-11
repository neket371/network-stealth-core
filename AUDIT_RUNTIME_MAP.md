# audit runtime map

date: 2026-03-11
repository: `neket371/network-stealth-core`
branch: `ubuntu`
baseline commit: `c848ef7ca8ed3679d7e2cfe5ac6649ee21ff24f4`

## top-level execution chain

1. `xray-reality.sh` resolves a trusted module root and bootstraps the local/runtime tree.
2. `lib.sh` loads globals, modules, validates runtime inputs, parses cli/env, and dispatches actions.
3. action flows branch into:
   - `install.sh` for `install`, `update`, `repair`, `migrate-stealth`, `rollback`, `diagnose`, `uninstall`
   - `modules/config/add_clients.sh` for `add-clients` / `add-keys`
   - `service.sh` for `status`, `logs`, `check-update`
4. `config.sh`, `service.sh`, `health.sh`, `export.sh`, and `modules/*` implement the shared runtime work.
5. artifacts and state land mainly in `/etc/xray`, `/etc/xray-reality`, `/etc/xray/private/keys`, `/var/lib/xray`, `/var/backups/xray`.

## current verification bundle

- local: `make ci-full` — pass
- local: `bash tests/lint.sh` — pass
- github: `ci`, `packages`, `ubuntu smoke` on `c848ef7` — success
- remote vm-lab lifecycle smoke on `185.218.204.206` — pass
- remote interactive raw install inside vm guest — one minisign prompt only (`prompt_count=1`, `logged_prompts=1`), `self-check=ok`, uninstall cleanup verified
- remote host production `xray` after vm-lab checks — still `active`

## runtime entrypoints

| file | role | main inputs | main outputs / side effects | current verdict |
|---|---|---|---|---|
| `xray-reality.sh` | bootstrap wrapper and trusted loader | env bootstrap refs, repo url, pinning, local script dir | cloned/synced runtime tree, sourced module dir | works; trust boundary is explicit and pinned |
| `lib.sh` | central orchestrator | cli args, env, runtime files, policy/state paths | action dispatch, logging, validation, cleanup, runtime defaults | works; still too large and contract-heavy |
| `install.sh` | mutating lifecycle entrypoint | install/update/repair/migrate/uninstall args, current managed state | xray install/update, config creation, rollback, quick-start output | works; early gate and rollback behavior are good |
| `config.sh` | config and artifact builder | planner outputs, ports, keys, domains, transport settings | `config.json`, `clients.json`, `clients.txt`, links, raw exports | works; still carries legacy-named transport helpers |
| `service.sh` | service/runtime ops | existing managed install and systemd state | `status`, `logs`, `check-update`, uninstall cleanup and systemd handling | works; status output and cleanup are strong |
| `health.sh` | health/diagnostics entry | runtime state, domain health data, timers | health script/timer content, diagnose helpers | works; heavy lifting now mostly delegated to modules |
| `export.sh` | export entry helpers | generated clients/artifacts | export files and capability notes | works; most logic now lives in export module |

## modules — lib layer

| file | role | current verdict |
|---|---|---|
| `modules/lib/cli.sh` | cli parsing, long-option normalization, runtime override resolution | works; current install-first parsing bug is fixed |
| `modules/lib/common_utils.sh` | tiny shared utility wrapper layer | works; minimal surface |
| `modules/lib/contract_gate.sh` | blocks invalid mutating flows on legacy/pre-v7 contracts | works; fresh install and legacy gating now behave correctly |
| `modules/lib/domain_sources.sh` | loads tiers/maps/catalog data | works; contributes to multi-source planner complexity |
| `modules/lib/firewall.sh` | ufw/iptables/nftables mutation helpers | works in tested paths |
| `modules/lib/globals_contract.sh` | default globals and env contract | works; still exposes grpc-named settings in xhttp-first baseline |
| `modules/lib/lifecycle.sh` | backup session, restore, cleanup, runtime reconciliation | works; rollback semantics are a project strength |
| `modules/lib/policy.sh` | managed `policy.json` save/load helpers | works; policy/state separation is explicit |
| `modules/lib/runtime_reuse.sh` | extracts reusable settings from current runtime | works; still needs compatibility awareness |
| `modules/lib/tty.sh` | tty normalization and interactive prompt parsing | works; vm-lab interactive minisign check confirmed single prompt path |
| `modules/lib/usage.sh` | help text and public command contract | works; matches current v7 command surface |
| `modules/lib/validation.sh` | validators for inputs, paths, domains, transports, schedules | works; coverage is strong |

## modules — config/export/health/install layers

| file | role | current verdict |
|---|---|---|
| `modules/config/add_clients.sh` | `add-clients` flow, append + artifact rebuild | works; rebuild-from-config behavior is correct |
| `modules/config/domain_planner.sh` | domain selection, provider diversity, path/service payload generation | works; biggest contract hotspot because xhttp path generation still depends on legacy-named grpc map |
| `modules/config/shared_helpers.sh` | transport/tier labels and compatibility helpers | works; names still reflect mixed grpc/xhttp history |
| `modules/export/capabilities.sh` | capability matrix and compatibility notes generation | works; export honesty is good |
| `modules/health/measurements.sh` | field report import/summary/prune helpers | works; measurement surface is present and coherent |
| `modules/health/self_check.sh` | transport-aware self-check engine and persisted verdicts | works; bounded process cleanup and fallback behavior verified |
| `modules/install/bootstrap.sh` | installed runtime tree sync and wrapper deployment | works; still packages legacy-named data artifacts |

## qa / release / lab scripts

| file/group | role | current verdict |
|---|---|---|
| `scripts/check-*.sh` | guard rails for dead code, docs commands, release consistency, security baseline, complexity, workflow pinning, advisory shellcheck | works; useful and actively wired into qa |
| `scripts/release.sh` + `scripts/release-policy-gate.sh` | release cut and artifact policy validation | works; release flow is mature |
| `scripts/measure-stealth.sh` | operator measurement tool with run/import/compare/summarize/prune | works; audit treats it as public operator surface |
| `scripts/lab/*.sh` | safe container/vm smoke orchestration and artifact collection | works; vm-lab is now the correct full-fidelity isolated test path |
| `scripts/windows/*.ps1` | windows developer validation helpers | works; needed for local validation on windows host |

## workflows and ci surface

| workflow | role | current verdict |
|---|---|---|
| `ci.yml` | main lint/test/release-check/audit path | green on current head |
| `packages.yml` | build/package pipeline | green on current head |
| `release.yml` | tagged release pipeline | not re-run in this audit pass; last known release path stable |
| `nightly-smoke.yml` | deeper smoke schedule | covered by current repo logic, not re-fired manually in this pass |
| `os-matrix-smoke.yml` | supported os smoke path | contract still documented and tested |
| `self-hosted-smoke.yml` | isolated self-hosted smoke path | works, but is not inside `make lint` actionlint list |

## test surface

| suite | role | current verdict |
|---|---|---|
| `tests/bats/*.bats` | unit/integration/validation/health/runtime contract suites | strong coverage: current `bats` total is 418 passing tests inside `make ci-full` |
| `tests/e2e/*.sh` | install/add/update/rollback/migrate contract scenarios | strong coverage for product paths and regressions |
| `tests/lint.sh` | broader standalone lint harness | passes and currently covers all workflows, including self-hosted |

## data and contract files

| file | role | current verdict |
|---|---|---|
| `data/domains/catalog.json` | canonical domain metadata with provider-family awareness | works, but not yet the only planner source |
| `domains.tiers` | tier domain fallback/source list | still active |
| `sni_pools.map` | sni fallback/source list | still active |
| `grpc_services.map` | xhttp payload seed source under legacy grpc naming | active, not dead, but naming is misleading |
| `Makefile` | primary local qa contract | works; workflow lint scope still differs from `tests/lint.sh` |
| `Dockerfile` | packaged smoke/runtime image | works; still ships legacy-named grpc map because runtime expects it |

## docs surface

user-facing docs and bilingual ops docs are broadly aligned with the current v7 contract:

- `readme*`, `docs/en/*`, `docs/ru/*`, `.github/contributing*`, `.github/security*`
- maintainer lab guidance is correctly split out of user-facing readmes
- docs command checker passes

main doc-level caveat from this audit is not contradiction, but that the repo still needs explicit narrative about the remaining multi-source planner contract and legacy naming debt.

## dead code / unnecessary code verdict

current verdict is strict:

- no confirmed dead runtime functions in the current baseline
- `scripts/check-dead-functions.sh` passes
- no obvious orphaned public actions or unreachable e2e flows were found
- the bigger issue is **not dead code**, but **legacy-named active code** and **oversized orchestration files**

that means:

- `grpc_services.map` and grpc-named helper paths are **not dead today**
- they are still active inputs in xhttp-era planning/output
- removing them blindly would be wrong
- but their naming and split-source contract now increase maintenance risk

## audit bottom line

- runtime correctness: **good**
- rollback and safety posture: **good**
- test and smoke coverage: **strong**
- public contract consistency: **good**
- confirmed dead code: **none found in current active path**
- biggest remaining debt:
  1. workflow lint coverage mismatch
  2. multi-source planner/data contract with legacy grpc naming in xhttp-first product
  3. large root entrypoints that still centralize too much behavior
