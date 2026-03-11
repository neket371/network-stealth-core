# full audit report

date: 2026-03-11
repository: `neket371/network-stealth-core`
branch: `ubuntu`
baseline commit: `c848ef7ca8ed3679d7e2cfe5ac6649ee21ff24f4`

## scope

this audit refresh covers the current `v7.1.0` baseline, not the old `4.2.x` shell-only snapshot.

reviewed surfaces:

- all repo-tracked files in `audit_coverage_matrix.md` (**123/123**)
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
  - bats: **422/422** pass
  - release consistency: pass (`7.1.0`)
  - dead-function check: pass
  - shell complexity check: pass
  - workflow pinning check: pass
  - security baseline check: pass
  - docs command contracts: pass
  - advisory shellcheck: pass
- `bash tests/lint.sh` — **pass**

### hosted verification

current `ubuntu` branch runs for `c848ef7ca8ed3679d7e2cfe5ac6649ee21ff24f4`:

- `ubuntu smoke / ubuntu / push` — success
  `22927426019`
- `packages / ubuntu / push` — success
  `22927426031`
- `ci / ubuntu / push` — success
  `22927426065`

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

## executive verdict

### what is healthy

- strongest-direct baseline is coherent: `xhttp + reality + vless encryption + vision`
- rollback and cleanup semantics are genuinely first-class, not decorative
- test surface is unusually strong for a shell project
- isolated vm-lab testing is now real and useful, not fake smoke
- docs are broadly aligned with current product behavior

### what is not broken but still costly

- active xhttp planning no longer depends on grpc-named endpoint seed files
- planner data contract is still split across multiple sources, even after neutral endpoint seed naming cleanup
- root runtime entrypoints are still large enough to slow future maintenance and review

### dead code verdict

- no confirmed dead runtime code was found in the current active product path
- current dead-function guard passes
- the stronger problem is stale naming / compatibility debt, not obviously unreachable code

## subsystem verdicts

### bootstrap and trust boundary

status: **good**

- trusted source resolution and pinning behavior are explicit
- bootstrap wrapper remains one of the stronger parts of the project
- no new hardening regression was found in this pass

### cli and public contract

status: **good**

- install-first long-option parsing is now correct
- public command surface matches usage/help and docs
- current v7 contract gate behaves correctly for fresh vs legacy managed installs

### install/update/repair/rollback lifecycle

status: **good**

- full lifecycle smoke passed in isolated vm
- rollback restored artifacts correctly in tested tamper path
- no silent host damage was observed during vm-lab execution

### config generation and exports

status: **good with contract debt**

- generated strongest-direct configs pass runtime checks
- exports and raw-xray artifacts are coherent
- capabilities/compatibility notes are honest
- client artifact rendering/rebuild logic is now split out of `config.sh` into a focused module
- however, planner data still spans catalog + tier + side-map inputs

### service/firewall/monitoring

status: **good**

- systemd and cleanup behavior passed current smoke coverage
- uninstall cleanup is strong and complete in tested flows

### health/self-check/measurement

status: **good**

- bounded self-check behavior is correct in current tests
- vm-lab raw interactive install reached `self-check=ok`
- measurement surface exists and is internally coherent

### lab/vm infrastructure

status: **good**

- busy host remained untouched at runtime boundary
- vm-lab is now the right way to do full-fidelity testing on the shared server
- interactive prompt behavior was validated inside the isolated guest

### docs and workflow surface

status: **good**

- docs are broadly aligned
- maintainer-only lab docs are correctly separated from user readmes
- workflow/actionlint coverage is now aligned between `make lint` and `tests/lint.sh`

## findings

### f-003 — core root scripts remain oversized after modularization

- severity: **p3**
- type: maintainability
- files:
  - `lib.sh` — 2513 lines
  - `install.sh` — 1406 lines
  - `service.sh` — 1189 lines
- impact:
  - slows review and safe refactoring
  - increases blast radius of small changes
  - keeps important contracts spread across very large files plus modules
- verdict:
  - not a correctness bug today, but still the biggest code-shape problem left after reducing `config.sh`

## closed in this audit refresh

the previous audit docs themselves were stale. this pass closes that documentation gap by replacing the old baseline with a current `v7.1.0` audit set.

in addition, `f-001` was closed during the first follow-up pass by aligning `make lint` workflow coverage with `tests/lint.sh`, and `f-002` was closed by moving the active planner seed surface to the neutral `transport_endpoints.map` contract while keeping grpc/http2 handling inside explicit legacy-only branches.

## conclusion

current product verdict:

- runtime correctness: **good**
- safety/rollback behavior: **good**
- test and smoke coverage: **strong**
- dead code situation: **no confirmed active dead runtime code found**
- biggest remaining debt: **multi-source planner inputs and still-large orchestration files**

there is no p0/p1 finding from this pass.
