# architecture

## strongest-direct runtime contract

`v7.1.0` defines one managed direct baseline:

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

## planner inputs

planner decisions come from three layers:

1. the requested domain profile from `policy.json`
2. canonical metadata in `data/domains/catalog.json`
3. runtime health and measurement history

for active `xhttp` planning, the catalog is now the primary metadata source for canonical tiers.
`domains.tiers` and `sni_pools.map` are fallback/compatibility inputs, and `transport_endpoints.map`
stays legacy-only for migration coverage.

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
- aggregates the latest summary to help operators and promotion logic
- may recommend `emergency` when direct variants are too weak on real networks

`repair` and `update --replan` can promote a stronger spare config when recent self-check or field data justifies it.

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
| `config.sh` | config build, schema v3 artifacts, and vless encryption generation |
| `service.sh` | systemd, firewall, status, uninstall, and cleanup |
| `health.sh` | diagnostics and health entrypoints |
| `modules/health/self_check.sh` | canonical post-action self-check engine |
| `modules/health/measurements.sh` | saved field report aggregation and promotion hints |
| `modules/lib/policy.sh` | managed policy serialization and loading |
| `modules/config/domain_planner.sh` | domain selection and diversity-aware planning |
| `modules/config/runtime_profiles.sh` | port allocation, path/runtime profile generation, and key helpers |
| `export.sh` | export generation, capability matrix, and canary bundle |

## design intent

the project intentionally prefers:

- fewer install questions
- one strongest safe default
- honest exports over fake compatibility
- fail-closed mutation on weak contracts
- operator visibility through saved verdicts instead of guesswork
