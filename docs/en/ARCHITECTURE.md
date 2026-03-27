# architecture

## strongest-direct runtime contract

the current `v7` strongest-direct line defines one managed direct baseline:

- protocol: `vless`
- security: `reality`
- transport: `xhttp`
- direct flow: `xtls-rprx-vision`
- per-config generated `vless encryption` and matching inbound `decryption`

managed client variants are:

- `recommended` = `xhttp mode=auto`
- `rescue` = `xhttp mode=packet-up`
- `emergency` = `xhttp mode=stream-up + browser dialer`

`recommended` and `rescue` are part of post-action validation.
`emergency` is field-only and is exported as raw xray json plus canary metadata.

## state model

the project now splits managed policy from generated runtime state.

| file or path | role |
|---|---|
| `/etc/xray-reality/policy.json` | operator-facing policy source of truth |
| `data/domains/catalog.json` | canonical domain metadata and provider families |
| `/etc/xray/config.json` | live xray server config |
| `/etc/xray-reality/config.env` | compatibility snapshot of generated state |
| `/etc/xray/private/keys/clients.json` | schema v3 artifact inventory |
| `/etc/xray/private/keys/export/raw-xray/` | canonical per-variant client configs |
| `/etc/xray/private/keys/export/canary/` | field-testing bundle |
| `/var/lib/xray/self-check.json` | latest post-action verdict |
| `/var/lib/xray/self-check-history.ndjson` | recent self-check history |
| `/var/lib/xray/measurements/*.json` | saved field reports |
| `/var/lib/xray/measurements/latest-summary.json` | aggregate field verdict and promotion hints |
| `/var/lib/xray/measurements/rotation-state.json` | persisted weak-primary streak, cooldown families/domains, and last promotion context |

## planner inputs

planner decisions come from three layers:

1. the requested domain profile from `policy.json`
2. canonical metadata in `data/domains/catalog.json`
3. runtime health and measurement history

for active `xhttp` planning, the catalog is now the primary metadata source for canonical tiers.
`domains.tiers` and `sni_pools.map` are fallback/compatibility inputs, and `transport_endpoints.map`
stays legacy-only for migration coverage.
the committed fallback files are generated from the catalog by `scripts/generate-domain-fallbacks.sh`,
and `scripts/check-domain-data-consistency.sh` now rejects drift between the catalog and those fallback views.

`catalog.json` gives the planner structured metadata such as:

- `tier`
- `provider_family`
- `region`
- candidate `ports`
- `priority`
- `risk`
- `sni_pool`

this lets the planner avoid burning one provider family and keep stronger spares available.

## mutating flow model

all mutating actions keep the same high-level shape:

1. load policy, config, and current artifacts
2. validate inputs and feature contract
3. back up managed state
4. build candidate config and artifacts
5. validate with `xray -test`
6. apply atomically
7. run post-action self-check using canonical raw xray clients
8. record verdicts and either keep state or roll back

## managed path contract

destructive actions now use one shared managed-artifact registry instead of separate hardcoded cleanup lists.
that registry covers:

- runtime binaries and wrapper scripts
- systemd unit, timer, and logrotate artifacts
- config, policy, env, and managed custom-domain files
- client export surfaces and supporting logs
- runtime state, self-check, measurement, and backup directories

the safety model is intentionally narrow:

- system paths must either use exact managed basenames in canonical managed parents or live under exact project path segments such as `xray`, `xray-reality`, or `network-stealth-core`
- lookalike paths such as `xray-evil` or `reality-backup-other` are not treated as managed scope
- non-system mirrored trees used by labs and disposable nested test roots are allowed only when they keep the canonical managed file layout

this keeps uninstall/rollback/repair aligned on the same scope and avoids both false cleanup gaps and broad substring-based destructive matches.

## managed source-tree publish

wrapper self-sync now publishes the managed source tree as a staged whole-tree commit.

instead of copying `modules/`, `data/`, and `scripts/` first and then patching root files in place, the flow now:

