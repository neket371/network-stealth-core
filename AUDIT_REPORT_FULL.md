# full audit report

date: 2026-03-13
repository: `neket371/network-stealth-core`
branch: `ubuntu`
baseline snapshot: `ubuntu` working tree after maturity hardening wave

> historical snapshot only: this document is a point-in-time audit record, not a live branch status page. any ci, runtime, or release claims here apply only to the audited tree on `2026-03-13` and must be revalidated for later commits or uncommitted changes.

## scope

this audit refresh covers the current `v7.1.0` baseline, not the old `4.2.x` shell-only snapshot.

reviewed surfaces:

- all repo-tracked files in `audit_coverage_matrix.md` (**146/146** including the new `modules/lib/*` extraction, `modules/config/runtime_profiles.sh`, `modules/config/runtime_contract.sh`, `modules/config/runtime_apply.sh`, `modules/config/client_formats.sh`, `modules/config/client_state.sh`, vm proof-pack tooling, and public issue/pr templates)
- runtime entrypoints: `xray-reality.sh`, `lib.sh`, `install.sh`, `config.sh`, `service.sh`, `health.sh`, `export.sh`
- runtime modules under `modules/*`
- qa/release/lab/windows scripts under `scripts/*`
- workflows under `.github/workflows/*`
- data contracts: `catalog.json`, `domains.tiers`, `sni_pools.map`, `transport_endpoints.map`
- user/maintainer/security docs in both languages
- bats and e2e coverage surface

companion docs for this pass:

- `AUDIT_COVERAGE_MATRIX.md`
- `AUDIT_RUNTIME_MAP.md`
- `AUDIT_FINDINGS_BACKLOG.md`

## evidence bundle used

### local verification

- `make ci-full` — **pass**
  - bats: **442/442** pass
  - release consistency: pass (`7.1.0`)
  - dead-function check: pass
  - shell complexity check: pass
  - workflow pinning check: pass
  - security baseline check: pass
  - docs command contracts: pass
  - advisory shellcheck: pass
- `bash tests/lint.sh` — **pass**
- `pwsh scripts/windows/run-validation.ps1 -SkipRemote` — **pass**

### hosted verification

latest verified `ubuntu` branch runs before closing this audit pass were green for:

- `ubuntu smoke / ubuntu / push`
- `packages / ubuntu / push`
- `ci / ubuntu / push`

the workflow set was also refreshed to node24-safe pinned action shas, removing the previous node 20 deprecation maintenance noise.

### remote isolated verification

on `185.218.204.206`:

- full `vm-lab` lifecycle smoke — **pass**
  - install
  - add-clients
  - repair
  - update
  - rollback
  - status
  - uninstall
- manual raw interactive install inside vm guest via `expect` — **pass**
  - minisign prompt accepted with a single `yes`
  - `prompt_count=1`
  - `logged_prompts=1`
  - `self-check verdict (install): ok`
  - uninstall cleanup restored guest to `inactive` and `config_absent`
- host production `xray` after vm-lab testing stayed `active`
- vm-lab proof source artifacts were collected and can now be packaged through `make vm-proof-pack`

## executive verdict

### what is healthy

- strongest-direct baseline is coherent: `xhttp + reality + vless encryption + vision`
- rollback and cleanup semantics are genuinely first-class, not decorative
- test surface is unusually strong for a shell project
- isolated vm-lab testing is now real and useful, not fake smoke
- docs are broadly aligned with current product behavior
- pinned bootstrap is now visually first-class in user-facing docs for real-server installs
- public repo hygiene is better: issue templates, pr template, and proof-pack guidance exist

### what is not broken but still costly

- planner still has fallback/compatibility side inputs, but active xhttp tier planning is now catalog-first and runtime-profile helpers were split into a focused module
- `config.sh` is no longer the main hotspot; the remaining config-side maintenance cost now sits in focused modules like `modules/config/client_formats.sh`
- support matrix is still intentionally narrow: ubuntu 24.04 is the supported and ci-validated platform

### dead code verdict

- no confirmed dead runtime code was found in the current active product path
- current dead-function guard passes
- the stronger problem is design cost and support surface, not obviously unreachable code

## subsystem verdicts

### bootstrap and trust boundary

status: **good**

- trusted source resolution and pinning behavior are explicit
- bootstrap wrapper remains one of the stronger parts of the project
- pinned bootstrap by commit is now the visually preferred quick-start path for real servers
- wrapper warnings are stronger for floating mutating bootstrap usage

### cli and public contract

status: **good**

