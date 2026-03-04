# Operations runbook

This runbook is the operations reference for **Network Stealth Core**.

## Installation entry points

### Universal install (recommended)

```bash
curl -fL https://raw.githubusercontent.com/neket371/network-stealth-core/ubuntu/xray-reality.sh -o /tmp/xray-reality.sh
sudo bash /tmp/xray-reality.sh install
```

### One-line install

```bash
sudo bash <(curl -fsSL https://raw.githubusercontent.com/neket371/network-stealth-core/ubuntu/xray-reality.sh) install
```

If `/dev/fd` is unavailable, use universal install.

Migration note: legacy `main` is supported as a temporary alias for one release cycle; canonical branch is `ubuntu`.

## Runtime assumptions

- default `install`, `update`, and `repair` expect working `systemd`
- for constrained environments, use `--allow-no-systemd`
- for fail-closed signature policy, use `--require-minisign`

## Public release sanity checklist (Ubuntu 24.04 LTS)

Supported and validated target for this checklist: **Ubuntu 24.04 LTS**.

### Scope lock (must pass)

- docs do not claim unsupported OS contracts
- install commands target `https://github.com/neket371/network-stealth-core`
- `LICENSE` exists in repo root

### Local quality gate (must pass)

```bash
make ci
```

### Fresh host smoke (must pass)

On clean Ubuntu 24.04:

```bash
curl -fL https://raw.githubusercontent.com/neket371/network-stealth-core/ubuntu/xray-reality.sh -o /tmp/xray-reality.sh
sudo bash /tmp/xray-reality.sh install
sudo xray-reality.sh status
sudo xray -test -c /etc/xray/config.json
sudo xray-reality.sh add-clients 1 --non-interactive --yes
sudo xray-reality.sh update --non-interactive --yes
sudo xray-reality.sh repair --non-interactive --yes
sudo xray-reality.sh uninstall --non-interactive --yes
```

Expected:

- service is `active` after install/update/repair
- `xray -test` exits `0`
- client artifacts are generated after `add-clients`
- uninstall removes managed files and systemd units

### Security and logging sanity (must pass)

- no private keys or full client links in install log
- client links printed to `/dev/tty` only
- `clients.json` remains restricted (`640`)

### Release gate (must pass)

- create release tag only after all checks pass
- on any red check: do not publish release/package

## Daily health check

```bash
sudo xray-reality.sh status
sudo systemctl status xray --no-pager
sudo journalctl -u xray -n 200 --no-pager
sudo xray-reality.sh diagnose
```

## Safe maintenance cycle

### Update

```bash
sudo xray-reality.sh check-update
sudo xray-reality.sh update
sudo xray-reality.sh status
```

### Add client configurations

```bash
sudo xray-reality.sh add-clients 2
sudo xray-reality.sh status
```

Expected artifact set:

- `/etc/xray/private/keys/keys.txt`
- `/etc/xray/private/keys/clients.txt`
- `/etc/xray/private/keys/clients.json`
- `/etc/xray/private/keys/export/*`

## Incident matrix

| Incident | Immediate action | Verify |
|---|---|---|
| `xray` not active | `sudo systemctl restart xray` | `systemctl is-active xray` |
| config test fails | `xray -test -c /etc/xray/config.json`, then rollback | config test exits `0` |
| failed update | `sudo xray-reality.sh rollback` | service active + artifacts consistent |
| domain instability | inspect `/var/lib/xray/domain-health.json` | fail trend improves |
| firewall drift | `sudo xray-reality.sh repair` | expected ports are open/listening |

## Rollback playbook

### Latest backup

```bash
sudo xray-reality.sh rollback
```

### Specific backup

```bash
sudo xray-reality.sh rollback /var/backups/xray/<session-dir>
```

### Post-rollback verification

```bash
sudo xray-reality.sh status
sudo journalctl -u xray -n 100 --no-pager
```

## Runtime tuning knobs

| Variable | Effect |
|---|---|
| `DOMAIN_HEALTH_PROBE_TIMEOUT` | probe timeout per domain |
| `DOMAIN_HEALTH_RATE_LIMIT_MS` | delay between probes |
| `DOMAIN_HEALTH_MAX_PROBES` | maximum probes per cycle |
| `DOMAIN_QUARANTINE_FAIL_STREAK` | quarantine trigger |
| `DOMAIN_QUARANTINE_COOLDOWN_MIN` | quarantine duration |
| `PRIMARY_DOMAIN_MODE` | first-domain strategy |
| `PROGRESS_MODE` | `auto`, `bar`, `plain`, `none` |

Example:

```bash
sudo env DOMAIN_HEALTH_PROBE_TIMEOUT=3 \
  DOMAIN_HEALTH_MAX_PROBES=12 \
  PROGRESS_MODE=plain \
  xray-reality.sh repair
```

## Uninstall procedure

```bash
sudo xray-reality.sh uninstall --yes --non-interactive
```

Post-uninstall checks:

- `id xray` should fail
- `/etc/xray`, `/etc/xray-reality`, `/usr/local/bin/xray` should be removed
- previously used service ports should not listen

## Escalation package

Collect before opening an issue:

- `sudo xray-reality.sh diagnose`
- `sudo journalctl -u xray -n 500 --no-pager`
- `/etc/xray/config.json` with secrets redacted
- `/etc/xray/private/keys/clients.json` if artifact mismatch is involved
