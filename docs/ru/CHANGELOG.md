# Changelog

Здесь фиксируются изменения **Network Stealth Core**.

Формат: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)  
Версионирование: [Semantic Versioning](https://semver.org/spec/v2.0.0.html)

## [Unreleased]

### Changed
- Усилена загрузка модулей в wrapper: `source` выполняется только из доверенных директорий (`SCRIPT_DIR`, `XRAY_DATA_DIR`) и больше не зависит от внешнего `MODULE_DIR`.
- В `check-security-baseline.sh` добавлено покрытие PowerShell (запрет `Invoke-Expression`/`iex`, download-pipe execution и encoded-command исполнения).
- Добавлены canonical-имена global-профиля: `global-50` / `global-50-auto`; legacy-алиасы `global-ms10` / `global-ms10-auto` сохранены для обратной совместимости.

## [4.2.1] - 2026-03-02

### Changed

- Усилена устойчивость интерактивного режима (`yes/no`, TTY-нормализация, единый prompt helper).
- Исправлены рендеринг рамок/строк интерфейса и стабильность ввода в install/uninstall сценариях.
- Вынесены и зафиксированы модульные контракты, tightened runtime-валидация путей и параметров.
- Усилен CI-контур (stage-3 complexity gate, дополнительные e2e/регрессионные проверки).
- Документация и структура проекта унифицированы в двуязычном формате.

### Fixed

- `add-clients`: добавлена fail-safe проверка IPv6 inbound сборки через `jq` и проверка итогового payload.
- Исключены повторные/ложные циклы подтверждений в fallback-подтверждениях minisign.

## [4.2.0] - 2026-02-26

### Changed

- Документация переведена в двуязычную структуру `docs/en` и `docs/ru`.
- Публичное имя проекта унифицировано как `Network Stealth Core`.

- Нормализованы операционные команды под установленный `xray-reality.sh`.
- Уточнён поддерживаемый контур: Ubuntu 24.04 LTS.
- Добавлены явные compatibility-флаги: `--allow-no-systemd`, `--require-minisign`.
- Документирована политика trust-anchor для minisign.
- Пул `tier_global_ms10` расширен с 10 до 50 доменов.

### Fixed

- Install теперь нейтрализует конфликтующие systemd drop-in файлы.
- `install`, `update`, `repair` корректно прекращают выполнение без systemd, если не включён compatibility-режим.
- В strict minisign режиме реализован fail-closed.
- Исправлено распределение доменов, исключены соседние дубли.
- Исправлен аварийный diagnostic-путь (`journalctl --no-pager`).

## [4.1.8] - 2026-02-24

### Changed

- CI и документация сфокусированы на Ubuntu 24.04.
- Уточнены названия workflow-run и метаданные пакетов.
- Обновлена формулировка документации для публичного репозитория.
- Добавлен release-checklist для Ubuntu 24.04.

### Fixed

- Исправлена обработка BBR sysctl значений.
- Улучшено поведение в isolated root окружениях.

## [4.1.7] - 2026-02-22

### Note

- Базовый релиз, с которого начата история в этом репозитории.

## [<4.1.7]

### Note

- Старые релизы до миграции в новый репозиторий здесь не публикуются.
- История до 4.1.7 намеренно свернута.
