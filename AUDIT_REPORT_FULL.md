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
- data contracts: `catalog.json`, `domains.tiers`, `sni_pools.map`, `grpc_services.map`
- user/maintainer/security docs in both languages
- bats and e2e coverage surface

companion docs for this pass:

- `AUDIT_COVERAGE_MATRIX.md`
- `AUDIT_RUNTIME_MAP.md`
- `AUDIT_FINDINGS_BACKLOG.md`

## evidence bundle used

### local verification

- `make ci-full` — **pass**
  - bats: **418/418** pass
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

- some legacy grpc naming is still active inside xhttp-era planning and output generation
- planner data contract is split across multiple sources, not truly canonicalized yet
- root runtime entrypoints are still large enough to slow future maintenance and review
- official lint entrypoints still do not cover exactly the same workflow set

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
- however, xhttp-era generation still routes through some grpc-named concepts and data files

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

status: **good with tooling gap**

- docs are broadly aligned
- maintainer-only lab docs are correctly separated from user readmes
- workflow/actionlint coverage between `make lint` and `tests/lint.sh` still differs

## findings

### f-001 — workflow lint coverage gap between `make lint` and `tests/lint.sh`

- severity: **p3**
- type: tooling consistency
- files:
  - `Makefile`
  - `tests/lint.sh`
  - `.github/workflows/self-hosted-smoke.yml`
- evidence:
  - `Makefile` hardcodes `WORKFLOWS := ci.yml nightly-smoke.yml release.yml packages.yml os-matrix-smoke.yml`
  - `self-hosted-smoke.yml` is missing there
  - `tests/lint.sh` uses `.github/workflows/*.yml`, so it does lint that workflow
- impact:
  - `make ci-full` can stay green while one workflow escapes `actionlint`
  - official lint entrypoints still differ in scope
- verdict:
  - not a runtime bug, but still a real audit finding

### f-002 — xhttp-first planner still depends on a legacy-named multi-source contract

- severity: **p2**
- type: maintainability / contract debt
- files:
  - `config.sh`
  - `lib.sh`
  - `modules/config/domain_planner.sh`
  - `modules/config/shared_helpers.sh`
  - `modules/lib/globals_contract.sh`
  - `modules/install/bootstrap.sh`
  - `Dockerfile`
  - `data/domains/catalog.json`
  - `domains.tiers`
  - `sni_pools.map`
  - `grpc_services.map`
- evidence:
  - xhttp is the active product transport
  - planner still loads and depends on `grpc_services.map`
  - grpc-named globals and helper functions still participate in active config generation
  - runtime bundle still ships the grpc-named map file
- impact:
  - not dead code, but misleading contract naming
  - maintainers must reason about four related data sources instead of one truly canonical source
  - future cleanup/removal work is easier to break by mistake
- verdict:
  - this is the main structural debt in current runtime generation

### f-003 — core root scripts remain oversized after modularization

- severity: **p3**
- type: maintainability
- files:
  - `lib.sh` — 2720 lines
  - `config.sh` — 2069 lines
  - `install.sh` — 1553 lines
  - `service.sh` — 1321 lines
- impact:
  - slows review and safe refactoring
  - increases blast radius of small changes
  - keeps important contracts spread across very large files plus modules
- verdict:
  - not a correctness bug today, but still the biggest code-shape problem left

## closed in this audit refresh

the previous audit docs themselves were stale. this pass closes that documentation gap by replacing the old baseline with a current `v7.1.0` audit set.

## conclusion

current product verdict:

- runtime correctness: **good**
- safety/rollback behavior: **good**
- test and smoke coverage: **strong**
- dead code situation: **no confirmed active dead runtime code found**
- biggest remaining debt: **planner/data contract naming and large orchestration files**

there is no p0/p1 finding from this pass.
