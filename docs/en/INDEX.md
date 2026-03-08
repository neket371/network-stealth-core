# documentation index

this is the entrypoint for the english docs set.

## current product contract

`v7.1.0` keeps the normal install path opinionated and minimal.
managed installs now target the strongest-direct baseline:

- `vless + reality + xhttp + vless encryption + xtls-rprx-vision`
- `recommended`, `rescue`, and `emergency` client variants
- `policy.json` as the managed policy source of truth
- `clients.json` schema v3
- transport-aware self-check plus saved field measurements
- adaptive repair and `update --replan` based on recent verdicts

## read this first

| file | why it matters |
|---|---|
| [OPERATIONS.md](OPERATIONS.md) | install, migrate, repair, measure, and recover |
| [ARCHITECTURE.md](ARCHITECTURE.md) | runtime model, state split, and module boundaries |
| [TROUBLESHOOTING.md](TROUBLESHOOTING.md) | symptom-driven fixes |
| [FAQ.md](FAQ.md) | short answers to practical questions |

## full map

| file | purpose |
|---|---|
| [ARCHITECTURE.md](ARCHITECTURE.md) | strongest-direct contract, state files, and module layout |
| [OPERATIONS.md](OPERATIONS.md) | install and day-2 runbook |
| [FAQ.md](FAQ.md) | product and operator faq |
| [TROUBLESHOOTING.md](TROUBLESHOOTING.md) | failure analysis and next-step commands |
| [COMMUNITY.md](COMMUNITY.md) | how to ask for help or contribute |
| [ROADMAP.md](ROADMAP.md) | post-v7.1.0 direction |
| [GLOSSARY.md](GLOSSARY.md) | shared terms |
| [CHANGELOG.md](CHANGELOG.md) | release history |

## operator quick links

- default install: `sudo xray-reality.sh install --non-interactive --yes`
- managed migration: `sudo xray-reality.sh migrate-stealth --non-interactive --yes`
- verbose status: `sudo xray-reality.sh status --verbose`
- local measurement: `sudo bash scripts/measure-stealth.sh run --save`
- import remote field reports: `sudo bash scripts/measure-stealth.sh import --dir ./remote-canary-reports`
- replan with fresh field data: `sudo xray-reality.sh update --replan --non-interactive --yes`
- host-safe busy-server smoke: `make lab-smoke`

## important files

- `/etc/xray-reality/policy.json`
- `/etc/xray/private/keys/clients.json`
- `/etc/xray/private/keys/export/raw-xray/`
- `/etc/xray/private/keys/export/canary/`
- `/var/lib/xray/self-check.json`
- `/var/lib/xray/measurements/latest-summary.json`
