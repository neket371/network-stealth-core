# Глоссарий

## Actions

- `install`: полный сценарий развёртывания
- `update`: сценарий обновления Xray core
- `repair`: сценарий сверки и восстановления консистентности
- `rollback`: восстановление из предыдущего backup
- `uninstall`: удаление управляемых ресурсов

## Tier

Предопределённый пул доменов для генерации destination и SNI-наборов.

## Profile

Публичный выбор пользователя, который маппится на внутренний tier и лимиты (`ru`, `global-50` и т.д.).

## SNI fallback

Автоматический выбор альтернативного валидного server name, если приоритетный SNI недоступен.

## Domain planner

Модуль выбора доменов с учётом ranking, quarantine и no-repeat последовательности.

## Health file

`DOMAIN_HEALTH_FILE` — runtime-состояние для ранжирования и карантина доменов.

## Strict minisign mode

Режим `--require-minisign`, где отсутствие verifier или подписи приводит к ошибке install/update.

## Compatibility mode (без systemd)

Режим `--allow-no-systemd` для ограниченных окружений без полноценного управления systemd.

## Консистентность артефактов

Состояние, при котором `config.json`, `keys.txt`, `clients.txt`, `clients.json` и export-файлы соответствуют одному набору конфигурации.
