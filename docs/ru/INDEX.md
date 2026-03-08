# индекс документации

это точка входа в русскоязычный набор docs.

## текущий продуктовый контракт

`v7.1.0` держит normal install path opinionated и минимальным.
managed install теперь целится в strongest-direct baseline:

- `vless + reality + xhttp + vless encryption + xtls-rprx-vision`
- клиентские варианты `recommended`, `rescue` и `emergency`
- `policy.json` как source of truth для managed policy
- `clients.json` schema v3
- transport-aware self-check и сохранённые field measurements
- adaptive repair и `update --replan` на основе недавних verdict’ов

## что читать первым

| файл | зачем нужен |
|---|---|
| [OPERATIONS.md](OPERATIONS.md) | install, migration, repair, measurement и recovery |
| [ARCHITECTURE.md](ARCHITECTURE.md) | runtime-модель, state split и границы модулей |
| [TROUBLESHOOTING.md](TROUBLESHOOTING.md) | исправление проблем по симптомам |
| [FAQ.md](FAQ.md) | короткие ответы на практические вопросы |

## полная карта

| файл | назначение |
|---|---|
| [ARCHITECTURE.md](ARCHITECTURE.md) | strongest-direct контракт, state files и модульная структура |
| [OPERATIONS.md](OPERATIONS.md) | runbook для install и day-2 операций |
| [FAQ.md](FAQ.md) | продуктовый и операторский faq |
| [TROUBLESHOOTING.md](TROUBLESHOOTING.md) | анализ сбоев и точные next-step команды |
| [COMMUNITY.md](COMMUNITY.md) | как просить помощь и контрибьютить |
| [ROADMAP.md](ROADMAP.md) | направление после v7.1.0 |
| [GLOSSARY.md](GLOSSARY.md) | общие термины |
| [CHANGELOG.md](CHANGELOG.md) | история релизов |

## быстрые operator-ссылки

- дефолтная установка: `sudo xray-reality.sh install --non-interactive --yes`
- managed-миграция: `sudo xray-reality.sh migrate-stealth --non-interactive --yes`
- подробный статус: `sudo xray-reality.sh status --verbose`
- локальное measurement: `sudo bash scripts/measure-stealth.sh run --save`
- импорт удалённых field-reports: `sudo bash scripts/measure-stealth.sh import --dir ./remote-canary-reports`
- replan после новых field data: `sudo xray-reality.sh update --replan --non-interactive --yes`
- host-safe smoke на занятом сервере: `make lab-smoke`

## важные файлы

- `/etc/xray-reality/policy.json`
- `/etc/xray/private/keys/clients.json`
- `/etc/xray/private/keys/export/raw-xray/`
- `/etc/xray/private/keys/export/canary/`
- `/var/lib/xray/self-check.json`
- `/var/lib/xray/measurements/latest-summary.json`
