# audit findings backlog

date: 2026-03-11
baseline commit: `c848ef7ca8ed3679d7e2cfe5ac6649ee21ff24f4`

## prioritized open items

### p2

#### f-002 — reduce xhttp planner dependency on legacy-named grpc contracts

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
- problem:
  - xhttp-first runtime still relies on grpc-named data and helper contracts.
  - planner responsibility is split across canonical catalog plus legacy side maps.
- recommended fix direction:
  - define one canonical planner contract for active xhttp paths.
  - either rename and normalize the active endpoint-seed data source, or generate legacy files from the canonical source instead of treating them as peers.
  - keep legacy migration support separate from active product naming.
- acceptance:
  - active xhttp path no longer requires maintainers to reason in grpc terms.
  - planner data sources have one explicit source of truth.

### p3

#### f-001 — unify workflow lint coverage between `make lint` and `tests/lint.sh`

- type: tooling consistency
- files:
  - `Makefile`
  - `tests/lint.sh`
  - `.github/workflows/self-hosted-smoke.yml`
- problem:
  - `tests/lint.sh` actionlints all workflows; `make lint` skips `self-hosted-smoke.yml`.
- recommended fix direction:
  - make both official lint entrypoints use the same workflow set.
- acceptance:
  - no workflow can pass one official lint entrypoint while escaping the other.

#### f-003 — continue decomposing oversized root entrypoints

- type: maintainability
- files:
  - `lib.sh`
  - `config.sh`
  - `install.sh`
  - `service.sh`
- problem:
  - core orchestration files are still large and blend multiple responsibilities.
- recommended fix direction:
  - keep moving behavior into modules by subsystem, not by arbitrary helper dumping.
  - prefer smaller action-focused files with explicit contracts.
- acceptance:
  - root files mostly dispatch and compose, while behavior lives in focused modules.

## not confirmed as open bugs in this pass

- no p0/p1 runtime defect was proven
- no active dead runtime function was proven
- no release-blocking security regression was found in the audited baseline

## resolved since the older audit baseline

these older items are no longer open:

- hardening `xray_data_dir` trust boundary
- bashate policy mismatch between `make lint` and `tests/lint.sh`
- dead-function checker false negatives from comment/string matches
