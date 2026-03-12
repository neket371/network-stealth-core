# changelog

здесь фиксируются изменения **network stealth core**.

формат: [keep a changelog](https://keepachangelog.com/en/1.0.0/)  
версионирование: [semantic versioning](https://semver.org/spec/v2.0.0.html)

## [unreleased]

### changed

- интерактивный `install` теперь всегда требует явный ввод числа конфигов на обычном пути; `--num-configs` остаётся scripted-override
- ручной потолок для `global-50` поднят до `15`, а non-interactive auto default оставлен на `5`
- pinned bootstrap по commit теперь вынесен в visually first-class quick start для реальных серверов, а wrapper печатает более жёсткую подсказку при floating mutating bootstrap
- wrapper bootstrap верификация сохранена совместимой с историческими pinned tag, которые используются в `migrate-stealth`, и больше не требует новые split lib modules
- активные canonical xhttp tier теперь читают metadata из catalog в первую очередь, а `domains.tiers`/`sni_pools.map` стали fallback/compatibility-источниками; значения catalog при этом нормально нормализуются и на windows line endings
- runtime profile, выделение портов и генерация ключей вынесены из `modules/config/domain_planner.sh` в отдельный `modules/config/runtime_profiles.sh`
- `lib.sh` дополнительно декомпозирован на focused-модули ui/logging, system-runtime, downloads, config-loading, path-safety и runtime-inputs
- добавлен санитизированный `make vm-proof-pack` / `scripts/lab/generate-vm-proof-pack.sh` для evidence bundle из vm-lab lifecycle run
- добавлены public issue templates и pull request template для более чистого bug/support/feature intake
- pinned github actions обновлены до node24-safe upstream shas, а self-hosted/nightly vm-lab workflow теперь выгружает proof-pack artifacts

## [7.1.0] - 2026-03-07

### changed

- strongest-direct контракт стал managed baseline: `vless + reality + xhttp + vless encryption + xtls-rprx-vision`
- добавлен `/etc/xray-reality/policy.json` как source of truth для managed policy
- `clients.json` поднят до schema v3 с provider metadata, direct-flow полями и тремя variants на конфиг
- добавлен field-only вариант `emergency` (`xhttp stream-up + browser dialer`), при этом `recommended` и `rescue` остались server-validated direct path
- добавлен `data/domains/catalog.json` и awareness planner’а по provider family для более разнообразных наборов конфигов
- `scripts/measure-stealth.sh` расширен до workflow `run`, `compare` и `summarize`, а measurement summaries стали сохраняться на диске
- добавлен `export/canary/` для переносимых полевых тестов, а `export/capabilities.json` поднят до schema v2
- `repair` и `update --replan` теперь используют self-check и field observations при продвижении более сильного spare-config
- `migrate-stealth` теперь обновляет и legacy transport, и pre-v7 xhttp install
- двуязычные docs, release metadata и lifecycle coverage обновлены до strongest-direct baseline v7.1.0

## [6.0.0] - 2026-03-07

### changed

- v6 переведен в xhttp-only режим для mutating product paths; `--transport grpc|http2` теперь отклоняется
- добавлен transport-aware post-action self-check по canonical raw xray client json artifacts
- operator verdict сохраняется в `/var/lib/xray/self-check.json` и показывается в `status --verbose` и `diagnose`
- введен `export/capabilities.json`, а `compatibility-notes.txt` теперь генерируется из capability matrix
- добавлен `scripts/measure-stealth.sh` как local measurement harness для вариантов `recommended` и `rescue`
- `update`, `repair`, `add-clients` и `add-keys` блокируются на managed legacy transport до выполнения `migrate-stealth`
- двуязычная документация, release metadata и тесты обновлены до xhttp-only baseline v6

## [5.1.0] - 2026-03-07

### changed

- `install` переведен в минимальный xhttp-first путь по умолчанию с `ru-auto` и auto-выбором числа конфигов
- ручные prompt’ы выбора профиля и числа конфигов перенесены за `install --advanced`
- добавлен `migrate-stealth` как штатная managed-миграция с legacy `grpc/http2`
- `clients.json` переведен на schema v2 с `variants[]` для каждого конфига
- xhttp-клиентские артефакты теперь создаются как `recommended (auto)` и `rescue (packet-up)` варианты
- raw xray json по вариантам экспортируются в `export/raw-xray/`
- расширено lifecycle-покрытие для minimal install, advanced install и миграции legacy-to-xhttp
- двуязычная документация приведена к xhttp-first baseline и compatibility-окну для legacy transport

## [4.2.3] - 2026-03-06

### changed

- усилена загрузка модулей в wrapper: `source` выполняется только из доверенных директорий (`SCRIPT_DIR`, `XRAY_DATA_DIR`) и больше не зависит от внешнего `MODULE_DIR`
- в `check-security-baseline.sh` добавлено покрытие powershell и заблокированы `Invoke-Expression`/`iex`, download-pipe execution и encoded-command execution
- добавлены canonical-имена global-профиля: `global-50` / `global-50-auto`; legacy-алиасы `global-ms10` / `global-ms10-auto` сохранены для обратной совместимости
- исправлены зависимости release quality-gate: перед `tests/lint.sh` теперь устанавливается `ripgrep`

## [4.2.1] - 2026-03-02

### changed

- усилена устойчивость интерактивного режима (`yes/no`, tty-нормализация, единый prompt helper)
- исправлены рендеринг рамок и стабильность ввода в install/uninstall сценариях
- вынесены и зафиксированы модульные контракты, tightened runtime-валидация путей и параметров
- усилен ci-контур (stage-3 complexity gate, дополнительные e2e и регрессионные проверки)
- документация и структура проекта унифицированы в двуязычном формате

### fixed

- `add-clients`: добавлена fail-safe проверка ipv6 inbound сборки через `jq` и проверка итогового payload
- исключены повторные и ложные циклы подтверждений в fallback-подтверждениях minisign

## [4.2.0] - 2026-02-26

### changed

- нормализованы операционные команды под установленный `xray-reality.sh`
- уточнён поддерживаемый контур: ubuntu 24.04 lts
- добавлены явные compatibility-флаги: `--allow-no-systemd` и `--require-minisign`
- документирована политика trust-anchor для minisign
- пул `tier_global_ms10` расширен с 10 до 50 доменов

### fixed

- install теперь нейтрализует конфликтующие systemd drop-in файлы
- `install`, `update` и `repair` корректно прекращают выполнение без systemd, если не включён compatibility-режим
- в strict minisign режиме реализован fail-closed
- исправлено распределение доменов, исключены соседние дубли
- исправлен diagnostic-путь (`journalctl --no-pager`)

## [4.1.8] - 2026-02-24

### changed

- ci и документация сфокусированы на ubuntu 24.04
- уточнены названия workflow-run и метаданные пакетов
- обновлена формулировка документации для публичного репозитория
- добавлен release-checklist для ubuntu 24.04

### fixed

- исправлена обработка bbr sysctl значений
- улучшено поведение в isolated root окружениях

## [4.1.7] - 2026-02-22

### note

- базовый релиз, с которого начата история в этом репозитории

## [<4.1.7]

### note

- старые релизы до миграции в новый репозиторий здесь не публикуются
- история до 4.1.7 намеренно свернута
