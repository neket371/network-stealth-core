<h1 align="center">Network Stealth Core</h1>

<p align="center">
  набор скриптов для установки и эксплуатации strongest-direct xray reality на linux-серверах.
</p>

<p align="center">
  <a href="https://github.com/neket371/network-stealth-core/releases"><img alt="release" src="https://img.shields.io/badge/release-v7.5.15-0f766e"></a>
  <a href="LICENSE"><img alt="license" src="https://img.shields.io/badge/license-MIT-97ca00"></a>
  <a href="docs/ru/OPERATIONS.md"><img alt="platform" src="https://img.shields.io/badge/platform-ubuntu%2024.04-1d4ed8"></a>
  <a href="Makefile"><img alt="qa" src="https://img.shields.io/badge/qa-make%20ci-334155"></a>
</p>

<p align="center">
  <a href="README.md">english version</a> • <a href="docs/ru/INDEX.md">документация (ru)</a> • <a href="docs/en/INDEX.md">docs (en)</a>
</p>

## что это за проект

`network stealth core` — bash-first проект автоматизации для managed xray reality узлов.
цель простая:

- задавать минимум вопросов при установке
- выбирать самый сильный безопасный дефолт для обхода dpi в рф
- держать все mutating-действия транзакционными и rollback-safe
- экспортировать честные клиентские артефакты, а не misleading degraded templates

## официальный источник

используйте только официальный репозиторий:

- `https://github.com/neket371/network-stealth-core`

## быстрый старт

### bootstrap с pin по commit — рекомендуемый путь для реальных серверов

обычный `install` opinionated и минимальный.
он автоматически выбирает strongest-direct контракт:

- `ru-auto`
- `vless + reality + xhttp + vless encryption + xtls-rprx-vision`
- клиентские варианты `recommended`, `rescue` и `emergency`

```bash
curl -fL https://raw.githubusercontent.com/neket371/network-stealth-core/ubuntu/xray-reality.sh -o /tmp/xray-reality.sh
sudo XRAY_REPO_COMMIT=<full_commit_sha> bash /tmp/xray-reality.sh install
```

для production-like установки лучше сразу pin'ить bootstrap wrapper на точный commit репозитория.

### bootstrap конкретного релиза по тегу

```bash
curl -fL https://raw.githubusercontent.com/neket371/network-stealth-core/v7.5.15/xray-reality.sh -o /tmp/xray-reality.sh
sudo XRAY_REPO_REF=v7.5.15 bash /tmp/xray-reality.sh install
```

этот путь удобен, когда нужен ровно опубликованный релиз без ручного поиска полного commit.
одного tag url для wrapper недостаточно: bootstrap clone всё равно пойдёт по default branch, пока явно не заданы `XRAY_REPO_REF` или `XRAY_REPO_COMMIT`.

### convenience-путь с плавающей веткой

floating bootstrap оставлен для удобства, но это уже не visually preferred путь для реального сервера:

```bash
curl -fL https://raw.githubusercontent.com/neket371/network-stealth-core/ubuntu/xray-reality.sh -o /tmp/xray-reality.sh
sudo bash /tmp/xray-reality.sh install
```

### полностью unattended установка

```bash
curl -fL https://raw.githubusercontent.com/neket371/network-stealth-core/ubuntu/xray-reality.sh -o /tmp/xray-reality.sh
sudo XRAY_REPO_COMMIT=<full_commit_sha> bash /tmp/xray-reality.sh install --non-interactive --yes
```

### ручной prompt выбора профиля доменов, когда он тебе нужен

```bash
sudo xray-reality.sh install --advanced
```

## карта команд

| команда | назначение |
|---|---|
| `install` | минимальная strongest-direct установка |
| `migrate-stealth` | переводит managed legacy или pre-v7 install на strongest-direct контракт v7 |
| `add-clients [n]` | добавляет `n` клиентских конфигов |
| `add-keys [n]` | алиас `add-clients [n]` |
| `update` | обновляет xray-core и пересобирает managed state |
| `repair` | сверяет service, firewall, policy и клиентские артефакты |
| `status` | сводка состояния |
| `logs [xray\|health\|all]` | просмотр логов |
| `diagnose` | сбор диагностики |
| `rollback [dir]` | откат из backup session |
| `uninstall` | полное удаление |
| `check-update` | проверка обновлений |

