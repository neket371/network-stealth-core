# glossary

## strongest-direct install

the default install contract: minimal prompts, strongest safe direct stack, and canonical raw exports.

## advanced mode

`install --advanced`, the explicit manual compatibility flow that enables the domain-profile prompt.

## stealth contract version

the managed runtime contract version recorded in policy and client artifacts.
in the current `v7` strongest-direct line it represents the managed strongest-direct baseline.

## policy.json

`/etc/xray-reality/policy.json`, the managed policy source of truth.

## domain catalog

`data/domains/catalog.json`, the canonical metadata set used by the domain planner.

## provider family

a planner label used to keep configs diversified across domain cohorts.

## client variant

a per-config client profile stored inside `clients.json` `variants[]`.

## recommended variant

the primary xhttp client artifact with `mode=auto`.

## rescue variant

the compatibility fallback xhttp artifact with `mode=packet-up`.

## emergency variant

the browser-assisted field tier with `mode=stream-up`; exported as raw xray only.

## raw xray export

the canonical per-variant client json in `export/raw-xray/`.

## capability matrix

`export/capabilities.json`, the machine-readable support map for generated export targets.

## canary bundle

`export/canary/`, a portable bundle for field testing from other machines or networks.

## self-check state

`/var/lib/xray/self-check.json`, the latest post-action verdict.

## self-check history

`/var/lib/xray/self-check-history.ndjson`, recent post-action verdict history.

## measurement harness

`scripts/measure-stealth.sh`, the local tool for `run`, `import`, `compare`, `prune`, and `summarize` field measurements.

## measurement summary

`/var/lib/xray/measurements/latest-summary.json`, the aggregated field verdict used by operator surfaces and promotion logic.

## replan

`update --replan`, a rebuild that lets recent self-check and field data influence config priority.

## xtls-rprx-vision

the direct flow used by the strongest-direct contract.

## vless encryption

generated outbound-side encryption metadata paired with inbound `decryption` for the strongest-direct contract.