1. prepares a staging copy of the existing managed tree
2. overlays the current repo content into that staging tree
3. atomically swaps the full staged tree into `XRAY_DATA_DIR`

this removes the previous mixed-tree window where modules could already be new while root entrypoints still came from the older tree after a partial copy failure.

## migration boundary

`migrate-stealth` is the only mutating bridge from older managed contracts.
it upgrades both:

- legacy `grpc/http2` installs
- pre-v7 xhttp installs that do not yet meet the strongest-direct contract

until that migration succeeds, `update`, `repair`, `add-clients`, and `add-keys` fail closed.

## client artifact model

`clients.json` schema v3 stores the managed contract in a machine-readable form.

each config keeps:

- identity material such as `uuid`, `short_id`, and `public_key`
- selection metadata such as `provider_family`, `primary_rank`, and `recommended_variant`
- direct contract fields such as `transport`, `flow`, `vless_encryption`, and `vless_decryption`
- per-variant outputs including raw xray files, links where honest, and browser-dialer requirements

raw xray json remains the canonical artifact because it can express the full strongest-direct contract without loss.

## validation and promotion model

there are two observation loops:

### post-action self-check

- uses generated raw xray client json
- probes `recommended` first, then `rescue`
- writes `/var/lib/xray/self-check.json`
- appends `/var/lib/xray/self-check-history.ndjson`
- triggers rollback if both direct variants fail

### field measurement

- uses `scripts/measure-stealth.sh run|import|compare|prune|summarize`
- saves reports under `/var/lib/xray/measurements/`
- aggregates the latest summary and persists rotation cooldown state for promotion logic
- may recommend `emergency` when direct variants are too weak on real networks

`repair` and `update --replan` now share one operator-decision layer and one cooldown-aware rotation engine, so the same weak-primary streak and provider-family penalties are applied to both actions.

## export layer

exports are capability-driven:

- raw xray json: native
- `clients.txt` and `clients.json`: native
- v2rayn and nekoray: link-only where honest
- sing-box and clash-meta: explicitly unsupported for the strongest-direct contract
- canary bundle: native field-testing surface

that support map is written to `export/capabilities.json`.

## module map

| module | role |
|---|---|
| `lib.sh` | dispatcher, validation, path safety, and command contracts |
| `install.sh` | install/update/repair/migrate orchestration |
| `config.sh` | config orchestration over focused runtime-contract, runtime-apply, and client-artifact modules |
| `service.sh` | systemd, firewall, status, uninstall, and cleanup |
| `health.sh` | diagnostics and health entrypoints |
| `modules/health/operator_decision.sh` | shared operator decision payload and cooldown-aware promotion engine |
| `modules/health/self_check.sh` | canonical post-action self-check engine |
| `modules/health/measurements.sh` | saved field report aggregation and promotion hints |
| `modules/lib/policy.sh` | managed policy serialization and loading |
| `modules/lib/legacy_transport_contract.sh` | isolated legacy grpc/mux compatibility defaults kept only for migrate/rebuild coverage |
| `modules/config/client_artifacts.sh` | thin client-artifact loader for focused formats and state helpers |
| `modules/config/client_formats.sh` | client link/json/text rendering, raw-xray client export generation, and key-file output |
| `modules/config/client_state.sh` | clients.json normalization, self-check readiness, and artifact rebuild helpers |
| `modules/config/domain_planner.sh` | domain selection and diversity-aware planning |
| `modules/config/runtime_profiles.sh` | port allocation, path/runtime profile generation, and key helpers |
| `modules/config/runtime_contract.sh` | xray config-contract generation, feature gates, mux setup, and vless encryption helpers |
| `modules/config/runtime_apply.sh` | xray `-test` execution, atomic config apply, and environment snapshot persistence |
| `export.sh` | export generation, capability matrix, and canary bundle |

## design intent

the project intentionally prefers:

- fewer install questions
- one strongest safe default
- honest exports over fake compatibility
- fail-closed mutation on weak contracts
- operator visibility through saved verdicts instead of guesswork
