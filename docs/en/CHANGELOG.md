# changelog

all notable changes in **network stealth core** are documented here.

format: [keep a changelog](https://keepachangelog.com/en/1.0.0/)  
versioning: [semantic versioning](https://semver.org/spec/v2.0.0.html)

## [unreleased]

## [7.10.7] - 2026-03-29

### Fixed
- made direct trusted `XRAY_DATA_DIR` env overrides win over a stale local bootstrap tree too, not only the persisted `config.env` override path
- tightened wrapper/bootstrap loading around one coherent trusted source tree and stopped the root/lib fallback chain from silently mixing files from different trees once strict wrapper loading is active
- made `install_self()` copy the canonical wrapper from the selected managed tree instead of re-installing the originally launched stale wrapper path
- extended trusted custom-tree validation to runtime `.jq` assets such as `modules/health/measurements_aggregate.jq`, so escaped or unsafe non-shell runtime files fail before operator decision code can load them

## [7.10.6] - 2026-03-28

### Fixed
- made the wrapper resolve one coherent trusted source tree before sourcing `lib.sh` and the root entrypoints, so stale local `lib.sh` copies can no longer mix with modules coming from another trusted tree
- persisted `XRAY_DATA_DIR` and `XRAY_ALLOW_CUSTOM_DATA_DIR` through the normal `config.env` round-trip and taught the bootstrap wrapper to load them early and prefer that trusted managed tree over a stale local bootstrap tree on the next run
- split managed measurement-state publishing from explicit `scripts/measure-stealth.sh --output` publishing, so ad-hoc output files no longer get forced into the internal `root:xray` ownership contract or the managed `0640` mode

### Changed
- clarified docs to describe `XRAY_DATA_DIR` as a mirror of the runnable managed source set instead of claiming it is a byte-for-byte mirror of the whole repository checkout

## [7.10.5] - 2026-03-28

### Changed
- re-ships the managed wrapper-tree rollback and rotation-state hardening tranche on the actual code commit after the `v7.10.4` release-prep-only tag slipped out

## [7.10.4] - 2026-03-28

### Changed
- made managed wrapper self-sync mirror the full source-tree root set including `xray-reality.sh`, so `$XRAY_DATA_DIR` stays a real runnable mirror instead of a partial module dump

### Fixed
- folded `XRAY_DATA_DIR` self-sync into the normal rollback snapshot flow, so failed `install`, `update`, or `repair` no longer leave a new managed code tree on top of rolled-back runtime state
- hardened staged wrapper-tree publish so a failed restore move no longer deletes the only old tree blindly; the previous tree now survives until rollback recovery can finish
- exposed an invalid saved `rotation-state.json` as explicit degraded operator state instead of silently resetting cooldown and weak-primary history to defaults

## [7.10.3] - 2026-03-28

### Fixed
- stopped measurement and self-check storage helpers from chmodding pre-existing custom parent directories, so custom state-file overrides no longer risk permission drift on shared system paths
- made the managed geo registry follow only the active GeoIP/GeoSite directory contract instead of always treating `/usr/local/share/xray` as project-owned
- persisted custom GeoIP/GeoSite asset URLs and checksum URLs through both `config.env` and policy round-trips, so saved runtime state no longer silently falls back to default origins
- made wrapper completeness validation track the current health runtime modules and `measurements_aggregate.jq`, so incomplete custom or pinned trees fail before later runtime sourcing

## [7.10.2] - 2026-03-27

### Fixed
- moved the new release/runtime contract bats guards into `tests/bats/release_contracts.bats`, so `tests/bats/unit.bats` stays below the stage-3 complexity budget and hosted `CI` is green again on the `v7.10.x` line

## [7.10.1] - 2026-03-27

### Changed
- made wrapper self-sync publish `XRAY_DATA_DIR` as a clean managed mirror, so stale files removed from the source tree no longer survive inside the managed wrapper tree after later updates
- moved GeoIP/GeoSite refresh onto the normal `update` runtime path and reduced the generated auto-update script to a thin wrapper that just executes `xray-reality.sh update --non-interactive`
- exposed invalid saved measurement summaries as an explicit degraded operator state instead of flattening them into a generic `unknown` fallback

### Fixed
- enforced `DOWNLOAD_HOST_ALLOWLIST` for custom GeoIP/GeoSite asset URLs and checksum URLs, so the geo-refresh path no longer trusts arbitrary `https` origins with self-consistent checksums
- completed the runtime contract for `MEASUREMENTS_ROTATION_STATE_FILE` across config loading, policy loading, path validation, destructive guards, and `config.env` persistence
- switched measurement summary/report persistence and `measure-stealth.sh --output` writes to atomic publish, so truncated JSON no longer silently degrades the decision layer

## [7.10.0] - 2026-03-27

### Changed
- added a persisted rotation-state contract under `/var/lib/xray/measurements/rotation-state.json`, so weak-primary streaks, cooldown families/domains, and the last promotion context survive across `repair` and `update --replan`
- unified `doctor`, `status --verbose`, `diagnose`, `repair`, `update --replan`, and `scripts/measure-stealth.sh summarize` on one operator decision layer with the same verdict names, rotation state, cooldown reasons, and next-action semantics
- made `repair` and `update --replan` share one cooldown-aware promotion engine instead of separate spare-promotion branches

### Fixed
- derived the measurement rotation-state path from the active summary/storage path when measurements are redirected, so nested report imports and isolated test runs no longer leak permission noise from `/var/lib/xray/measurements`
- fixed the measurement summary overlay path to keep JSON payloads intact instead of appending a stray `}` through an unsafe shell default expansion

## [7.9.1] - 2026-03-27

### Changed
- re-ships the operator-focused `doctor` and planner anti-correlation tranche on the actual code commit after the `v7.9.0` release-prep-only tag slipped out
- added a read-only `doctor` command that condenses runtime state, the latest self-check, the saved field recommendation, and the next operator action into one screen
- made spare ordering lean away from the current primary provider family when saved field summaries already recommend rotation, so `build_domain_plan` keeps broader family separation after the primary slot
- moved normal/legacy transport normalization into the shared legacy transport contract instead of keeping scattered `grpc/http2/h2` case handling in hot-path modules

## [7.9.0] - 2026-03-27

### Changed
- added a read-only `doctor` command that condenses runtime state, the latest self-check, the saved field recommendation, and the next operator action into one screen
- made spare ordering lean away from the current primary provider family when saved field summaries already recommend rotation, so `build_domain_plan` keeps broader family separation after the primary slot
- moved normal/legacy transport normalization into the shared legacy transport contract instead of keeping scattered `grpc/http2/h2` case handling in hot-path modules

## [7.8.1] - 2026-03-26

### Changed
- fix: split measurement aggregate jq program (bfdbad3)

## [7.8.0] - 2026-03-26

### Changed
- taught `scripts/measure-stealth.sh import` to walk nested report trees, ignore non-report JSON files, and deduplicate already imported reports by content hash instead of failing a whole remote-canary batch on one stray manifest or copied file
- expanded the operator-facing field summary with provider-family diversity, long-term trend review, provider-family penalties, and richer current-primary / best-spare details reused by `summarize`, `status --verbose`, `diagnose`, `repair`, and `update --replan`
- made domain planning bias toward lower-penalty provider families from saved field summaries while still preserving strongest-direct diversity and priority invariants

### Fixed
- saved measurement reports now persist config-level `domain`, `provider_family`, and `primary_rank` metadata, so imported field data can drive family-aware summaries and planner decisions without relying on ambient runtime state

## [7.7.0] - 2026-03-26

### Changed
- turned saved field measurements into a decision-grade operator summary with coverage quality, recommendation reason, current primary stats, best spare stats, and richer promotion metadata reused by `status --verbose`, `diagnose`, `repair`, `update --replan`, and `scripts/measure-stealth.sh summarize`

### Fixed
- made field summaries report `unknown` instead of an implied degraded verdict when no reports are saved yet, and kept the recommendation fail-soft as `collect-more-data`

## [7.6.3] - 2026-03-26

### Fixed
- loosened two uninstall bats assertions from exact stdout matching to success-marker matching, so hosted linux runners no longer fail on incidental control characters or extra wrapper output while still verifying the intended uninstall behavior

## [7.6.2] - 2026-03-26

### Fixed
- relaxed two uninstall bats guards to assert the final success marker instead of exact full stdout equality, so hosted linux runners no longer fail the suite on incidental extra output while the uninstall behavior itself remains unchanged

## [7.6.1] - 2026-03-25

### Fixed
- made the release-surface security-doc test derive supported and unsupported version lines from `SCRIPT_VERSION`, so release and CI checks no longer pin a stale previous minor after a new release cut

## [7.6.0] - 2026-03-25

### Changed
- introduced a shared managed-artifact registry and exact-scope destructive path contract so install, update, repair, rollback, and uninstall now reason about the same managed files, directories, logs, and unit artifacts instead of parallel cleanup lists
- switched `install_self` source-tree publishing to a staged whole-tree commit model, so the managed wrapper tree under `XRAY_DATA_DIR` is no longer exposed to mixed old/new root files during self-sync interruptions

### Fixed
- narrowed destructive path validation to real project segments while still allowing canonical managed system paths and safe mirrored non-system paths used by disposable labs and custom nested test trees
- made uninstall residue detection include managed logs and auxiliary artifacts, so `uninstall` no longer exits early with `already removed` while managed residue still exists

## [7.5.18] - 2026-03-25

### Fixed
- made `scripts/lab/prepare-vm-smoke.sh` publish the ubuntu cloud image only after a verified non-empty `.part` download, with stale temp cleanup on failure instead of a brittle `mv` step
- fixed `scripts/lab/guest-vm-release-smoke.sh` to validate the persisted quoted `XRAY_DOMAINS_FILE="..."` contract instead of falsely failing on a correct managed `config.env`

## [7.5.17] - 2026-03-24

### Changed
- moved legacy grpc/mux compatibility defaults into a dedicated shared contract module instead of keeping that surface duplicated across the main globals layer
- made `data/domains/catalog.json` the enforced canon for committed `domains.tiers` and `sni_pools.map` fallbacks via a checked generator path

### Fixed
- switched config and add-clients runtime-profile generation away from hidden `PROFILE_*` global side effects to explicit output values
- split contract-level bats coverage out of `tests/bats/unit.bats`, wired the new generator/module into smoke coverage, and added regression checks for generated domain fallbacks
- cleaned up duplicated busy-host faq entries, softened maintainer check wording, and polished ru maintainer/docs phrasing without changing the product contract
- hardened wrapper trust checks for `XRAY_ALLOW_CUSTOM_DATA_DIR=true` so sourced shell files and symlink targets must stay inside the trusted tree with safe permissions, and made client-artifact rollback fail closed on invalid publish-manifest states

## [7.5.16] - 2026-03-22

### Fixed
- aligned the download-failure e2e smoke with the hardened installer path so release jobs now expect the official `.dgst` fail-closed message instead of the older mirror-only SHA256 wording

## [7.5.15] - 2026-03-22

### Changed
- moved the managed version contract defaults into one shared helper and documented `XRAY_FAILURE_PROOF_DIR` as a maintainer-only debug hook instead of leaving it as an implicit environment knob

### Fixed
- removed duplicate server-side `settings.flow` from generated inbound JSON and stopped writing non-standard `version.min` into the server root config
- made `systemctl_uninstall_bounded` forward every requested unit instead of silently dropping trailing arguments during uninstall cleanup
- deduplicated the `googleapis.com` SNI pool and added a domain-data consistency gate for catalog, tiers, and fallback map files
- switched rebuild/self-check helpers away from hidden multi-output coupling, and reduced repeated `jq` work in client artifact rendering/inventory assembly
- tightened Xray release verification so official digest/signature sidecars are preferred by default, with mirror digest fallback only in the explicit insecure path

## [7.5.14] - 2026-03-22

### Changed
- release-prep tag only; the actual validated code changes were shipped in `7.5.15`

### Fixed
- release metadata was updated, but the validated code-pass was not included in this tag

## [7.5.13] - 2026-03-21

### Changed
- documented the strongest-direct DNS contract as intentionally IPv4-first on dual-stack hosts, instead of leaving `queryStrategy: UseIPv4` to look like an accidental mismatch

### Fixed
- strengthened the container `HEALTHCHECK` so it verifies wrapper bootability instead of only checking that the main files exist

## [7.5.12] - 2026-03-21

### Changed
- moved service/atomic-write guard tests out of `tests/bats/unit.bats` into themed bats coverage so the stage-3 complexity gate stays honest without relaxing its file-size limit

## [7.5.11] - 2026-03-21

### Fixed
- made `check-update` degrade with an explicit warning instead of crashing if the version comparator helper is unavailable in a degraded service-shell context
- narrowed `atomic_write` `/usr/local` permissions to managed subpaths so unrelated `/usr/local/*` targets are no longer implicitly writable

## [7.5.10] - 2026-03-21

### Fixed
- shipped the queued export, transactional client-artifact publishing, CLI parser, and local QA hardening changes in a follow-up patch release so the tagged tree now matches the validated fix-pass

## [7.5.9] - 2026-03-21

### Fixed
- created export parents before `mktemp` in canary and capability export paths, so first-run exports no longer fail on missing output directories
- made client artifact publishing transactional by staging `clients.json`, text exports, and `raw-xray` outputs before atomically publishing them into place
- rejected missing long-option values in the CLI parser instead of silently consuming the next flag as an argument
- added mandatory local quality gates for `tests/bats/*.bats` and PowerShell syntax, and extended shell complexity coverage to `.bats` and `.ps1`
- optimized `check-dead-functions.sh` to use a shared candidate scan instead of repeatedly rescanning the full repository for each function
- deduplicated the transport endpoint file contract helper and split large CLI/test hotspots into smaller phase helpers and themed bats files

## [7.5.8] - 2026-03-20

### Fixed
- made export template helpers clean temporary files on `jq` or validation failures instead of leaving orphaned `.tmp.*` artifacts behind
- made `repair` fail closed when client-artifact rebuild or self-check artifact preparation degrades, instead of ending with a misleading successful recovery
- clarified strict bootstrap pin diagnostics so failed auto-pin resolution now explains the `XRAY_REPO_COMMIT` fallback and likely `git ls-remote` / network cause
- skipped empty optional runtime arrays during primary promotion so `PORTS_V6=()` no longer aborts a valid reorder
- batched inbound JSON assembly in config build/rebuild paths instead of repeatedly re-parsing the whole array with per-item `jq` appends

## [7.5.7] - 2026-03-20

### Fixed
- made generated `xray-health.sh` survive fail-count lock timeouts with explicit warnings instead of aborting under `set -e`
- made `diagnose` collect output in a subshell so temporary `set +e` no longer leaks into the caller shell state
- made `status --verbose` fall back to raw transport labels if shared helper functions are unavailable
- rejected explicit legacy `TRANSPORT` overrides on normal v7 actions earlier in runtime override handling while still allowing `migrate-stealth`
- allowed read-only and cleanup actions to keep the persisted legacy `TRANSPORT` value on managed pre-migration installs instead of aborting before `migrate-stealth`
- switched generated domain-health updates to `printf '%s\n'` pipes so JSON state is passed to `jq` consistently instead of relying on shell `echo`
- reduced the `xray-health.service` oneshot start timeout to `90s` so a stuck health pass fails promptly instead of waiting `30min`
- removed the 10-position nameref normalization helper from health monitoring setup and replaced it with explicit typed normalizers
- clarified grpc/mux defaults as legacy compatibility knobs for `migrate-stealth` and explicit legacy rebuild paths
- bounded `rand_between` retry sampling and added a deterministic fallback path instead of leaving an unbounded rejection loop
- hardened `atomic_write` to restore `umask` when temporary file creation fails and made install warn explicitly when export hooks are unavailable after load
- made rollback log the exact restore target before aborting on snapshot copy failures instead of failing silently inside the restore loop
- made `status` warn explicitly when it sees an unrecognized inbound transport instead of showing `unknown` with no operator hint
- added an `atomic_write` guard for accidental interactive calls without a pipe or heredoc
- made explicit rollback replay symlink artifacts from backup sessions instead of restoring only regular files
- made generated `xray-health.sh` normalize corrupted fail-count values to `0` with a warning instead of aborting before restart logic
- made release consistency checks reject stale `TODO: summarize release changes` placeholders in released ru changelog sections too

## [7.5.6] - 2026-03-19

### Fixed
- made canary bundle export fail closed with explicit errors when source manifest generation breaks or raw-xray filenames collide
- added a wrapper warning when `SCRIPT_DIR` cannot be resolved and the bootstrap path may be used instead of local sources
- normalized the update-version regex to keep `-` and `.` explicitly literal in prerelease suffix checks
- fixed linux `emergency` browser-dialer guidance so docs and canary helpers now use shell-safe `env 'xray.browser.dialer=...'` instead of invalid `export`
- aligned `SECURITY.md` and `SECURITY.ru.md` with the current supported `7.5.x` release line and added release checks for that surface
- unified the canonical `SELF_CHECK_URLS` default across shared runtime modules

## [7.5.5] - 2026-03-18

### Changed
- preserved explicit domain-data file overrides during path resolution while still rebinding managed defaults to the resolved data directory
- unified the shared root `config.json` writer used by both full build and rebuild flows to keep runtime policy and logging structure in sync

### Fixed
- tightened atomic write path validation to reject real traversal segments before canonicalization while keeping safe-prefix enforcement intact
- stopped generating gRPC-only timeout randomness for `xhttp` rebuild paths
- hardened domain probing so health ranking prefers real TLS validation over a loose `CONNECTED` match and removed the unconditional connectivity startup sleep
- widened the shell fallback entropy path used when strong random sources are unavailable

## [7.5.4] - 2026-03-18

### Fixed
- fixed release automation so tagged changelog sections now consume `[unreleased]` notes cleanly instead of duplicating sections or leaving stale bullets behind
- cleaned the `7.5.3` changelog layout and restored markdownlint-clean release docs after the previous release-script bug

## [7.5.3] - 2026-03-18

### Changed
- persisted source metadata (`kind`, `ref`, `commit`) into managed state and surfaced it in `status --verbose` and `diagnose`
- made `Nightly Smoke` self-hosted the explicit regular evidence path while leaving the standalone self-hosted workflow manual/on-demand only
- documented field validation as a separate real-network proof layer instead of treating runtime-green smoke as anti-dpi proof
- split several high-risk orchestration functions into phase helpers to reduce silent regression pressure without changing the public CLI

### Fixed
- suppressed the false uninstall `reset-failed` warning when no `xray*` units remain after cleanup
- hardened host cleanup, rollback residue handling, and xray-health log fallback paths around real-host lifecycle validation

## [7.5.2] - 2026-03-17

### Changed
- removed archived auxiliary docs from the public repository and aligned internal quality-check naming with the maintainer-facing workflow

## [7.5.1] - 2026-03-17

### Changed

- expanded release validation around nightly smoke and rollback paths so the published branch state matches the full server-validated lifecycle baseline

### Fixed

- fixed the `xray-health.service` failure path so the health timer no longer exits early under `set -e` during fail-count handling
- hardened rollback restore flow by quiescing related systemd units and restoring runtime-critical files atomically, avoiding `Text file busy` failures on `/usr/local/bin/xray`
- made `nightly_smoke_install_add_update_uninstall.sh` idempotent by using a unique temporary status file for each run

## [7.5.0] - 2026-03-16

### changed

- persisted managed custom domain sources into `/etc/xray-reality/custom-domains.txt` so custom installs remain manageable across `add-clients`, `add-keys`, and later lifecycle actions
- added a deterministic vm-lab tagged release validation path via `nsc-vm-install-release` and `make vm-lab-release-smoke`

### fixed

- fail-closed custom-profile validation now reports missing managed custom-domain state early instead of failing later with an empty domain list
- release-facing docs and consistency checks now enforce an explicit tag-pinned bootstrap path and generic issue-template placeholders

## [7.3.8] - 2026-03-16

### changed

- split config, install, service, and client-artifact orchestration into focused modules (`runtime_contract`, `runtime_apply`, `runtime_profiles`, `client_formats`, `client_state`, install output/selection/runtime, and service runtime/uninstall helpers)
- made the active xhttp planner catalog-first while keeping bootstrap compatibility with historical pinned tags used by `migrate-stealth`
- promoted pinned bootstrap, vm-lab proof-pack generation, and host-safe lab workflows as the maintainer-grade validation path
- refreshed issue templates, support metadata, and bilingual docs to the current `v7` strongest-direct release line

### fixed

- hardened xray log lifecycle behavior on `ubuntu-24.04`, including service startup, restart, and `logrotate` handling on hosted runners
- stabilized legacy migration fixtures and lifecycle validation for clean hosted `ubuntu-24.04` environments
- expanded quality/lint coverage to `modules/export/*` and added direct unit contracts for export capability notes and `rebuild_config_for_transport()`
- refreshed pinned docker actions to node24-ready revisions and removed the previous node 20 deprecation noise from hosted package builds

## [7.1.0] - 2026-03-07

### changed

- made the strongest-direct contract the managed baseline: `vless + reality + xhttp + vless encryption + xtls-rprx-vision`
- introduced `/etc/xray-reality/policy.json` as the managed policy source of truth
- promoted `clients.json` to schema v3 with provider metadata, direct-flow fields, and three variants per config
- added the `emergency` field-only variant (`xhttp stream-up + browser dialer`) while keeping `recommended` and `rescue` as the server-validated direct path
- added `data/domains/catalog.json` and planner/provider-family awareness for more diverse config sets
- expanded `scripts/measure-stealth.sh` into `run`, `compare`, and `summarize` workflows and persisted measurement summaries
- added `export/canary/` for portable field testing and promoted `export/capabilities.json` to schema v2
- taught `repair` and `update --replan` to use self-check and field observations when promoting a stronger spare config
- expanded `migrate-stealth` to upgrade both legacy transports and pre-v7 xhttp installs
- refreshed bilingual docs, release metadata, and lifecycle coverage to the v7.1.0 strongest-direct baseline

## [6.0.0] - 2026-03-07

### changed

- made v6 xhttp-only for mutating product paths; `--transport grpc|http2` is now rejected
- added transport-aware post-action self-check using canonical raw xray client json artifacts
- persisted operator verdicts to `/var/lib/xray/self-check.json` and surfaced them in `status --verbose` and `diagnose`
- introduced `export/capabilities.json` and generated compatibility notes from the capability matrix
- added `scripts/measure-stealth.sh` as a local measurement harness for `recommended` and `rescue` variants
- blocked `update`, `repair`, `add-clients`, and `add-keys` on managed legacy transports until `migrate-stealth` is executed
- updated bilingual docs, release metadata, and tests to the xhttp-only v6 baseline

## [5.1.0] - 2026-03-07

### changed

- made `install` a minimal xhttp-first default path with `ru-auto` and auto-selected config count
- moved manual profile/count prompts behind `install --advanced`
- added `migrate-stealth` as the supported managed migration path from legacy `grpc/http2`
- promoted `clients.json` schema v2 with per-config `variants[]`
- generated xhttp client artifacts as `recommended (auto)` and `rescue (packet-up)` variants
- exported raw per-variant xray client json files under `export/raw-xray/`
- expanded lifecycle coverage for minimal install, advanced install, and legacy-to-xhttp migration paths
- refreshed the bilingual docs set to reflect the xhttp-first baseline and legacy-transport compatibility window

## [4.2.3] - 2026-03-06

### changed

- hardened wrapper module loading: runtime now resolves modules only from trusted directories (`SCRIPT_DIR`, `XRAY_DATA_DIR`) instead of honoring external `MODULE_DIR`
- added powershell coverage to `check-security-baseline.sh` and blocked `Invoke-Expression`/`iex`, download-pipe execution patterns, and encoded-command execution
- introduced canonical global profile names `global-50` / `global-50-auto` with backward-compatible legacy aliases `global-ms10` / `global-ms10-auto`
- fixed release quality-gate dependencies so `ripgrep` is installed before `tests/lint.sh`

## [4.2.1] - 2026-03-02

### changed

- fix bats wrapper mock module set (d685d86)
- split lib modules and enforce stage-3 complexity (7045562)
- docs: migrate bilingual structure and rebrand (ff86a16)
- fix uninstall confirmation no handling via shared tty prompt (dfee450)
- fix minisign prompt no-loop and simplify yes-no text (58d48c9)
- fix deduplicate minisign fallback confirmation log (05a0309)
- fix robust yes-no confirmation parsing (a855c04)
- fix harden tty yes-no input normalization (c302e41)
- fix yes/no input normalization for tty prompts (04eb9a1)
- fix tty fd assignment in helper (ae89cbd)
- fix interactive install prompt stability (2c11d4c)
- fix tty prompt rendering and shared helpers (63c77e2)
- fix add-keys prompt matcher in e2e (3544f05)
- fix e2e expect prompt regex (94c2171)
- fix retry transient e2e network failures (f6a9b20)
- fix remove unused `MAGENTA` constant (11b8169)
- fix utf-8 box padding and input parsing (6835734)
- fix terminal ui rendering and prompts (00337d2)
- fix tty prompts and box alignment (9abd9e8)
- harden release changelog guards (a5ac8b6)
- fix path traversal in runtime validation (11dad8e)
- fix geo dir validation and status printf (a52858c)
- harden cli and destructive path checks (0e47bd0)

## [4.2.0] - 2026-02-26

### changed

- normalized operations commands to use installed `xray-reality.sh`
- aligned docs wording around ubuntu 24.04 lts support scope
- added explicit compatibility flags: `--allow-no-systemd` and `--require-minisign`
- documented minisign trust-anchor fingerprint policy
- expanded `tier_global_ms10` domain pool from 10 to 50 domains

### fixed

- install now neutralizes conflicting `systemd` drop-ins that override runtime-critical fields
- `install`, `update`, and `repair` now fail fast when `systemd` is unavailable unless compatibility mode is enabled
- strict minisign mode now fails closed when signature verification cannot be completed
- domain planning avoids adjacent duplicate domains when pool size allows
- corrected diagnostics command to use `journalctl --no-pager`

## [4.1.8] - 2026-02-24

### changed

- focused ci and documentation on ubuntu 24.04 as the validated target
- clarified workflow run naming and package metadata in github actions
- refreshed docs language for public repository operation
- added ubuntu 24.04 release checklist and maintenance notes

### fixed

- corrected bbr sysctl value handling in runtime tuning paths
- improved behavior in isolated root environments

## [4.1.7] - 2026-02-22

### note

- baseline release imported into this repository

## [<4.1.7]

### note

- older release artifacts are not published in this repository after migration
- historical details for these versions are intentionally collapsed
