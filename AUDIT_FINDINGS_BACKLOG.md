# Audit Findings Backlog

Date: 2026-03-04  
Scope: full shell audit (43 files)

## Prioritized items

## P2

### F-001 — Harden module source trust boundary (`XRAY_DATA_DIR`)

- Status: Open
- Files:
  - [xray-reality.sh](D:\Project\network-stealth-core\xray-reality.sh)
- Problem:
  - `XRAY_DATA_DIR` can influence module source path for `source` when `SCRIPT_DIR` lacks modules.
- Target fix:
  - Validate `XRAY_DATA_DIR` against trusted allowlist before `resolve_module_dir`.
  - Add explicit opt-in flag for non-default data dir for privileged runs.
  - Keep backward compatibility by preserving default path behavior.
- Acceptance criteria:
  1. Passing unsafe `XRAY_DATA_DIR` is rejected before any source.
  2. Default install/update/status flows unchanged.
  3. New/updated tests cover unsafe override rejection and safe explicit override.

## P3

### F-002 — Unify lint policy between `make lint` and `tests/lint.sh`

- Status: Open
- Files:
  - [Makefile](D:\Project\network-stealth-core\Makefile)
  - [tests/lint.sh](D:\Project\network-stealth-core\tests\lint.sh)
- Problem:
  - `tests/lint.sh` enforces `bashate`; `make lint` does not.
- Target fix:
  - Pick one canonical policy and apply in both entrypoints.
- Acceptance criteria:
  1. Same tool requirements in both commands.
  2. CI and local lint output are consistent.

### F-003 — Improve dead-function check precision

- Status: Open
- File:
  - [scripts/check-dead-functions.sh](D:\Project\network-stealth-core\scripts\check-dead-functions.sh)
- Problem:
  - Regex-based call matching may count comments/strings as real calls.
- Target fix:
  - Reduce false negatives by filtering non-code contexts or tightening matcher.
- Acceptance criteria:
  1. Synthetic test case with comment-only mention is not counted as call site.
  2. Existing repository still passes dead-function check.

## Deferred / no action now

- No P0/P1 findings in current pass.
- No mandatory runtime bugfix required for `4.2.1` stability based on this audit.

