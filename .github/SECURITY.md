# security policy

this document defines the security posture and disclosure process for **network stealth core**.

## supported versions

| version line | status |
|---|---|
| `7.5.x` | supported |
| `<7.5` | unsupported in this repository |

## reporting vulnerabilities

use responsible disclosure:

1. do not open public issues for security bugs
2. use github private vulnerability reporting
3. include impact, reproduction steps, affected version or commit, and an optional patch proposal

response targets:

- initial triage: up to 48 hours
- critical patch target: up to 7 days

## practical threat model

| threat | mitigation |
|---|---|
| bootstrap or download tampering | pinned bootstrap support, sha256 checks, optional strict minisign mode |
| command or path injection | strict validators, exact-scope managed path guards, and trusted wrapper sourcing |
| partial write corruption | atomic writes, staged validation, and rollback |
| failed update, repair, or migration | backup sessions, runtime reconciliation, and fail-closed mutating gates |
| service over-privilege | dedicated `xray` user and restrictive `systemd` unit settings |
| stale or misleading client exports | canonical raw xray artifacts plus capability matrix |
| silent direct-path degradation | transport-aware self-check, self-check history, and saved field measurements |
| weak primary config staying active too long | promotion logic driven by self-check and measurement summaries |

## security controls

### integrity and download surface

- https-only download flows with strict validation
- allowlisted critical hosts via `DOWNLOAD_HOST_ALLOWLIST`
- artifact integrity checks with `sha256` and optional strict `REQUIRE_MINISIGN=true`
- pinned minisign trust anchor with fingerprint check via `MINISIGN_KEY`
- bootstrap pin control through `XRAY_REPO_COMMIT`; prefer the pinned bootstrap path on real servers
- wrapper code-source trust boundary for `XRAY_DATA_DIR`, enabled only with `XRAY_ALLOW_CUSTOM_DATA_DIR=true`

current pinned minisign key fingerprint (`sha256` of `MINISIGN_KEY` content):

- `294701ab7f6e18646e45b5093033d9e64f3ca181f74c0cf232627628f3d8293e`

### privilege separation

- service runs under dedicated non-root account `xray`
- only the minimum runtime privileges needed for low-port binding are granted

### systemd hardening

project units apply controls such as:

- `NoNewPrivileges=true`
- `ProtectSystem=strict`
- `ProtectHome=true`
- `PrivateTmp=true`
- `ProtectKernelTunables=true`
- `ProtectKernelModules=true`
- `ProtectControlGroups=true`
- syscall filtering and restricted address families

### input and runtime validation

validation coverage includes:

- domains, ports, ipv4, and ipv6 formats
- xhttp path normalization
- destructive operation path safety
- url and schedule validation
- self-check url validation and timeout bounds
- transport contract checks for legacy and pre-v7 installs
- minimum xray feature contract for strongest-direct generation

destructive path validation is intentionally exact-scope:

- managed system paths must match canonical parents and basenames or live under exact project path segments
- lookalike paths such as `xray-evil` do not count as project scope
- lab-style mirrored non-system trees are allowed only when they preserve the canonical managed file layout

### artifact safety

- `clients.json` is schema v3 and remains permission-restricted
- raw xray exports are the canonical client artifacts
- `export/capabilities.json` makes unsupported targets explicit
- `export/canary/` separates field-only `emergency` artifacts from normal operator paths
- `self-check.json`, `self-check-history.ndjson`, and measurement summaries persist operator-visible verdicts
- `policy.json` stores managed policy separately from generated runtime state

### rollback safety

- pre-change backup snapshot
- automatic rollback on failure paths
- rollback on broken post-action self-check verdicts
- firewall rollback records
- runtime reconciliation after restore
- staged whole-tree publish for wrapper self-sync under `XRAY_DATA_DIR`

## sensitive paths and intended permissions

| path | owner | mode | purpose |
|---|---|---:|---|
| `/usr/local/bin/xray` | `root:root` | `0755` | xray binary |
| `/etc/xray/config.json` | `root:xray` | `0640` | server config |
| `/etc/xray-reality/config.env` | `root:root` | `0600` | runtime snapshot |
| `/etc/xray-reality/policy.json` | `root:root` | `0600` | managed strongest-direct policy |
| `/etc/xray/private` | `root:xray` | `0750` | sensitive root directory |
| `/etc/xray/private/keys/keys.txt` | `root:root` | `0400` | private key material |
| `/etc/xray/private/keys/clients.txt` | `root:xray` | `0640` | human-readable client summary |
| `/etc/xray/private/keys/clients.json` | `root:xray` | `0640` | structured client metadata (`schema_version: 3`) |
| `/etc/xray/private/keys/export/raw-xray/*.json` | `root:xray` | `0640` | canonical raw xray client artifacts |
| `/etc/xray/private/keys/export/capabilities.json` | `root:xray` | `0640` | export capability matrix |
| `/etc/xray/private/keys/export/canary/manifest.json` | `root:xray` | `0640` | field-testing bundle manifest |
| `/var/lib/xray/self-check.json` | `root:xray` | `0640` | last self-check verdict |
| `/var/lib/xray/self-check-history.ndjson` | `root:xray` | `0640` | recent self-check history |
| `/var/lib/xray/measurements` | `root:xray` | `0750` | saved field reports |
| `/var/lib/xray/measurements/latest-summary.json` | `root:xray` | `0640` | aggregated field verdict |
| `/var/backups/xray` | `root:root` | `0700` | rollback sessions |

## risky overrides

these flags weaken default guarantees and should stay temporary:

- `ALLOW_INSECURE_SHA256=true`
- `ALLOW_UNVERIFIED_MINISIGN_BOOTSTRAP=true`
- `ALLOW_NO_SYSTEMD=true`
- `GEO_VERIFY_HASH=false`
- `SELF_CHECK_ENABLED=false`
- `XRAY_ALLOW_CUSTOM_DATA_DIR=true`

## operational recommendations

1. prefer the pinned bootstrap path with `XRAY_REPO_COMMIT=<full_commit_sha>` on real servers; treat the floating raw bootstrap as a convenience path
2. migrate managed legacy or pre-v7 installs promptly with `migrate-stealth`
3. monitor `status --verbose`, `diagnose`, and self-check history after every change
4. use `scripts/measure-stealth.sh run|compare|summarize` when comparing real-network behavior
5. treat `emergency` as a field-only tier and test it through raw xray plus browser dialer, not through improvised links
6. rotate or redeploy when compromise or burn is suspected

## security testing signals

security-sensitive behavior is covered by:

- validator tests
- path safety tests
- rollback and lifecycle tests
- export schema validation
- self-check and measurement coverage
- ci quality gates and docs contract checks

for operations-side incident response, see [../docs/en/OPERATIONS.md](../docs/en/OPERATIONS.md).