- install-first long-option parsing is correct
- public command surface matches usage/help and docs
- current v7 contract gate behaves correctly for fresh vs legacy managed installs
- interactive install now requires explicit config count input unless the count is provided via cli/env or non-interactive path

### install/update/repair/rollback lifecycle

status: **good**

- full lifecycle smoke passed in isolated vm
- rollback restored artifacts correctly in tested tamper path
- no silent host damage was observed during vm-lab execution

### config generation and exports

status: **good with bounded complexity**

- generated strongest-direct configs pass runtime checks
- exports and raw-xray artifacts are coherent
- capabilities/compatibility notes are honest
- client artifact rendering/rebuild logic is no longer one broad helper file; it is split into focused `client_formats` and `client_state` modules behind a thin `client_artifacts.sh` loader
- xray contract generation, feature gates, mux setup, config apply, and environment snapshot logic are split out of `config.sh` into `modules/config/runtime_contract.sh` and `modules/config/runtime_apply.sh`
- runtime profile, port-allocation, and key helpers are split out of `modules/config/domain_planner.sh` into `modules/config/runtime_profiles.sh`
- install success/runtime-mode, selection, and xray/minisign bootstrap logic are split out of `install.sh` into focused modules
- service runtime and uninstall behavior are split out of `service.sh` into focused modules
- planner keeps fallback/compatibility side inputs, but active xhttp tier planning is now catalog-first rather than hard-wired to tiers and sni maps

### service/firewall/monitoring

status: **good**

- systemd and cleanup behavior passed current smoke coverage
- uninstall cleanup is strong and complete in tested flows
- runtime log-file preparation is hardened before service start and restart

### health/self-check/measurement

status: **good**

- bounded self-check behavior is correct in current tests
- vm-lab raw interactive install reached `self-check=ok`
- measurement surface exists and is internally coherent
- proof-pack generation gives operators a sanitized shareable evidence path without leaking secrets

### lab/vm infrastructure

status: **good**

- busy host remained untouched at runtime boundary
- vm-lab is now the right way to do full-fidelity testing on the shared server
- interactive prompt behavior was validated inside the isolated guest
- proof-pack generation turns vm-lab runs into reproducible operator evidence instead of hand-wavy trust

### docs and workflow surface

status: **good**

- docs are broadly aligned
- maintainer-only lab docs are correctly separated from user readmes
- workflow/actionlint coverage is aligned with local qa
- official workflow pins were refreshed to node24-safe revisions

## findings

no active `p0`–`p3` finding remains from this audit pass.

the older open maintainability item around oversized root entrypoints is considered **closed for this wave** because:

- `lib.sh` dropped to **961** lines from the previous 2700+ monolith
- `install.sh` dropped to **605** lines
- `service.sh` dropped to **484** lines
- behavior now lives in focused modules for ui/logging, downloads, config loading, path safety, runtime inputs, system runtime, install output, install selection, xray bootstrap, service runtime, and uninstall cleanup

remaining concerns are now watch items, not active defects:

- planner still keeps fallback/compatibility side inputs even though active xhttp tier planning is now catalog-first
- the remaining config-side watch items now live mainly in focused modules such as `modules/config/client_formats.sh`; `config.sh` itself is now mostly orchestration
- ubuntu 24.04 remains the intentionally narrow supported matrix

## closed in this audit refresh

the previous audit docs themselves were stale. this pass closes that documentation gap by replacing the old baseline with a current maturity-hardened audit set.

in addition, this refresh closes the older follow-up items by evidence rather than by promise:

- `f-001` — workflow lint coverage now matches between `make lint` and `tests/lint.sh`
- `f-002` — active planner seed naming is neutralized through `transport_endpoints.map`; grpc/http2 handling is explicit legacy-only coverage
- `f-003` — oversized root orchestration scripts were cut down enough that the issue is no longer an active backlog item for this wave
- `w-001` — active xhttp tier planning is now catalog-first; `domains.tiers`/`sni_pools.map` were reduced to fallback/compatibility inputs and `transport_endpoints.map` stays legacy-only
- pinned bootstrap is now first-class in user-facing docs
- vm proof-pack exists as a reproducible public evidence artifact
- public issue/pr intake templates exist
- workflow pins were refreshed away from node 20 deprecation noise

## conclusion

current product verdict:

- runtime correctness: **good**
- safety/rollback behavior: **good**
- test and smoke coverage: **strong**
- dead code situation: **no confirmed active dead runtime code found**
- maintainer maturity: **meaningfully stronger than the previous v7 audit baseline**

there is no proven `p0`/`p1`/`p2`/`p3` runtime finding from this pass.
