# contributing

спасибо за вклад в **network stealth core**.

репозиторий оптимизирован под очень строгий продуктовый контракт:

- минимум вопросов при установке
- самый сильный безопасный anti-dpi дефолт
- rollback-first mutating-действия
- честные клиентские экспорты и диагностика

## текущий публичный baseline

до изменения поведения считай публичными такие контракты текущей strongest-direct линии `v7`:

- `install` = минимальный strongest-direct путь
- `install --advanced` = явный manual compatibility flow
- дефолтный стек = `vless + reality + xhttp + vless encryption + xtls-rprx-vision`
- `migrate-stealth` = единственный поддерживаемый mutating-мост для managed legacy или pre-v7 install
- `clients.json` = schema v3 с `variants[]` для каждого конфига
- `policy.json` = source of truth для managed policy
- `export/raw-xray/` = canonical per-variant xray artifacts
- `export/canary/` = bundle для полевых тестов, включая `emergency`
- `export/capabilities.json` = capability matrix schema v2
- `/var/lib/xray/self-check.json` и `/var/lib/xray/measurements/latest-summary.json` = операторский verdict state
- `scripts/measure-stealth.sh run|import|compare|prune|summarize` = локальный и импортируемый measurement-workflow

если изменение затрагивает что-то из этого, обнови код, тесты, документацию и release metadata в одном проходе.

## локальная подготовка

### зависимости

- linux или wsl
- bash 4.3+
- git
- `shellcheck`, `shfmt`, `bats`, `actionlint`
- node.js или `npx` для markdown lint

### clone и upstream

```bash
git clone https://github.com/YOUR_USERNAME/network-stealth-core.git
cd network-stealth-core
git remote add upstream https://github.com/neket371/network-stealth-core.git
git fetch upstream
```

## структура репозитория

| путь | назначение |
|---|---|
| `xray-reality.sh` | bootstrap wrapper |
| `lib.sh` | runtime core и dispatcher |
| `install.sh` | orchestration для install, update, repair, rollback |
| `config.sh` | генерация конфигов и клиентская модель артефактов |
| `service.sh` | systemd, firewall и status-surface |
| `health.sh` | health monitor, self-check и диагностика |
| `export.sh` | генерация export’ов и canary bundle |
| `modules/` | вынесенные reusable modules |
| `data/domains/catalog.json` | canonical metadata доменов |
| `tests/bats/` | shell unit и integration tests |
| `tests/e2e/` | lifecycle и migration scenarios |
| `docs/` | двуязычная документация |

github issue и pull-request templates лежат здесь:

- `.github/ISSUE_TEMPLATE/`
- `.github/PULL_REQUEST_TEMPLATE.md`

## обязательные локальные проверки

перед push:

```bash
make lint
make test
make release-check
make ci-fast
make ci
make ci-full
make lab-smoke
make vm-lab-smoke
```

для windows-assisted проверки:

```powershell
pwsh ./scripts/windows/run-validation.ps1 -SkipRemote
```

документация по smoke-проверкам для сопровождающих и busy-host lifecycle лежит здесь:

- `docs/ru/MAINTAINER-LAB.md`

если lifecycle bug воспроизводится через vm-lab, приложи ещё и:

- `make vm-proof-pack`

регулярное self-hosted evidence должно идти через `Nightly Smoke`.
`.github/workflows/self-hosted-smoke.yml` — только manual/on-demand workflow, а не scheduled proof-source.

## coding standards

1. держи скрипты безопасными под `set -euo pipefail`
2. последовательно экранируй переменные
3. не используй `eval` на пользовательском вводе
4. переиспользуй общие валидаторы и helper’ы
5. сохраняй rollback-safe поведение mutating-flow
6. предпочитай canonical raw xray json вместо lossy client templates
7. не делай silent downgrade strongest-direct контракта
8. держи english и russian docs синхронными в одном проходе

## release hygiene

если поведение изменилось:

1. подними `SCRIPT_VERSION`
2. обнови оба readme, оба changelog и release-facing issue templates
3. обнови затронутые docs в `docs/en` и `docs/ru`
4. убедись, что тесты покрывают новый контракт
5. режь тег только с зелёного `ubuntu` head

## чего ждём от pull request

хороший pr содержит:

- короткое описание проблемы
- выбранное изменение контракта или явное сохранение старого
- test evidence
- updates в документации
- migration notes, если затронуты managed install

избегай:

- добавления prompt’ов в normal install path без очень сильной причины
- возврата legacy transport как активного продуктового пути
- генерации фейковых client templates для unsupported strongest-direct features
- изменения artifact schema без обновления всех consumers
