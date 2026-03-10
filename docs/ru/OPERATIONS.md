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

используй это только если тебе сознательно нужны ручные prompt’ы для профиля и числа конфигов.

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

## host-safe lab smoke на занятом сервере

если на хосте уже есть production-сервисы, держи smoke-тесты изолированными:

```bash
make lab-smoke
```

или запускай скрипты явно:

```bash
bash scripts/lab/prepare-host-safe-smoke.sh
bash scripts/lab/run-container-smoke.sh
bash scripts/lab/collect-container-artifacts.sh
```

этот flow ожидает уже существующий `docker` или `podman`, не публикует container ports, форсирует `c.utf-8` внутри smoke-контейнера и складывает логи в host-safe lab directory, а не в дерево репозитория.

## полный vm-lab lifecycle на занятом сервере

если нужен настоящий `systemd` lifecycle без захода в namespace занятого хоста, используй kvm vm-lab:

```bash
make vm-lab-prepare
make vm-lab-smoke
```

или запускай скрипты напрямую:

```bash
bash scripts/lab/prepare-vm-smoke.sh
bash scripts/lab/run-vm-lifecycle-smoke.sh
bash scripts/lab/enter-vm-smoke.sh
```

этот flow:

- требует `kvm`, `qemu-system-x86_64`, `qemu-img`, `cloud-localds` и `ssh`
- один раз скачивает ubuntu 24.04 cloud image в lab-директорию
- поднимает изолированного гостя с настоящим `systemd`
- пробрасывает на loopback хоста только гостевой ssh
- копирует в гостя текущий репозиторий
- гоняет там полный nightly lifecycle smoke: `install`, `add-clients`, `repair`, `update`, `rollback`, `status`, `uninstall`
- возвращает guest-логи обратно в vm-lab log directory

дефолтные guest-side значения:

- `start_port=24440`
- `initial_configs=1`
- `add_configs=1`
- `e2e_server_ip=10.0.2.15`
- `e2e_domain_check=false`
- `e2e_skip_reality_check=false`
- `xray_custom_domains=vk.com,yoomoney.ru,cdek.ru`
- `install_version=latest stable`
- `update_version=install_version`

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
