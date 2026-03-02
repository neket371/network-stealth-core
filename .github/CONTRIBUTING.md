# Contributing

Thanks for contributing to **Network Stealth Core**.

This guide defines the expected workflow for safe and reviewable changes.

## Core rules

- keep commits focused and small
- preserve rollback and security behavior
- include tests and docs updates with behavior changes
- avoid silent compatibility breaks

## Local setup

### Prerequisites

- Linux or WSL
- Bash 4.3+
- Git
- `shellcheck`, `shfmt`, `bats`, `actionlint`
- Node.js (or `npx`) for markdown lint

### Clone and track upstream

```bash
git clone https://github.com/YOUR_USERNAME/network-stealth-core.git
cd network-stealth-core
git remote add upstream https://github.com/neket371/network-stealth-core.git
git fetch upstream
```

## Repository layout

| Path | Purpose |
|---|---|
| `xray-reality.sh` | bootstrap wrapper |
| `lib.sh` | runtime core and dispatcher |
| `install.sh` | dependency setup and Xray install/update |
| `config.sh` | config generation and key/client artifacts |
| `service.sh` | systemd, firewall, lifecycle operations |
| `health.sh` | health monitor and diagnostics |
| `export.sh` | client export templates |
| `modules/` | extracted reusable modules |
| `tests/bats/` | shell unit and integration tests |
| `tests/e2e/` | lifecycle and scenario tests |
| `docs/` | bilingual documentation |

## Mandatory local checks

Run before push:

```bash
make lint
make test
make release-check
make ci
```

Equivalent direct commands:

```bash
bash tests/lint.sh
bats tests/bats
bash scripts/check-release-consistency.sh
```

## Shell complexity policy

This repository enforces staged shell complexity gates.

- stage 3 limit: file <= 2800 lines
- stage 3 limit: function <= 320 lines

For any `lib.sh` growth, do not relax limits. Extract logic into `modules/lib/*.sh` and keep runtime contracts unchanged.

## Coding standards

1. keep scripts safe under `set -euo pipefail`
2. quote variables consistently
3. avoid `eval` for user-controlled input
4. reuse shared validators
5. use atomic writes for critical files
6. keep mutating flows rollback-safe

## High-risk areas

Changes in these areas require extra coverage:

- bootstrap and download verification
- permission and path handling
- systemd unit generation
- firewall apply and rollback
- backup stack and cleanup traps

## Testing expectations

- every behavior change should include or update BATS coverage
- lifecycle-sensitive changes should include e2e checks
- docs updates must pass markdown lint and command-contract checks

Example targeted runs:

```bash
bats tests/bats/unit.bats
bats tests/bats/integration.bats
bats tests/bats/health.bats
```

## Branch and commit style

### Branch naming

- `fix/<topic>`
- `feat/<topic>`
- `docs/<topic>`
- `security/<topic>`

### Commit format

```text
type(scope): summary
```

Examples:

- `fix(config): harden temporary config validation`
- `docs(readme): refresh quick-start and docs map`
- `security(wrapper): tighten bootstrap pin checks`

## Pull request checklist

- [ ] local checks are green (`make ci`)
- [ ] tests cover changed behavior
- [ ] docs updated for user-visible changes
- [ ] `docs/en/CHANGELOG.md` updated when needed
- [ ] no secrets in commits
- [ ] rollback and security behavior preserved

## Documentation update scope

Behavior changes usually affect:

- `README.md`
- `README.ru.md`
- `docs/en/*.md`
- `docs/ru/*.md`
- `.github/CONTRIBUTING.md`
- `.github/SECURITY.md`

## Security reporting

Do not open public issues for vulnerabilities.

Use GitHub private vulnerability reporting.  
See [.github/SECURITY.md](SECURITY.md).
