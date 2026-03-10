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

### normal path

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

use this only when you intentionally want manual profile and count prompts.

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

## host-safe lab smoke on a busy server

when the host already carries production services, keep smoke tests isolated:

```bash
make lab-smoke
```

or run the scripts explicitly:

```bash
bash scripts/lab/prepare-host-safe-smoke.sh
bash scripts/lab/run-container-smoke.sh
bash scripts/lab/collect-container-artifacts.sh
```

this flow expects an existing `docker` or `podman` runtime, publishes no container ports, forces `c.utf-8` inside the smoke container, and keeps logs under the host-safe lab directory instead of touching the repo tree.

## full vm-lab lifecycle on a busy server

when you need the real `systemd` lifecycle without touching the busy host namespace, use the kvm vm-lab:

```bash
make vm-lab-prepare
make vm-lab-smoke
```

or run the scripts directly:

```bash
bash scripts/lab/prepare-vm-smoke.sh
bash scripts/lab/run-vm-lifecycle-smoke.sh
bash scripts/lab/enter-vm-smoke.sh
```

this flow:

- requires `kvm`, `qemu-system-x86_64`, `qemu-img`, `cloud-localds`, and `ssh`
- downloads the ubuntu 24.04 cloud image once under the lab directory
- boots an isolated guest with `systemd`
- forwards only guest ssh to host loopback
- copies the current repo into the guest
- runs the full nightly lifecycle smoke there, including `install`, `add-clients`, `repair`, `update`, `rollback`, `status`, and `uninstall`
- collects guest logs back into the vm-lab log directory

for manual guest-side testing, use:

```bash
nsc-vm-install-latest --num-configs 3
nsc-vm-install-repo --advanced
```

do not use raw `curl ... xray-reality.sh` inside the vm-lab guest: a nat-backed guest can auto-detect the host public ip and fail the final self-check.

default guest-side smoke values:

- `start_port=24440`
- `initial_configs=1`
- `add_configs=1`
- `e2e_server_ip=10.0.2.15`
- `e2e_domain_check=false`
- `e2e_skip_reality_check=false`
- `xray_custom_domains=vk.com,yoomoney.ru,cdek.ru`
- `install_version=latest stable`
- `update_version=install_version`

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