## публичный strongest-direct контракт

- `install` = минимальный strongest-direct путь без вопросов про transport и profile на основном пути; в интерактивном режиме число конфигов всё равно вводится явно
- `install --advanced` = явный manual compatibility flow для тех, кому нужен prompt выбора профиля доменов
- `migrate-stealth` = единственный mutating-мост для managed legacy `grpc/http2` install и pre-v7 xhttp install
- `update`, `repair`, `add-clients` и `add-keys` блокируются на старом managed-контракте, пока не выполнен `migrate-stealth`
- `clients.json` = `schema_version: 3`
- каждый конфиг экспортирует три варианта:
  - `recommended` = `xhttp mode=auto`
  - `rescue` = `xhttp mode=packet-up`
  - `emergency` = `xhttp mode=stream-up + browser dialer`
- `recommended` и `rescue` валидируются post-action self-check
- `emergency` экспортируется честно только как raw xray и предназначен для полевых проверок, а не для фейковых ссылок
- `update --replan` и `repair` могут повышать более сильный spare-config на основе self-check history и сохранённых field measurements
- server-side DNS здесь намеренно остаётся IPv4-first (`queryStrategy: UseIPv4`) даже при включённых IPv6 listeners; dual-stack в этом контракте означает покрытие входящих соединений, а не IPv6-preferred outbound resolution

## поверхность state и артефактов

managed install держит синхронными такие файлы:

- `/etc/xray-reality/policy.json` — source of truth для strongest-direct policy
- `data/domains/catalog.json` — canonical metadata planner’а для активных xhttp tier; `domains.tiers` и `sni_pools.map` остаются fallback/compatibility-источниками
- `/etc/xray/private/keys/clients.txt` — человекочитаемое summary по конфигам и variant’ам
- `/etc/xray/private/keys/clients-links.txt` — быстрые vless-ссылки: сначала основная, затем запасная
- `/etc/xray/private/keys/clients.json` — клиентский инвентарь schema v3
- `/etc/xray/private/keys/export/raw-xray/` — canonical per-variant xray client json
- `/etc/xray/private/keys/export/canary/` — bundle для полевых тестов `recommended`, `rescue` и `emergency`
- `/etc/xray/private/keys/export/capabilities.json` — честная capability matrix по export-target
- `/var/lib/xray/self-check.json` — последний post-action verdict
- `/var/lib/xray/self-check-history.ndjson` — недавняя история self-check
- `/var/lib/xray/measurements/` — сохранённые field reports из `scripts/measure-stealth.sh`
- `/var/lib/xray/measurements/latest-summary.json` — агрегированный field verdict для `status --verbose`, `diagnose`, `repair` и `update --replan`

## workflow measurement и canary

локальные measurement-запуски используют тот же probe-engine, что и runtime self-check:

```bash
sudo bash scripts/measure-stealth.sh run \
  --save \
  --network-tag home \
  --provider rostelecom \
  --region moscow \
  --output /tmp/measure-home.json

sudo bash scripts/measure-stealth.sh compare \
  --dir /var/lib/xray/measurements \
  --output /tmp/measure-compare.json

sudo bash scripts/measure-stealth.sh import \
  --dir ./remote-canary-reports \
  --output /tmp/measure-import.json

sudo bash scripts/measure-stealth.sh summarize \
  --dir /var/lib/xray/measurements \
  --output /tmp/measure-summary.json

sudo bash scripts/measure-stealth.sh prune \
  --keep-last 30 \
  --output /tmp/measure-prune.json
```

