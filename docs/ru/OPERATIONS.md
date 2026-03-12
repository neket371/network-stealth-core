# operations

## модель оператора по умолчанию

обычные операции предполагают один managed node на `ubuntu-24.04`.
normal install path остаётся opinionated и минимальным.

strongest-direct defaults:

- profile: `ru-auto`
- transport: `xhttp`
- stack: `vless + reality + xhttp + vless encryption + xtls-rprx-vision`
- варианты: `recommended`, `rescue`, `emergency`
- self-check: включён по умолчанию
- measurement storage: работает по умолчанию, когда ты сохраняешь reports

## установка

### normal path

```bash
sudo xray-reality.sh install
```

в обычном интерактивном режиме normal path всё равно спрашивает число конфигов.
для scripted-установок используй:

```bash
sudo xray-reality.sh install --non-interactive --yes
```

что должно произойти:

- strongest-direct стек собирается без вопросов про transport
- пишется `policy.json`
- генерируются клиентские артефакты schema v3
- в интерактивном терминале после install сразу печатаются основная и запасная `vless`-ссылки, а детали остаются в `clients-links.txt`
- запускается post-action self-check для `recommended`, затем `rescue`, если нужно
- экспортируются raw xray configs, capability matrix и canary bundle

### manual compatibility path

```bash
sudo xray-reality.sh install --advanced
```

используй это только если тебе сознательно нужен ручной prompt выбора профиля доменов.

## миграция

запускай на:

- managed legacy `grpc/http2` install
- managed xhttp install, созданных до strongest-direct контракта

```bash
sudo xray-reality.sh migrate-stealth --non-interactive --yes
```

после миграции проверь:

```bash
sudo xray-reality.sh status --verbose
sudo xray-reality.sh diagnose
```

## day-2 действия

### добавить клиентов

```bash
sudo xray-reality.sh add-clients 2 --non-interactive --yes
```

это пересобирает managed artifacts из live config и сохраняет strongest-direct контракт.

### repair

```bash
sudo xray-reality.sh repair --non-interactive --yes
```

`repair` теперь также:

- пересобирает `clients.txt`, `clients-links.txt`, `clients.json`, raw xray exports, capability matrix и canary bundle
- обновляет `policy.json`
- может повысить более сильный spare-config, если недавние verdict’ы показывают, что текущий primary слабый

### update

```bash
sudo xray-reality.sh update --non-interactive --yes
```

принудительно пересчитать приоритеты по недавним verdict’ам:

```bash
sudo xray-reality.sh update --replan --non-interactive --yes
```

используй `--replan` после сохранения свежих reports с реальных сетей.

## статус и диагностика

### краткий статус

```bash
sudo xray-reality.sh status
```

### подробный статус

```bash
sudo xray-reality.sh status --verbose
```

в подробном статусе должны быть:

- детали strongest-direct контракта
- последний self-check verdict
- последний verdict полевых измерений
- текущий primary config
- лучший spare config
- нужна ли рекомендация `emergency`

### полная диагностика

```bash
sudo xray-reality.sh diagnose
```

`diagnose` теперь включает policy, историю self-check и measurement summary.

## workflow измерений

### запустить локальное measurement и сохранить его

```bash
sudo bash scripts/measure-stealth.sh run \
  --save \
  --network-tag home \
  --provider rostelecom \
  --region moscow \
  --output /tmp/measure-home.json
```

### сравнить сохранённые reports

```bash
sudo bash scripts/measure-stealth.sh compare \
  --dir /var/lib/xray/measurements \
  --output /tmp/measure-compare.json
```

### импортировать удалённые canary-reports в managed storage

```bash
sudo bash scripts/measure-stealth.sh import \
  --dir ./remote-canary-reports \
  --output /tmp/measure-import.json
```

### получить актуальную summary-картину

```bash
sudo bash scripts/measure-stealth.sh summarize \
  --dir /var/lib/xray/measurements \
  --output /tmp/measure-summary.json
```

### подчистить старые сохранённые reports

```bash
sudo bash scripts/measure-stealth.sh prune \
  --keep-last 30 \
  --output /tmp/measure-prune.json
```

обычный вызов без subcommand ведёт себя как `run`.

## smoke для сопровождающих и busy-host validation

на этом обычная боевая эксплуатация заканчивается.
если ты сопровождаешь репозиторий и тебе нужна изолированная smoke-проверка или busy-host lifecycle validation, смотри:

- [MAINTAINER-LAB.md](MAINTAINER-LAB.md)
- [.github/CONTRIBUTING.ru.md](../../.github/CONTRIBUTING.ru.md)

## canary bundle

managed exports теперь включают:

- `export/canary/manifest.json`
- `export/canary/raw-xray/*.json`
- `export/canary/measure-linux.sh`
- `export/canary/measure-windows.ps1`

используй canary bundle, когда нужно тестировать узел с другой машины или сети.
для варианта `emergency` задай browser dialer env на клиентской стороне:

```bash
export xray.browser.dialer=127.0.0.1:11050
```

## важные файлы

| путь | смысл |
|---|---|
| `/etc/xray-reality/policy.json` | managed policy |
| `/etc/xray-reality/config.env` | generated env snapshot |
| `/etc/xray/config.json` | live xray config |
| `/etc/xray/private/keys/clients.txt` | человекочитаемое summary по конфигам |
| `/etc/xray/private/keys/clients-links.txt` | быстрые vless-ссылки для копирования |
| `/etc/xray/private/keys/clients.json` | клиентский инвентарь schema v3 |
| `/etc/xray/private/keys/export/capabilities.json` | карта поддержки export-target |
| `/var/lib/xray/self-check.json` | последний self-check verdict |
| `/var/lib/xray/self-check-history.ndjson` | недавняя история self-check |
| `/var/lib/xray/measurements/latest-summary.json` | последняя field-summary |

## rollback и uninstall

### rollback

```bash
sudo xray-reality.sh rollback
```

или восстановление конкретной session:

```bash
sudo xray-reality.sh rollback /var/backups/xray/<session-dir>
```

### uninstall

```bash
sudo xray-reality.sh uninstall --non-interactive --yes
```

managed uninstall удаляет вместе policy, историю self-check, measurement summary и generated export artifacts.

## практический цикл оператора

1. установи или мигрируй узел на strongest-direct контракт
2. проверь `status --verbose`
3. сохрани несколько measurements с реальных сетей
4. запусти `update --replan` или `repair`, если field-summary указывает на более сильный spare
5. используй `emergency` только когда direct-вариантов недостаточно на проверенной сети
