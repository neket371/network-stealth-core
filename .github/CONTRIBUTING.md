# contributing

thanks for contributing to **network stealth core**.

this repository optimizes for a very strict product contract:

- minimal install questions
- strongest safe anti-dpi default
- rollback-first mutating actions
- honest client exports and diagnostics

## current public baseline

before changing behavior, assume these contracts are public in `v7.1.0`:

- `install` = minimal strongest-direct path
- `install --advanced` = explicit manual compatibility flow
- default stack = `vless + reality + xhttp + vless encryption + xtls-rprx-vision`
- `migrate-stealth` = only supported mutating bridge for managed legacy or pre-v7 installs
- `clients.json` = schema v3 with per-config `variants[]`
- `policy.json` = managed policy source of truth
- `export/raw-xray/` = canonical per-variant xray artifacts
- `export/canary/` = field-testing bundle, including `emergency`
- `export/capabilities.json` = schema v2 capability matrix
- `/var/lib/xray/self-check.json` and `/var/lib/xray/measurements/latest-summary.json` = operator verdict state
- `scripts/measure-stealth.sh run|import|compare|prune|summarize` = local and imported measurement workflow

if your change touches any of these, update code, tests, docs, and release metadata in the same pass.

## local setup

### prerequisites

- linux or wsl
- bash 4.3+
- git
- `shellcheck`, `shfmt`, `bats`, `actionlint`
- node.js or `npx` for markdown lint

### clone and track upstream

```bash
git clone https://github.com/YOUR_USERNAME/network-stealth-core.git
cd network-stealth-core
git remote add upstream https://github.com/neket371/network-stealth-core.git
git fetch upstream
```

## repository layout

| path | purpose |
|---|---|
| `xray-reality.sh` | bootstrap wrapper |
| `lib.sh` | runtime core and dispatcher |
| `install.sh` | install, update, repair, rollback orchestration |
| `config.sh` | config generation and client artifact model |
| `service.sh` | systemd, firewall, and status surface |
| `health.sh` | health monitor, self-check, and diagnostics |
| `export.sh` | export generation and canary bundle |
| `modules/` | extracted reusable modules |
| `data/domains/catalog.json` | canonical domain metadata |
| `tests/bats/` | shell unit and integration tests |
| `tests/e2e/` | lifecycle and migration scenarios |
| `docs/` | bilingual documentation |

## mandatory local checks

run before push:

```bash
make lint
make test
make release-check
make ci-fast
make ci
make ci-full
make lab-smoke
make vm-lab-smoke
```

for windows-assisted validation:

```powershell
pwsh ./scripts/windows/run-validation.ps1 -SkipRemote
```

maintainer-only smoke and busy-host lifecycle docs live here:

- `docs/en/MAINTAINER-LAB.md`

## coding standards

1. keep scripts safe under `set -euo pipefail`
2. quote variables consistently
3. avoid `eval` on user-controlled input
4. reuse shared validators and helpers
5. keep mutating flows rollback-safe
6. prefer canonical raw xray json over lossy client templates
7. do not silently downgrade the strongest-direct contract
8. keep english and russian docs aligned in the same pass

## release hygiene

if behavior changed:

1. bump `SCRIPT_VERSION`
2. update both readmes and both changelogs
3. update the affected docs in `docs/en` and `docs/ru`
4. ensure tests cover the new contract
5. cut a tag only from a green `ubuntu` head

## support expectations for pull requests

good pull requests include:

- a short problem statement
- the chosen contract change or non-change
- test evidence
- doc updates
- migration notes when managed installs are affected

avoid:

- adding install prompts to the normal path without a very strong reason
- reviving legacy transports as active product paths
- emitting fake client templates for unsupported strongest-direct features
- changing artifact schemas without updating every consumer
