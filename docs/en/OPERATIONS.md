# operations

## default operator model

default operations assume one managed node on `ubuntu-24.04`.
normal install stays opinionated and minimal.

strongest-direct defaults:

- profile: `ru-auto`
- transport: `xhttp`
- stack: `vless + reality + xhttp + vless encryption + xtls-rprx-vision`
- variants: `recommended`, `rescue`, `emergency`
- self-check: enabled by default
- measurement storage: enabled by default when you save reports

## install

for the first bootstrap on a real server, prefer the pinned bootstrap path from the readme (`XRAY_REPO_COMMIT=<full_commit_sha>`).
if you need the exact published release instead of the current floating branch, use the tag-pinned bootstrap path from the readme (`XRAY_REPO_REF=v<release-tag>`).
fetching the wrapper from a tag url alone does not pin the bootstrap clone.

### normal path

```bash
sudo xray-reality.sh install
```

interactive installs on the normal path still ask for the config count.
for scripted installs, use:

```bash
sudo xray-reality.sh install --non-interactive --yes
```

what this should do:

- build the strongest-direct stack without transport questions
- write `policy.json`
- generate schema v3 client artifacts
- print the primary and fallback `vless` links during install and keep the full list in `clients-links.txt`
- run post-action self-check with `recommended`, then `rescue` if needed
- export raw xray configs, capability matrix, and canary bundle

### manual compatibility path

```bash
sudo xray-reality.sh install --advanced
```

use this only when you intentionally want the manual domain-profile prompt.

## migration

run this on:

- managed legacy `grpc/http2` installs
- managed xhttp installs created before the strongest-direct contract

```bash
sudo xray-reality.sh migrate-stealth --non-interactive --yes
```

after migration, re-check:

```bash
sudo xray-reality.sh status --verbose
sudo xray-reality.sh diagnose
```

## day-2 actions

### add clients

```bash
sudo xray-reality.sh add-clients 2 --non-interactive --yes
```

this rebuilds managed artifacts from the live config and preserves the strongest-direct contract.

### repair

```bash
sudo xray-reality.sh repair --non-interactive --yes
```

`repair` now also:

- rebuilds `clients.txt`, `clients-links.txt`, `clients.json`, raw xray exports, capability matrix, and canary bundle
- refreshes `policy.json`
- may promote a better spare config when recent verdicts show the current primary is weak

### update

```bash
sudo xray-reality.sh update --non-interactive --yes
```

force a priority rebuild from recent verdicts:

```bash
sudo xray-reality.sh update --replan --non-interactive --yes
```

use `--replan` after you save fresh real-network reports.

## status and diagnosis

### concise status

```bash
sudo xray-reality.sh status
```

### verbose status

```bash
sudo xray-reality.sh status --verbose
```

verbose status should show:

- strongest-direct contract details
- source metadata (`kind`, `ref`, `commit`)
- last self-check verdict
- latest field measurement verdict
- current primary config
- best spare config
- whether `emergency` is recommended

### full diagnosis

```bash
sudo xray-reality.sh diagnose
```

`diagnose` now includes policy, self-check history, and measurement summary.
it also prints the managed source metadata used to produce the current node state.

## measurement workflow

### run a local measurement and save it

```bash
sudo bash scripts/measure-stealth.sh run \
  --save \
  --network-tag home \
  --provider rostelecom \
  --region moscow \
  --output /tmp/measure-home.json
```

### compare saved reports

```bash
sudo bash scripts/measure-stealth.sh compare \
  --dir /var/lib/xray/measurements \
  --output /tmp/measure-compare.json
```

### import remote canary reports into managed storage

```bash
sudo bash scripts/measure-stealth.sh import \
  --dir ./remote-canary-reports \
  --output /tmp/measure-import.json
```

### summarize the latest picture

```bash
sudo bash scripts/measure-stealth.sh summarize \
  --dir /var/lib/xray/measurements \
  --output /tmp/measure-summary.json
```

### prune older stored reports

```bash
sudo bash scripts/measure-stealth.sh prune \
  --keep-last 30 \
  --output /tmp/measure-prune.json
```

plain invocation without a subcommand behaves like `run`.

runtime smoke, hosted CI, and busy-host lifecycle checks do not prove real-network anti-dpi effectiveness by themselves.
for that layer, use the separate playbook in [FIELD-VALIDATION.md](FIELD-VALIDATION.md).

## maintainer-only smoke and busy-host validation

normal production operations stop here.
if you maintain the repo and need isolated smoke or busy-host lifecycle validation, use:

- [MAINTAINER-LAB.md](MAINTAINER-LAB.md)
- [.github/CONTRIBUTING.md](../../.github/CONTRIBUTING.md)

## canary bundle

managed exports now include:

- `export/canary/manifest.json`
- `export/canary/raw-xray/*.json`
- `export/canary/measure-linux.sh`
- `export/canary/measure-windows.ps1`

use the canary bundle when you need field testing from another machine or network.
for the `emergency` variant, set the browser dialer env on the client side:

```bash
export xray.browser.dialer=127.0.0.1:11050
```

## important files

| path | meaning |
|---|---|
| `/etc/xray-reality/policy.json` | managed policy |
| `/etc/xray-reality/config.env` | generated env snapshot |
| `/etc/xray/config.json` | live xray config |
| `/etc/xray/private/keys/clients.txt` | human-readable config summary |
| `/etc/xray/private/keys/clients-links.txt` | quick-copy vless links |
| `/etc/xray/private/keys/clients.json` | schema v3 client inventory |
| `/etc/xray/private/keys/export/capabilities.json` | export support map |
| `/var/lib/xray/self-check.json` | last self-check verdict |
| `/var/lib/xray/self-check-history.ndjson` | recent self-check history |
| `/var/lib/xray/measurements/latest-summary.json` | latest field summary |

## rollback and uninstall

### rollback

```bash
sudo xray-reality.sh rollback
```

or restore a specific session:

```bash
sudo xray-reality.sh rollback /var/backups/xray/<session-dir>
```

### uninstall

```bash
sudo xray-reality.sh uninstall --non-interactive --yes
```

managed uninstall removes policy, self-check history, measurement summaries, and generated export artifacts together.

## practical operator loop

1. install or migrate to the strongest-direct contract
2. verify `status --verbose`
3. save a few real-network measurements
4. run `update --replan` or `repair` if the field summary points to a better spare
5. use `emergency` only when direct variants are not enough on the tested network
