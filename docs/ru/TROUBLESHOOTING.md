# troubleshooting

## 1. install задаёт неожиданные вопросы

default install должен оставаться минимальным.
обычный интерактивный install всё равно спрашивает число конфигов.
если ты запускал `install --advanced`, дополнительный prompt выбора профиля доменов тоже нормален.
для unattended-установки используй:

```bash
sudo xray-reality.sh install --non-interactive --yes
```

## 2. `update`, `repair` или `add-clients` говорят, что сначала нужна миграция

ты находишься на legacy или pre-v7 managed-контракте.
запусти:

```bash
sudo xray-reality.sh migrate-stealth --non-interactive --yes
```

потом проверь:

```bash
sudo xray-reality.sh status --verbose
```

## 3. status показывает `warning` или `broken`

сначала собери общую картину:

```bash
sudo xray-reality.sh status --verbose
sudo xray-reality.sh diagnose
```

потом действуй так:

- `warning`: сохрани measurements с реальных сетей и запусти `update --replan` или `repair`
- `broken`: сначала `repair`, потом смотри, не был ли продвинут более сильный spare

```bash
sudo bash scripts/measure-stealth.sh run --save --output /tmp/measure.json
sudo xray-reality.sh update --replan --non-interactive --yes
```

## 4. клиентские артефакты выглядят устаревшими или отсутствуют

пересобери их из live managed state:

```bash
sudo xray-reality.sh repair --non-interactive --yes
```

это должно обновить:

- `clients.txt`
- `clients.json`
- `export/raw-xray/`
- `export/capabilities.json`
- `export/canary/`
- `policy.json`

## 5. `scripts/measure-stealth.sh run` не находит успешных variants для конфига

сначала сравни direct-варианты:

```bash
sudo bash scripts/measure-stealth.sh run --variants recommended,rescue --output /tmp/measure.json
jq . /tmp/measure.json
```

если оба direct-варианта слабы на проверяемой сети:

- посмотри в `status --verbose`, рекомендован ли `emergency`
- используй canary bundle или raw xray `emergency` config на клиентской стороне
- проверь, что клиент задаёт `xray.browser.dialer`

## 6. мне нужно протестировать `emergency`

`emergency` — field-only вариант.
используй raw xray artifact из `export/raw-xray/` или bundle из `export/canary/`.
пример env на клиенте:

```bash
env 'xray.browser.dialer=127.0.0.1:11050' xray run -config /path/to/emergency.json
```

не используй dotted `export`-форму в bash и других POSIX shell: dotted env names там не являются валидными shell-идентификаторами.

это нормально, что server-side post-action self-check не запускает `emergency`.

## 7. сломался вызов `scripts/measure-stealth.sh`

используй одну из поддерживаемых форм:

```bash
sudo bash scripts/measure-stealth.sh run --save
sudo bash scripts/measure-stealth.sh import --dir ./remote-canary-reports
sudo bash scripts/measure-stealth.sh compare --dir /var/lib/xray/measurements
sudo bash scripts/measure-stealth.sh prune --keep-last 30
sudo bash scripts/measure-stealth.sh summarize --dir /var/lib/xray/measurements
```

обычный вызов без subcommand эквивалентен `run`.

## 8. `migrate-stealth` завершился ошибкой

собери диагностику до случайных правок:

```bash
sudo xray-reality.sh diagnose
sudo xray-reality.sh rollback
```

дальше проверь:

- поддержку нужных xray features
- ошибки self-check
- field summary
- policy и artifact paths

## 9. импорт во внешний клиент не совпадает с raw xray config

обычно это намеренно.
для strongest-direct features canonical source of truth — raw xray json.
используй `export/capabilities.json`, чтобы увидеть, какие targets являются native, link-only или unsupported.
