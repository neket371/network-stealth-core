# audit findings backlog

date: 2026-03-13
baseline snapshot: `ubuntu` working tree after maturity hardening wave

> historical snapshot only: this backlog reflects the audited tree on `2026-03-13`. do not treat it as an evergreen claim about later commits, unreleased work, or the current working tree without a fresh verification pass.

## active backlog

there is no confirmed open `p0`–`p3` runtime or release-blocking finding in this audit pass.

## watch items

these are real future maintenance costs, but they are **not** proven defects in the current baseline:

### w-002 — a few focused modules are still broad enough to deserve future decomposition if scope grows

- type: maintainability
- files:
  - `modules/config/client_formats.sh`
  - `modules/lib/runtime_inputs.sh`
- problem:
  - the root-script sprawl problem was materially reduced, and `config.sh` is now mostly orchestration; the remaining future maintenance risk sits in a couple of focused modules that could still bloat if new scope is piled onto them carelessly.
- recommended direction:
  - keep new behavior out of the root entrypoints.
  - prefer subsystem-focused extractions before these modules start growing sharply again.
  - keep `modules/config/runtime_profiles.sh` focused; do not let it turn into the next planner-style catch-all.
  - keep `modules/lib/runtime_inputs.sh` narrow; new path/config loading logic should stay in the dedicated lib modules.

## resolved in this wave

these older items are no longer open:

- `f-001` — workflow lint coverage mismatch between `make lint` and `tests/lint.sh`
- `f-002` — active xhttp planner dependency on grpc-named seed contracts
- `f-003` — oversized root entrypoint sprawl; this wave cut `lib.sh` below 1000 lines and moved orchestration behavior into focused modules
- `w-001` — active planner reads are now catalog-first for canonical xhttp tiers; `domains.tiers`/`sni_pools.map` remain fallback/compatibility and `transport_endpoints.map` stays legacy-only
- pinned bootstrap being visually secondary to floating bootstrap in user docs
- missing public issue/pr intake templates
- missing reusable vm-lab proof-pack artifact flow
- workflow maintenance noise from node 20 deprecation warnings in pinned actions
