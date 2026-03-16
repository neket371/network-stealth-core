# политика безопасности

этот документ описывает security posture и disclosure process для **network stealth core**.

## поддерживаемые версии

| линейка версий | статус |
|---|---|
| `7.3.x` | поддерживается |
| `<7.3` | не поддерживается в этом репозитории |

## сообщение об уязвимостях

используй responsible disclosure:

1. не открывай публичные issue для security-багов
2. используй github private vulnerability reporting
3. приложи impact, шаги воспроизведения, затронутую версию или commit и, по желанию, patch proposal

целевые сроки ответа:

- первичный triage: до 48 часов
- критический patch: до 7 дней

## практическая threat model

| угроза | митигация |
|---|---|
| tampering bootstrap или downloads | pinned bootstrap, sha256 checks, optional strict minisign mode |
| command или path injection | strict validators, safe path guards и trusted wrapper sourcing |
| повреждение при partial write | atomic writes, staged validation и rollback |
| неудачный update, repair или migration | backup sessions, runtime reconciliation и fail-closed mutating gates |
| лишние привилегии service | выделенный `xray` user и restrictive `systemd` unit settings |
| stale или misleading client exports | canonical raw xray artifacts и capability matrix |
| тихая деградация direct-path | transport-aware self-check, self-check history и сохранённые field measurements |
| слишком слабый primary конфиг | promotion logic на основе self-check и measurement summary |

## security controls

### целостность и поверхность загрузок

- https-only download flows со strict validation
- allowlist критичных host через `DOWNLOAD_HOST_ALLOWLIST`
- проверки целостности артефактов через `sha256` и optional strict `REQUIRE_MINISIGN=true`
- pinned minisign trust anchor с fingerprint check через `MINISIGN_KEY`
- bootstrap pin control через `XRAY_REPO_COMMIT`; на реальных серверах предпочитай именно pinned bootstrap path
- wrapper trust boundary для `XRAY_DATA_DIR`, включаемая только через `XRAY_ALLOW_CUSTOM_DATA_DIR=true`

текущий pinned minisign key fingerprint (`sha256` содержимого `MINISIGN_KEY`):

- `294701ab7f6e18646e45b5093033d9e64f3ca181f74c0cf232627628f3d8293e`

### разделение привилегий

- service работает под отдельным non-root аккаунтом `xray`
- выдаются только минимальные runtime-привилегии для bind low ports

### systemd hardening

project units применяют такие controls:

- `NoNewPrivileges=true`
- `ProtectSystem=strict`
- `ProtectHome=true`
- `PrivateTmp=true`
- `ProtectKernelTunables=true`
- `ProtectKernelModules=true`
- `ProtectControlGroups=true`
- syscall filtering и restricted address families

### валидация входов и runtime

валидация покрывает:

- форматы доменов, портов, ipv4 и ipv6
- нормализацию xhttp path
- безопасные пути destructive-операций
- проверку url и расписаний
- валидацию self-check url и границ timeout
- transport-contract checks для legacy и pre-v7 install
- minimum xray feature contract для strongest-direct generation

### безопасность артефактов

- `clients.json` — schema v3 и остаётся permission-restricted
- raw xray exports — canonical client artifacts
- `export/capabilities.json` явно помечает unsupported targets
- `export/canary/` отделяет field-only `emergency` от обычных operator paths
- `self-check.json`, `self-check-history.ndjson` и measurement summaries хранят операторские verdict’ы
- `policy.json` хранит managed policy отдельно от generated runtime-state

### безопасность rollback

- pre-change backup snapshot
- automatic rollback на failure-path
- rollback при broken post-action self-check verdict
- firewall rollback records
- runtime reconciliation после restore

## чувствительные пути и ожидаемые права

| путь | владелец | mode | назначение |
|---|---|---:|---|
| `/usr/local/bin/xray` | `root:root` | `0755` | бинарник xray |
| `/etc/xray/config.json` | `root:xray` | `0640` | server config |
| `/etc/xray-reality/config.env` | `root:root` | `0600` | runtime snapshot |
| `/etc/xray-reality/policy.json` | `root:root` | `0600` | managed strongest-direct policy |
| `/etc/xray/private` | `root:xray` | `0750` | корневая директория чувствительных данных |
| `/etc/xray/private/keys/keys.txt` | `root:root` | `0400` | private key material |
| `/etc/xray/private/keys/clients.txt` | `root:xray` | `0640` | читаемый summary клиентов |
| `/etc/xray/private/keys/clients.json` | `root:xray` | `0640` | структурированные client metadata (`schema_version: 3`) |
| `/etc/xray/private/keys/export/raw-xray/*.json` | `root:xray` | `0640` | canonical raw xray client artifacts |
| `/etc/xray/private/keys/export/capabilities.json` | `root:xray` | `0640` | export capability matrix |
| `/etc/xray/private/keys/export/canary/manifest.json` | `root:xray` | `0640` | manifest полевого bundle |
| `/var/lib/xray/self-check.json` | `root:xray` | `0640` | последний self-check verdict |
| `/var/lib/xray/self-check-history.ndjson` | `root:xray` | `0640` | недавняя история self-check |
| `/var/lib/xray/measurements` | `root:xray` | `0750` | сохранённые field reports |
| `/var/lib/xray/measurements/latest-summary.json` | `root:xray` | `0640` | агрегированный field verdict |
| `/var/backups/xray` | `root:root` | `0700` | rollback sessions |

## рискованные overrides

эти флаги ослабляют default-гарантии и должны быть временными:

- `ALLOW_INSECURE_SHA256=true`
- `ALLOW_UNVERIFIED_MINISIGN_BOOTSTRAP=true`
- `ALLOW_NO_SYSTEMD=true`
- `GEO_VERIFY_HASH=false`
- `SELF_CHECK_ENABLED=false`
- `XRAY_ALLOW_CUSTOM_DATA_DIR=true`

## операционные рекомендации

1. на реальных серверах предпочитай pinned bootstrap path с `XRAY_REPO_COMMIT=<full_commit_sha>`; floating raw bootstrap считай convenience-путём
2. managed legacy и pre-v7 install как можно быстрее переводи через `migrate-stealth`
3. после каждого изменения проверяй `status --verbose`, `diagnose` и историю self-check
4. используй `scripts/measure-stealth.sh run|compare|summarize` для сравнения поведения на реальных сетях
5. рассматривай `emergency` как field-only tier и тестируй его через raw xray и browser dialer, а не через самодельные ссылки
6. ротируй или переустанавливай узел при подозрении на compromise или burn

## сигналы security-testing

security-sensitive поведение покрывается через:

- validator tests
- path safety tests
- rollback и lifecycle tests
- export schema validation
- покрытие self-check и measurement
- ci audit gates и docs contract checks

для operations-side incident response см. [../docs/ru/OPERATIONS.md](../docs/ru/OPERATIONS.md).