для удалённых тестов на сетях рф используй bundle из `export/canary/` и raw xray-конфиги оттуда.
если проверяешь `emergency`, на стороне клиента нужно выставить `xray.browser.dialer`; в POSIX shell используй `env 'xray.browser.dialer=127.0.0.1:11050' ...`, а не `export`.
hosted CI, nightly runtime smoke и busy-host lifecycle checks доказывают только runtime correctness; для реальной anti-dpi проверки используй [docs/ru/FIELD-VALIDATION.md](docs/ru/FIELD-VALIDATION.md).

## документация для сопровождающих

на этом обычная пользовательская установка и эксплуатация заканчиваются.
если ты сопровождаешь репозиторий и тебе нужны изолированные smoke-проверки или busy-host lifecycle validation, смотри:

- [docs/ru/MAINTAINER-LAB.md](docs/ru/MAINTAINER-LAB.md)
- [.github/CONTRIBUTING.ru.md](.github/CONTRIBUTING.ru.md)

## ключевые флаги

```bash
--domain-profile ru|ru-auto|global-50|global-50-auto|custom
--transport xhttp
--advanced
--replan
--progress-mode auto|bar|plain|none
--require-minisign
--allow-no-systemd
--num-configs n
--start-port n
--server-ip ipv4 --server-ip6 ipv6
--yes --non-interactive
--verbose
```

заметки:

- `--transport` в v7 зафиксирован на `xhttp` и оставлен только как compatibility no-op для поддерживаемого значения
- интерактивный `install` всегда спрашивает число конфигов; чтобы пропустить prompt, используй `--num-configs n`, а для scripted-режима — `--non-interactive --yes`
- legacy-алиасы `global-ms10` и `global-ms10-auto` всё ещё мапятся на `global-50` и `global-50-auto`
- `XRAY_DATA_DIR` в wrapper-режиме не является свободным trusted source; `XRAY_ALLOW_CUSTOM_DATA_DIR=true` используй только для trusted non-world-writable директорий

## карта документации

| путь | назначение |
|---|---|
| `docs/ru/INDEX.md` | точка входа в документацию |
| `docs/ru/ARCHITECTURE.md` | runtime-модель, state split и границы модулей |
| `docs/ru/OPERATIONS.md` | runbook по install, migration, repair, measurement и инцидентам |
| `docs/ru/FIELD-VALIDATION.md` | workflow полевой проверки для `recommended`, `rescue` и `emergency` |
| `docs/ru/FAQ.md` | практические вопросы |
| `docs/ru/MAINTAINER-LAB.md` | только для сопровождающих: изолированные smoke и vm-lab flow |
| `docs/ru/TROUBLESHOOTING.md` | диагностика по симптомам |
| `docs/ru/COMMUNITY.md` | правила взаимодействия и поддержки |
| `docs/ru/ROADMAP.md` | направление следующего релиза |
| `docs/ru/GLOSSARY.md` | общие термины |
| `docs/ru/CHANGELOG.md` | история релизов |
| `.github/CONTRIBUTING.ru.md` | правила контрибьюта |
| `.github/SECURITY.ru.md` | политика безопасности |

## безопасность

основные меры:

- строгая runtime-валидация путей, доменов, портов, адресов, расписаний и probe-url
- контролируемая поверхность загрузок с allowlist
- optional strict minisign и pinned trust anchor
- транзакционные записи с rollback при ошибке конфига, service или self-check
- ограниченный systemd unit и non-root runtime user
- canonical raw xray exports как source of truth для self-check и field measurement

подробности: [.github/SECURITY.ru.md](.github/SECURITY.ru.md).

## поддерживаемая платформа

поддерживаемая и ci-валидируемая платформа:

- `ubuntu-24.04` (lts)

## проверки качества

```bash
make lint
make test
make release-check
make ci-fast
make ci
make ci-full
```

smoke-цели для сопровождающих на занятых хостах смотри здесь:

- [docs/ru/MAINTAINER-LAB.md](docs/ru/MAINTAINER-LAB.md)
- [.github/CONTRIBUTING.ru.md](.github/CONTRIBUTING.ru.md)

windows-помощники:

```powershell
pwsh ./scripts/markdownlint.ps1
pwsh ./scripts/windows/run-validation.ps1
```
