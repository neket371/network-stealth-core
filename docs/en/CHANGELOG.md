# Changelog

All notable changes in **Network Stealth Core** are documented here.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)  
Versioning: [Semantic Versioning](https://semver.org/spec/v2.0.0.html)

## [Unreleased]

## [4.2.1] - 2026-03-02

### Changed
- fix bats wrapper mock module set (d685d86)
- split lib modules and enforce stage3 complexity (7045562)
- docs: migrate bilingual structure and rebrand (ff86a16)
- fix uninstall confirmation no handling via shared tty prompt (dfee450)
- fix minisign prompt no-loop and simplify yes-no text (58d48c9)
- fix deduplicate minisign fallback confirmation log (05a0309)
- fix robust yes-no confirmation parsing (a855c04)
- fix harden tty yes-no input normalization (c302e41)
- fix yes/no input normalization for tty prompts (04eb9a1)
- fix tty fd assignment in helper (ae89cbd)
- fix interactive install prompt stability (2c11d4c)
- fix tty prompt rendering and shared helpers (63c77e2)
- fix add-keys prompt matcher in e2e (3544f05)
- fix e2e expect prompt regex (94c2171)
- fix retry transient e2e network failures (f6a9b20)
- fix remove unused MAGENTA constant (11b8169)
- fix utf8 box padding and input parsing (6835734)
- fix terminal ui rendering and prompts (00337d2)
- fix tty prompts and box alignment (9abd9e8)
- harden release changelog guards (a5ac8b6)
- fix path traversal in runtime validation (11dad8e)
- fix geo dir validation and status printf (a52858c)
- harden cli and destructive path checks (0e47bd0)


### Changed

- Documentation moved to bilingual structure: `docs/en` and `docs/ru`.
- Public naming unified to `Network Stealth Core` across scripts and docs.

## [4.2.0] - 2026-02-26

### Changed

- Normalized operations commands to use installed `xray-reality.sh`.
- Aligned docs wording around Ubuntu 24.04 LTS support scope.
- Added explicit compatibility flags: `--allow-no-systemd` and `--require-minisign`.
- Documented minisign trust-anchor fingerprint policy.
- Expanded `tier_global_ms10` domain pool from 10 to 50 domains.

### Fixed

- Install now neutralizes conflicting `systemd` drop-ins that override runtime-critical fields.
- `install`, `update`, and `repair` now fail fast when `systemd` is unavailable unless compatibility mode is enabled.
- Strict minisign mode now fails closed when signature verification cannot be completed.
- Domain planning avoids adjacent duplicate domains when pool size allows.
- Corrected diagnostics command to use `journalctl --no-pager`.

## [4.1.8] - 2026-02-24

### Changed

- Focused CI and documentation on Ubuntu 24.04 as the validated target.
- Clarified workflow run naming and package metadata in GitHub Actions.
- Refreshed docs language for public repository operation.
- Added Ubuntu 24.04 release checklist and maintenance notes.

### Fixed

- Corrected BBR sysctl value handling in runtime tuning paths.
- Improved behavior in isolated root environments.

## [4.1.7] - 2026-02-22

### Note

- Baseline release imported into this repository.

## [<4.1.7]

### Note

- Older release artifacts are not published in this repository after migration.
- Historical details for these versions are intentionally collapsed.
