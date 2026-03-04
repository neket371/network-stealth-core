# Эксплуатационный runbook

Этот документ — операционная инструкция для **Network Stealth Core**.

## Точки входа установки

### Universal install (рекомендуется)

```bash
curl -fL https://raw.githubusercontent.com/neket371/network-stealth-core/ubuntu/xray-reality.sh -o /tmp/xray-reality.sh
sudo bash /tmp/xray-reality.sh install
```

### One-line install

```bash
sudo bash <(curl -fsSL https://raw.githubusercontent.com/neket371/network-stealth-core/ubuntu/xray-reality.sh) install
```

Если `/dev/fd` недоступен, используйте universal install.

Заметка миграции: legacy `main` поддерживается как временный alias на один релизный цикл; каноническая ветка — `ubuntu`.

## Runtime-допущения

- по умолчанию `install`, `update`, `repair` требуют рабочий `systemd`
- для ограниченных окружений есть `--allow-no-systemd`
- для fail-closed проверки подписи используйте `--require-minisign`

## Release sanity checklist (Ubuntu 24.04 LTS)

Поддерживаемый и валидируемый контур для этого checklist: **Ubuntu 24.04 LTS**.

### Scope lock

- документация не заявляет неподтверждённые ОС
- install-команды указывают на `https://github.com/neket371/network-stealth-core`
- в корне есть `LICENSE`

### Локальный quality gate

```bash
make ci
```

### Smoke на чистой VM

```bash
curl -fL https://raw.githubusercontent.com/neket371/network-stealth-core/ubuntu/xray-reality.sh -o /tmp/xray-reality.sh
sudo bash /tmp/xray-reality.sh install
sudo xray-reality.sh status
sudo xray -test -c /etc/xray/config.json
sudo xray-reality.sh add-clients 1 --non-interactive --yes
sudo xray-reality.sh update --non-interactive --yes
sudo xray-reality.sh repair --non-interactive --yes
sudo xray-reality.sh uninstall --non-interactive --yes
```

Ожидание:

- сервис активен после install/update/repair
- `xray -test` возвращает `0`
- после `add-clients` созданы клиентские артефакты
- `uninstall` удаляет управляемые файлы и systemd units

## Ежедневный health-check

```bash
sudo xray-reality.sh status
sudo systemctl status xray --no-pager
sudo journalctl -u xray -n 200 --no-pager
sudo xray-reality.sh diagnose
```

## Безопасный цикл сопровождения

### Обновление

```bash
sudo xray-reality.sh check-update
sudo xray-reality.sh update
sudo xray-reality.sh status
```

### Добавление клиентов

```bash
sudo xray-reality.sh add-clients 2
sudo xray-reality.sh status
```

Ожидаемые артефакты:

- `/etc/xray/private/keys/keys.txt`
- `/etc/xray/private/keys/clients.txt`
- `/etc/xray/private/keys/clients.json`
- `/etc/xray/private/keys/export/*`

## Матрица инцидентов

| Симптом | Действие | Проверка |
|---|---|---|
| `xray` не активен | `sudo systemctl restart xray` | `systemctl is-active xray` |
| не проходит `xray -test` | проверить `/etc/xray/config.json`, выполнить rollback | `xray -test` возвращает `0` |
| неуспешный update | `sudo xray-reality.sh rollback` | сервис активен, артефакты консистентны |
| нестабильные домены | проверить `/var/lib/xray/domain-health.json` | fail trend снижается |
| дрейф firewall | `sudo xray-reality.sh repair` | нужные порты открыты и слушаются |

## Rollback playbook

### Последняя сессия

```bash
sudo xray-reality.sh rollback
```

### Конкретная сессия

```bash
sudo xray-reality.sh rollback /var/backups/xray/<session-dir>
```

### Проверка после rollback

```bash
sudo xray-reality.sh status
sudo journalctl -u xray -n 100 --no-pager
```

## Runtime-параметры тюнинга

| Переменная | Эффект |
|---|---|
| `DOMAIN_HEALTH_PROBE_TIMEOUT` | timeout проверки домена |
| `DOMAIN_HEALTH_RATE_LIMIT_MS` | пауза между probe |
| `DOMAIN_HEALTH_MAX_PROBES` | максимум probe за цикл |
| `DOMAIN_QUARANTINE_FAIL_STREAK` | порог карантина |
| `DOMAIN_QUARANTINE_COOLDOWN_MIN` | длительность карантина |
| `PRIMARY_DOMAIN_MODE` | стратегия выбора primary домена |
| `PROGRESS_MODE` | `auto`, `bar`, `plain`, `none` |

## Uninstall

```bash
sudo xray-reality.sh uninstall --yes --non-interactive
```

После удаления:

- `id xray` должен завершиться ошибкой
- `/etc/xray`, `/etc/xray-reality`, `/usr/local/bin/xray` должны отсутствовать
- ранее занятые порты не должны слушаться

## Пакет для эскалации

Перед созданием issue подготовьте:

- `sudo xray-reality.sh diagnose`
- `sudo journalctl -u xray -n 500 --no-pager`
- `/etc/xray/config.json` с редактированными секретами
- `/etc/xray/private/keys/clients.json` при проблемах с артефактами
