# roadmap

this roadmap is a directional public plan, not a strict delivery promise.

## current baseline

the current `v7` strongest-direct line establishes:

- minimal strongest-direct install
- policy-driven managed state via `policy.json`
- schema v3 client inventory with `recommended`, `rescue`, and `emergency`
- canonical raw xray exports plus canary bundle
- saved self-check history and field measurement summaries
- adaptive repair and `update --replan`

## next priorities

1. turn family-penalty and long-term trend data into safer automatic rotation for repeatedly weak configs
2. add a shorter operator-facing doctor layer with one-screen verdicts and actions
3. keep reducing shared mutable state and legacy compatibility noise before the `v8` cleanup line
4. keep bilingual docs and release metadata perfectly aligned

## medium-term direction

- stronger operator tooling around field-data import, family diversity, and long-term trend review
- safer automation for retiring or rotating repeatedly weak configs
- richer capability notes for external clients that eventually gain honest support

## out of scope for now

- adding more questions to the normal install path
- reviving legacy transports as active product paths
- fake compatibility templates for unsupported strongest-direct features
- broad multi-os promises without ci coverage
- mandatory cdn or fleet-management layers in the core path
