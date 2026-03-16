# changelog

all notable changes in **network stealth core** are documented here.

format: [keep a changelog](https://keepachangelog.com/en/1.0.0/)  
versioning: [semantic versioning](https://semver.org/spec/v2.0.0.html)

## [unreleased]

## [7.3.8] - 2026-03-16

### changed

- split config, install, service, and client-artifact orchestration into focused modules (`runtime_contract`, `runtime_apply`, `runtime_profiles`, `client_formats`, `client_state`, install output/selection/runtime, and service runtime/uninstall helpers)
- made the active xhttp planner catalog-first while keeping bootstrap compatibility with historical pinned tags used by `migrate-stealth`
- promoted pinned bootstrap, vm-lab proof-pack generation, and host-safe lab workflows as the maintainer-grade validation path
- refreshed issue templates, support metadata, and bilingual docs to the current `v7` strongest-direct release line

### fixed

- hardened xray log lifecycle behavior on `ubuntu-24.04`, including service startup, restart, and `logrotate` handling on hosted runners
- stabilized legacy migration fixtures and lifecycle validation for clean hosted `ubuntu-24.04` environments
- expanded audit/lint coverage to `modules/export/*` and added direct unit contracts for export capability notes and `rebuild_config_for_transport()`
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
