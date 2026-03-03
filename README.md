<h1 align="center">Network Stealth Core</h1>

<p align="center">
  Installation and operations toolkit for Xray Reality on Linux servers.
</p>

<p align="center">
  <a href="https://github.com/neket371/network-stealth-core/releases"><img alt="release" src="https://img.shields.io/badge/release-v4.2.1-0f766e"></a>
  <a href="LICENSE"><img alt="license" src="https://img.shields.io/badge/license-MIT-97ca00"></a>
  <a href="docs/en/OPERATIONS.md"><img alt="platform" src="https://img.shields.io/badge/platform-ubuntu%2024.04-1d4ed8"></a>
  <a href="Makefile"><img alt="qa" src="https://img.shields.io/badge/qa-make%20ci-334155"></a>
</p>

<p align="center">
  <a href="README.ru.md">Русская версия</a> • <a href="docs/en/INDEX.md">Docs (EN)</a> • <a href="docs/ru/INDEX.md">Документация (RU)</a>
</p>

## Project scope

`Network Stealth Core` is a Bash-first automation project that standardizes:

- server bootstrap and install flow
- Xray runtime configuration generation
- lifecycle operations (`install`, `update`, `repair`, `rollback`, `uninstall`)
- client artifact exports for common desktop and mobile clients

The project is public and maintained as a reusable tool, not as host-specific automation.

## Canonical source

Use only the official repository:

- `https://github.com/neket371/network-stealth-core`

If commands are copied from a mirror or fork, verify the source before execution.

## Quick start

### Recommended: universal install

```bash
curl -fL https://raw.githubusercontent.com/neket371/network-stealth-core/main/xray-reality.sh -o /tmp/xray-reality.sh
sudo bash /tmp/xray-reality.sh install
```

### Alternative: one-line install

```bash
sudo bash <(curl -fsSL https://raw.githubusercontent.com/neket371/network-stealth-core/main/xray-reality.sh) install
```

If `/dev/fd` is unavailable, use the universal install form.

### Pinned bootstrap by commit

```bash
curl -fL https://raw.githubusercontent.com/neket371/network-stealth-core/main/xray-reality.sh -o /tmp/xray-reality.sh
sudo XRAY_REPO_COMMIT=<full_commit_sha> bash /tmp/xray-reality.sh install
```

### Bootstrap source mode

Default source is `main`:

```bash
curl -fL https://raw.githubusercontent.com/neket371/network-stealth-core/main/xray-reality.sh -o /tmp/xray-reality.sh
sudo bash /tmp/xray-reality.sh install
```

Use latest release tag instead:

```bash
curl -fL https://raw.githubusercontent.com/neket371/network-stealth-core/main/xray-reality.sh -o /tmp/xray-reality.sh
sudo XRAY_BOOTSTRAP_DEFAULT_REF=release bash /tmp/xray-reality.sh install
```

## Command map

| Command | Description |
|---|---|
| `install` | Full stack install |
| `add-clients [N]` | Add `N` client configurations |
| `add-keys [N]` | Alias to `add-clients` |
| `update` | Update Xray core |
| `repair` | Reconcile service/firewall/artifacts |
| `status` | Runtime status summary |
| `logs [xray\|health\|all]` | Log streaming |
| `diagnose` | Diagnostic snapshot |
| `rollback [dir]` | Restore backup session |
| `uninstall` | Full uninstall |
| `check-update` | Check upstream version |

## Profiles and limits

| Profile | Internal tier | Config limit | Notes |
|---|---|---:|---|
| `ru` | `tier_ru` | 100 | Main RU pool |
| `ru-auto` | `tier_ru` | auto 5 | Fast RU install |
| `global-50` | `tier_global_ms10` | 10 | Global pool (50 domains) |
| `global-50-auto` | `tier_global_ms10` | auto 10 | Fast global install |
| `custom` | `custom` | 100 | User-provided domain set |

Legacy aliases `global-ms10` and `global-ms10-auto` are still accepted for backward compatibility.

## Key flags

```bash
--domain-profile ru|ru-auto|global-50|global-50-auto|custom
--transport grpc|http2
--progress-mode auto|bar|plain|none
--require-minisign
--allow-no-systemd
--num-configs N
--start-port N
--server-ip IPV4 --server-ip6 IPV6
--yes --non-interactive
--verbose
```

## Documentation map

| Path | Purpose |
|---|---|
| `docs/en/INDEX.md` | Documentation entrypoint (EN) |
| `docs/ru/INDEX.md` | Документация (RU) |
| `docs/en/ARCHITECTURE.md` | Runtime architecture and module contracts |
| `docs/en/OPERATIONS.md` | Runbook for install/update/incidents |
| `docs/en/FAQ.md` | Practical FAQ |
| `docs/en/TROUBLESHOOTING.md` | Symptom-driven troubleshooting |
| `docs/en/COMMUNITY.md` | Public collaboration model |
| `docs/en/ROADMAP.md` | Current development direction |
| `docs/en/GLOSSARY.md` | Terms and definitions |
| `docs/en/CHANGELOG.md` | Release history |
| `.github/CONTRIBUTING.md` | Contribution rules |
| `.github/SECURITY.md` | Security policy |

## Security model

Core controls include:

- strict runtime validation for paths, ports, addresses, and domains
- controlled download surface with allowlisted hosts
- artifact integrity checks (`sha256` and optional strict `minisign`)
- transactional writes and rollback on failure
- restricted `systemd` service profile and unprivileged runtime user

See [.github/SECURITY.md](.github/SECURITY.md) for full policy details.

## Supported platform

Primary and CI-validated platform:

- `ubuntu-24.04` (LTS)

Other Linux distributions may work, but are currently outside the active CI contract.

## Quality checks

```bash
make lint
make test
make release-check
make ci
```

Windows helper scripts:

```powershell
pwsh ./scripts/markdownlint.ps1
pwsh ./scripts/windows/run-validation.ps1
```

## Community

- Discussions: `GitHub Discussions` tab
- Issues: bug reports and feature requests
- Contact: X (Twitter) [x.com/neket371](https://x.com/neket371)

## License

MIT License. See [LICENSE](LICENSE).
