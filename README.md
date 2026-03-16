<h1 align="center">Network Stealth Core</h1>

<p align="center">
  installation and operations toolkit for strongest-direct xray reality on linux servers.
</p>

<p align="center">
  <a href="https://github.com/neket371/network-stealth-core/releases"><img alt="release" src="https://img.shields.io/badge/release-v7.5.0-0f766e"></a>
  <a href="LICENSE"><img alt="license" src="https://img.shields.io/badge/license-MIT-97ca00"></a>
  <a href="docs/en/OPERATIONS.md"><img alt="platform" src="https://img.shields.io/badge/platform-ubuntu%2024.04-1d4ed8"></a>
  <a href="Makefile"><img alt="qa" src="https://img.shields.io/badge/qa-make%20ci-334155"></a>
</p>

<p align="center">
  <a href="README.ru.md">русская версия</a> • <a href="docs/en/INDEX.md">docs (en)</a> • <a href="docs/ru/INDEX.md">документация (ru)</a>
</p>

## project scope

`network stealth core` is a bash-first automation project for managed xray reality nodes.
its goal is simple:

- ask almost nothing during install
- choose the strongest safe default for rf anti-dpi use
- keep every mutating action transactional and rollback-safe
- export honest client artifacts instead of misleading degraded templates

## canonical source

use only the official repository:

- `https://github.com/neket371/network-stealth-core`

## quick start

### pinned bootstrap by commit (recommended on real servers)

default `install` is opinionated and minimal.
it selects the strongest-direct contract automatically:

- `ru-auto`
- `vless + reality + xhttp + vless encryption + xtls-rprx-vision`
- `recommended`, `rescue`, and `emergency` client variants

```bash
curl -fL https://raw.githubusercontent.com/neket371/network-stealth-core/ubuntu/xray-reality.sh -o /tmp/xray-reality.sh
sudo XRAY_REPO_COMMIT=<full_commit_sha> bash /tmp/xray-reality.sh install
```

for production-like installs, pin the bootstrap wrapper to an exact repo commit.

### pinned bootstrap by release tag

```bash
curl -fL https://raw.githubusercontent.com/neket371/network-stealth-core/v7.5.0/xray-reality.sh -o /tmp/xray-reality.sh
sudo XRAY_REPO_REF=v7.5.0 bash /tmp/xray-reality.sh install
```

use this when you want the exact published release without looking up the full commit first.
fetching `xray-reality.sh` from a tag url alone is not enough: the bootstrap clone still follows its default branch unless `XRAY_REPO_REF` or `XRAY_REPO_COMMIT` is set explicitly.

### convenience floating bootstrap

the floating branch bootstrap stays available for convenience, but it is not the visually preferred production path:

```bash
curl -fL https://raw.githubusercontent.com/neket371/network-stealth-core/ubuntu/xray-reality.sh -o /tmp/xray-reality.sh
sudo bash /tmp/xray-reality.sh install
```

### fully unattended install

```bash
curl -fL https://raw.githubusercontent.com/neket371/network-stealth-core/ubuntu/xray-reality.sh -o /tmp/xray-reality.sh
sudo XRAY_REPO_COMMIT=<full_commit_sha> bash /tmp/xray-reality.sh install --non-interactive --yes
```

### manual domain-profile prompt when you explicitly want it

```bash
sudo xray-reality.sh install --advanced
```

## command map

| command | description |
|---|---|
| `install` | minimal strongest-direct install |
| `migrate-stealth` | convert managed legacy or pre-v7 installs to the v7 strongest-direct contract |
| `add-clients [n]` | add `n` client configurations |
| `add-keys [n]` | alias of `add-clients [n]` |
| `update` | update xray-core and rebuild managed state |
| `repair` | reconcile service, firewall, policy, and client artifacts |
| `status` | runtime status summary |
| `logs [xray\|health\|all]` | view logs |
| `diagnose` | collect diagnostics |
| `rollback [dir]` | restore backup session |
| `uninstall` | full uninstall |
| `check-update` | check upstream version |

## strongest-direct public contract

- `install` = minimal strongest-direct path with no transport or profile questions on the normal path; interactive installs still require an explicit config count
- `install --advanced` = explicit manual compatibility flow for operators who want the domain-profile prompt
- `migrate-stealth` = only supported mutating bridge for managed legacy `grpc/http2` installs and pre-v7 xhttp installs
- `update`, `repair`, `add-clients`, and `add-keys` are blocked on older managed contracts until `migrate-stealth` succeeds
- `clients.json` = `schema_version: 3`
- every config exports three variants:
  - `recommended` = `xhttp mode=auto`
  - `rescue` = `xhttp mode=packet-up`
  - `emergency` = `xhttp mode=stream-up + browser dialer`
- `recommended` and `rescue` are validated by post-action self-check
- `emergency` is exported honestly as raw xray only and is meant for field testing, not fake link templates
- `update --replan` and `repair` may promote a stronger spare config using self-check history and saved field measurements

## state and artifact surface

managed installs now keep these files in sync:

