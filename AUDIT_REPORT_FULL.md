# Full Shell Audit Report

Date: 2026-03-04  
Repository: `neket371/network-stealth-core`  
Branch: `ubuntu`  
Baseline commit: `0e36793a36bc3d881964a585ca6bb57041df34e5`

## Scope

Audit coverage includes all shell entrypoints and support scripts:

- Runtime scripts: `xray-reality.sh`, `lib.sh`, `install.sh`, `config.sh`, `service.sh`, `health.sh`, `export.sh`
- Runtime modules: `modules/lib/*.sh`, `modules/config/*.sh`, `modules/install/*.sh`
- Security/release/quality scripts: `scripts/*.sh`
- Shell test scripts: `tests/e2e/*.sh`, `tests/lint.sh`, `tests/bats/helpers/mocks.bash`

Total audited shell files: **43**

## Method

1. Automated gate baseline
   - `make ci`
   - `bash tests/lint.sh --fast`
   - `bash tests/lint.sh`
   - `bash scripts/check-shellcheck-advisory.sh`
2. Static pattern scans
   - dangerous command patterns (`eval`, curl|sh, mktemp race, unsafe rm patterns)
   - AI/meta comments and TODO/FIXME markers in shell files
3. Manual code review
   - bootstrap trust chain and pinning
   - install/update/uninstall lifecycle
   - minisign/sha256 fallback policy
   - systemd and rollback behavior
   - prompt/TTY paths
   - release and guard scripts
4. Cross-check against tests and gates

## Baseline Results

### Automated checks

- `make ci`: **PASS**
  - shellcheck/shfmt/actionlint: pass
  - dead-function check: pass
  - shell complexity check: pass
  - workflow pinning check: pass
  - security baseline check: pass
  - docs command contracts: pass
  - bats: `356/356` pass
  - release consistency check: pass (`4.2.1`)
- `tests/lint.sh --fast`: **PASS**
- `tests/lint.sh`: **PASS**
- `check-shellcheck-advisory.sh`: **PASS**

### Manual review outcome

- No critical runtime-functional defects found in install/update/add/uninstall/rollback flows.
- No dead functions reported by project’s dead-code guard.
- No security-baseline violations detected by project guards.
- Interactive confirmation and minisign fallback logic are consistent with current tests.

## Findings

### F-001 — Hardening gap: environment-controlled module root can be used as code source

- Severity: **P2 (hardening)**
- Type: security hardening gap
- Files:
  - [xray-reality.sh](D:\Project\network-stealth-core\xray-reality.sh)
- Relevant locations:
  - `XRAY_DATA_DIR` default/override path selection (top-level env binding)
  - `resolve_module_dir()` candidate order (`SCRIPT_DIR`, `XRAY_DATA_DIR`)
  - module sourcing through resolved module directory
- Description:
  - For installed usage (where `SCRIPT_DIR` does not contain modules), `XRAY_DATA_DIR` is accepted from environment and can become a dynamic module source.
  - This can execute alternate local shell code if a privileged operator explicitly injects `XRAY_DATA_DIR`.
- Impact:
  - Not a remote exploit; requires local privileged invocation with crafted environment.
  - Increases accidental/misconfiguration attack surface for a public project.
- Recommendation:
  - Add strict allowlist validation for `XRAY_DATA_DIR` before any `source` (for example only default path + optional explicit `--data-dir` flag).
  - Optionally ignore env override when EUID=0 unless an explicit CLI flag is used.

### F-002 — Lint pipeline inconsistency between `Makefile` and `tests/lint.sh`

- Severity: **P3**
- Type: tooling consistency
- Files:
  - [tests/lint.sh](D:\Project\network-stealth-core\tests\lint.sh)
  - [Makefile](D:\Project\network-stealth-core\Makefile)
- Relevant locations:
  - `tests/lint.sh` requires `bashate` and runs it
  - `make lint` does not require/run `bashate`
- Description:
  - Two official lint entrypoints enforce different toolchains.
  - A contributor may pass `make ci` and fail `tests/lint.sh` (or vice versa) due to `bashate`.
- Impact:
  - Contributor friction and inconsistent local/CI expectations.
- Recommendation:
  - Unify policy: either add `bashate` to `make lint` (and CI), or remove it from `tests/lint.sh`.

### F-003 — Dead-function checker can under-report due text-level matching

- Severity: **P3**
- Type: analysis quality risk
- File:
  - [scripts/check-dead-functions.sh](D:\Project\network-stealth-core\scripts\check-dead-functions.sh)
- Description:
  - Call-site detection relies on regex over raw text and can treat comment/string mentions as usage.
  - This may hide truly dead functions (false negatives).
- Impact:
  - Lower confidence in dead-code guarantees for future growth.
- Recommendation:
  - Filter comment-only lines before matching, and/or tighten matcher.
  - Keep current check but mark it advisory if precision cannot be improved safely.

## Conclusion

Runtime functionality is currently stable and well-covered by automated gates and tests.  
No P0/P1 defects were found in this audit pass.  
Primary work remaining is hardening and quality-consistency improvements (F-001..F-003).

