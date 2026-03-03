# Glossary

## Actions

- `install`: full deployment flow
- `update`: Xray core update flow
- `repair`: consistency reconciliation flow
- `rollback`: restore previous backup session
- `uninstall`: remove managed resources

## Tier

A predefined domain pool used to generate destination and SNI combinations.

## Profile

User-facing selection mapped to an internal tier and config limits (`ru`, `global-50`, etc.).

## SNI fallback

Automatic selection of another valid server name when preferred SNI is unavailable.

## Domain planner

Module that chooses domains using ranking, quarantine, and no-repeat sequencing.

## Health file

`DOMAIN_HEALTH_FILE` runtime state used for domain ranking and quarantine decisions.

## Strict minisign mode

`--require-minisign` behavior where missing verifier or signature fails installation/update.

## Compatibility mode (no systemd)

`--allow-no-systemd` mode for constrained environments where full service management is unavailable.

## Artifact consistency

State where generated files (`config.json`, `keys.txt`, `clients.txt`, `clients.json`, exports) reflect one coherent config set.