- `/etc/xray-reality/policy.json` — strongest-direct policy source of truth
- `data/domains/catalog.json` — canonical planner metadata for active xhttp tiers; `domains.tiers` and `sni_pools.map` remain fallback/compatibility inputs
- `/etc/xray/private/keys/clients.txt` — human-readable summary of configs and variants
- `/etc/xray/private/keys/clients-links.txt` — quick-copy vless links with a primary and fallback order
- `/etc/xray/private/keys/clients.json` — schema v3 client inventory
- `/etc/xray/private/keys/export/raw-xray/` — canonical per-variant xray client json
- `/etc/xray/private/keys/export/canary/` — field-testing bundle for `recommended`, `rescue`, and `emergency`
- `/etc/xray/private/keys/export/capabilities.json` — honest capability matrix for generated exports
- `/var/lib/xray/self-check.json` — last post-action verdict
- `/var/lib/xray/self-check-history.ndjson` — recent self-check history
- `/var/lib/xray/measurements/` — saved field reports from `scripts/measure-stealth.sh`
- `/var/lib/xray/measurements/latest-summary.json` — aggregated field verdict used by `status --verbose`, `diagnose`, `repair`, and `update --replan`

## measurement and canary workflow

local measurements use the same probe engine as runtime self-check:

```bash
sudo bash scripts/measure-stealth.sh run \
  --save \
  --network-tag home \
  --provider rostelecom \
  --region moscow \
  --output /tmp/measure-home.json

sudo bash scripts/measure-stealth.sh compare \
  --dir /var/lib/xray/measurements \
  --output /tmp/measure-compare.json

sudo bash scripts/measure-stealth.sh import \
  --dir ./remote-canary-reports \
  --output /tmp/measure-import.json

sudo bash scripts/measure-stealth.sh summarize \
  --dir /var/lib/xray/measurements \
  --output /tmp/measure-summary.json

sudo bash scripts/measure-stealth.sh prune \
  --keep-last 30 \
  --output /tmp/measure-prune.json
```

for remote rf testing, send the generated canary bundle from `export/canary/` and use the raw xray configs there.
set `xray.browser.dialer` on the client side when you intentionally test the `emergency` variant.

## maintainer-only validation docs

normal user-facing install and operations stop here.
if you maintain the repo and need isolated smoke or busy-host lifecycle validation, use:

- [docs/en/MAINTAINER-LAB.md](docs/en/MAINTAINER-LAB.md)
- [.github/CONTRIBUTING.md](.github/CONTRIBUTING.md)

## key flags

```bash
--domain-profile ru|ru-auto|global-50|global-50-auto|custom
--transport xhttp
--advanced
--replan
--progress-mode auto|bar|plain|none
--require-minisign
--allow-no-systemd
--num-configs n
--start-port n
--server-ip ipv4 --server-ip6 ipv6
--yes --non-interactive
--verbose
```

notes:

- `--transport` is fixed to `xhttp` in v7 and exists only as a compatibility no-op for the supported value
- interactive `install` always asks for the config count; use `--num-configs n` to skip the prompt or `--non-interactive --yes` for scripted installs
- legacy aliases `global-ms10` and `global-ms10-auto` still map to `global-50` and `global-50-auto`
- `XRAY_DATA_DIR` is not a free-form trusted code source in wrapper mode; use `XRAY_ALLOW_CUSTOM_DATA_DIR=true` only for trusted non-world-writable directories

## documentation map

| path | purpose |
|---|---|
| `docs/en/INDEX.md` | documentation entrypoint |
| `docs/en/ARCHITECTURE.md` | runtime model, state split, and module boundaries |
| `docs/en/OPERATIONS.md` | install, migration, repair, measurement, and incident runbook |
| `docs/en/FAQ.md` | practical questions |
| `docs/en/MAINTAINER-LAB.md` | maintainer-only isolated smoke and vm-lab flows |
| `docs/en/TROUBLESHOOTING.md` | symptom-driven troubleshooting |
| `docs/en/COMMUNITY.md` | collaboration and support guidance |
| `docs/en/ROADMAP.md` | next-release direction |
| `docs/en/GLOSSARY.md` | shared terms |
| `docs/en/CHANGELOG.md` | release history |
| `.github/CONTRIBUTING.md` | contribution rules |
| `.github/SECURITY.md` | security policy |

## security model

core controls include:

- strict runtime validation for paths, domains, ports, addresses, schedules, and probe urls
- controlled download surface with allowlisted hosts
- optional strict minisign verification and pinned trust anchor
- transactional writes with rollback on config, service, or self-check failure
- restricted systemd unit and non-root runtime account
- canonical raw xray exports as the source of truth for self-check and field measurement

see [.github/SECURITY.md](.github/SECURITY.md) for the full policy.

## supported platform

supported and ci-validated platform:

- `ubuntu-24.04` (lts)

## quality checks

```bash
make lint
make test
make release-check
make ci-fast
make ci
make ci-full
```

for maintainer-only smoke targets on busy hosts, see:

- [docs/en/MAINTAINER-LAB.md](docs/en/MAINTAINER-LAB.md)
- [.github/CONTRIBUTING.md](.github/CONTRIBUTING.md)

windows helpers:

```powershell
pwsh ./scripts/markdownlint.ps1
pwsh ./scripts/windows/run-validation.ps1
```
