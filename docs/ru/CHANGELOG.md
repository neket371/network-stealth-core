# changelog

здесь фиксируются изменения **network stealth core**.

формат: [keep a changelog](https://keepachangelog.com/en/1.0.0/)  
версионирование: [semantic versioning](https://semver.org/spec/v2.0.0.html)

## [unreleased]

## [7.5.6] - 2026-03-19

### Fixed
- canary bundle теперь валится fail-closed с явной ошибкой, если ломается сборка source manifest или сталкиваются имена raw-xray файлов
- wrapper теперь предупреждает, когда `SCRIPT_DIR` не удалось определить и вместо локального source tree может быть использован bootstrap path
- regex проверки версии в `check-update` нормализован так, чтобы `-` и `.` были явно литеральными в prerelease suffix
- linux-инструкция для `emergency` browser-dialer исправлена: docs и canary helper теперь используют shell-safe `env 'xray.browser.dialer=...'` вместо невалидного `export`
- `SECURITY.md` и `SECURITY.ru.md` выровнены с текущей поддерживаемой релизной линией `7.5.x`, а release-check теперь следит и за этой поверхностью
- канонический default для `SELF_CHECK_URLS` унифицирован между общими runtime-модулями

## [7.5.5] - 2026-03-18

### Changed
- явные override-пути для domain-data файлов теперь сохраняются при `resolve_paths()`, а managed default-пути по-прежнему корректно привязываются к разрешённому `data dir`
- общий root writer для `config.json` вынесен в один helper и теперь одинаково используется в полном build и rebuild flow

### Fixed
- `atomic_write` теперь режет реальные traversal-сегменты ещё до canonicalization и при этом сохраняет safe-prefix enforcement
- для `xhttp` rebuild path больше не вычисляются лишние gRPC-only timeout-параметры
- health domain probe стал строже: приоритет у реальной TLS-проверки, loose-match по одному `CONNECTED` убран, а безусловный стартовый `sleep` в connectivity check заменён на bounded readiness wait
- fallback-путь shell-рандома расширен для окружений без нормального сильного источника энтропии

## [7.5.4] - 2026-03-18

### Fixed
- release automation теперь корректно переносит заметки из `[unreleased]` в tagged section и больше не дублирует секции с висящими bullet’ами
- layout секции `7.5.3` выровнен, а release docs снова проходят markdownlint после бага в release-script

## [7.5.3] - 2026-03-18

### Changed
- source metadata (`kind`, `ref`, `commit`) теперь сохраняется в managed state и показывается в `status --verbose` и `diagnose`
- `Nightly Smoke` self-hosted зафиксирован как регулярный evidence path, а отдельный self-hosted workflow оставлен только manual/on-demand инструментом
- field validation оформлен как отдельный слой доказательства для реальных сетей вместо подмены anti-dpi proof обычным runtime-green smoke
- несколько рискованных orchestration-функций разрезаны на phase helpers без изменения публичного CLI-контракта

### Fixed
- снят ложный uninstall warning про `reset-failed`, когда после cleanup уже не остаётся ни одного `xray*` unit
- усилены real-host cleanup/rollback residue path и fallback на `xray-health` journal в server lifecycle контуре

## [7.5.2] - 2026-03-17

### Changed
- удалены архивные служебные документы из публичного репозитория, а внутренние quality-check имена выровнены под обычный maintainer workflow

## [7.5.1] - 2026-03-17

### Changed

- расширена release-валидация nightly smoke и rollback путей, чтобы опубликованное состояние ветки совпадало с полностью проверенным server-side lifecycle baseline

### Fixed

- исправлен failure-path `xray-health.service`: health timer больше не завершается раньше времени под `set -e` во время обработки счётчика неудач
- усилен rollback restore flow: связанные systemd unit’ы теперь quiesce’ятся заранее, а runtime-critical файлы восстанавливаются атомарно, без `Text file busy` на `/usr/local/bin/xray`
- `nightly_smoke_install_add_update_uninstall.sh` сделан идемпотентным за счёт уникального временного status-file на каждый прогон

## [7.5.0] - 2026-03-16

### changed

- source of truth для custom-domain install теперь сохраняется в `/etc/xray-reality/custom-domains.txt`, поэтому такие установки переживают `add-clients`, `add-keys` и следующие lifecycle-действия
- добавлен детерминированный vm-lab путь проверки tagged release через `nsc-vm-install-release` и `make vm-lab-release-smoke`

### fixed

- fail-closed валидация custom-профиля теперь рано и явно сообщает об отсутствии managed custom-domain state вместо позднего падения с пустым списком доменов
- release-facing docs и consistency-checks теперь жёстко требуют явный tag-pinned bootstrap path и generic placeholders в issue templates

## [7.3.8] - 2026-03-16

### changed

- оркестрация config, install, service и client-artifact путей разнесена по focused-модулям (`runtime_contract`, `runtime_apply`, `runtime_profiles`, `client_formats`, `client_state`, install output/selection/runtime и service runtime/uninstall helpers)
- активный xhttp planner переведён на catalog-first модель, при этом bootstrap остался совместимым с историческими pinned tag для `migrate-stealth`
- pinned bootstrap, генерация vm-lab proof-pack и host-safe lab workflows оформлены как основной maintainer-grade validation path
- issue templates, support metadata и двуязычные docs выровнены под текущую strongest-direct линию релиза `v7`

### fixed

- усилен lifecycle логов xray на `ubuntu-24.04`: startup, restart и `logrotate` больше не ломаются на hosted runner’ах
- стабилизированы legacy migration fixtures и lifecycle validation для чистых hosted окружений `ubuntu-24.04`
- quality/lint coverage расширен на `modules/export/*`, а для export capability notes и `rebuild_config_for_transport()` добавлены прямые unit-контракты
- pinned docker actions обновлены до node24-ready revisions, и hosted package builds больше не шумят из-за deprecation `Node 20`

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
