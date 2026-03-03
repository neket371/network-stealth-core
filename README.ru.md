<h1 align="center">Network Stealth Core</h1>

<p align="center">
  Набор скриптов для установки и эксплуатации Xray Reality на Linux-серверах.
</p>

<p align="center">
  <a href="https://github.com/neket371/network-stealth-core/releases"><img alt="release" src="https://img.shields.io/badge/release-v4.2.1-0f766e"></a>
  <a href="LICENSE"><img alt="license" src="https://img.shields.io/badge/license-MIT-97ca00"></a>
  <a href="docs/ru/OPERATIONS.md"><img alt="platform" src="https://img.shields.io/badge/platform-ubuntu%2024.04-1d4ed8"></a>
  <a href="Makefile"><img alt="qa" src="https://img.shields.io/badge/qa-make%20ci-334155"></a>
</p>

<p align="center">
  <a href="README.md">English version</a> • <a href="docs/ru/INDEX.md">Документация (RU)</a> • <a href="docs/en/INDEX.md">Docs (EN)</a>
</p>

## Что это за проект

`Network Stealth Core` автоматизирует:

- развёртывание Xray Reality
- генерацию и сопровождение конфигурации
- операционные сценарии (`install`, `update`, `repair`, `rollback`, `uninstall`)
- экспорт клиентских артефактов

Проект публичный и предназначен для общего использования, без привязки к конкретному серверу.

## Официальный источник

Используйте только официальный репозиторий:

- `https://github.com/neket371/network-stealth-core`

Если команда взята из форка или зеркала, проверьте источник перед запуском.

## Быстрый старт

### Рекомендуемый способ: universal install

```bash
curl -fL https://raw.githubusercontent.com/neket371/network-stealth-core/main/xray-reality.sh -o /tmp/xray-reality.sh
sudo bash /tmp/xray-reality.sh install
```

### Альтернатива: one-line install

```bash
sudo bash <(curl -fsSL https://raw.githubusercontent.com/neket371/network-stealth-core/main/xray-reality.sh) install
```

Если появляется `/dev/fd/...: no such file or directory`, используйте universal install.

### Bootstrap с pin по commit

```bash
curl -fL https://raw.githubusercontent.com/neket371/network-stealth-core/main/xray-reality.sh -o /tmp/xray-reality.sh
sudo XRAY_REPO_COMMIT=<full_commit_sha> bash /tmp/xray-reality.sh install
```

### Выбор источника bootstrap

По умолчанию используется `main`:

```bash
curl -fL https://raw.githubusercontent.com/neket371/network-stealth-core/main/xray-reality.sh -o /tmp/xray-reality.sh
sudo bash /tmp/xray-reality.sh install
```

Чтобы брать последний релизный тег:

```bash
curl -fL https://raw.githubusercontent.com/neket371/network-stealth-core/main/xray-reality.sh -o /tmp/xray-reality.sh
sudo XRAY_BOOTSTRAP_DEFAULT_REF=release bash /tmp/xray-reality.sh install
```

## Карта команд

| Команда | Назначение |
|---|---|
| `install` | Полная установка |
| `add-clients [N]` | Добавляет `N` клиентских конфигов |
| `add-keys [N]` | Алиас `add-clients` |
| `update` | Обновление Xray core |
| `repair` | Сверка и восстановление service/firewall/artifacts |
| `status` | Сводка состояния |
| `logs [xray\|health\|all]` | Просмотр логов |
| `diagnose` | Диагностический снимок |
| `rollback [dir]` | Откат из бэкапа |
| `uninstall` | Полное удаление |
| `check-update` | Проверка обновлений |

## Профили и лимиты

| Профиль | Внутренний tier | Лимит конфигов | Примечание |
|---|---|---:|---|
| `ru` | `tier_ru` | 100 | Основной RU-пул |
| `ru-auto` | `tier_ru` | auto 5 | Быстрый RU-старт |
| `global-50` | `tier_global_ms10` | 10 | Глобальный пул (50 доменов) |
| `global-50-auto` | `tier_global_ms10` | auto 10 | Быстрый global-старт |
| `custom` | `custom` | 100 | Пользовательский набор |

Legacy-алиасы `global-ms10` и `global-ms10-auto` пока поддерживаются для обратной совместимости.

## Ключевые флаги

```bash
--domain-profile ru|ru-auto|global-50|global-50-auto|custom
--transport grpc|http2
--progress-mode auto|bar|plain|none
--require-minisign
--allow-no-systemd
--num-configs N
--start-port N
--server-ip IPV4 --server-ip6 IPV6
--yes --non-interactive
--verbose
```

## Карта документации

| Путь | Назначение |
|---|---|
| `docs/ru/INDEX.md` | Точка входа в документацию (RU) |
| `docs/en/INDEX.md` | Documentation entrypoint (EN) |
| `docs/ru/ARCHITECTURE.md` | Архитектура и контракты модулей |
| `docs/ru/OPERATIONS.md` | Эксплуатационный runbook |
| `docs/ru/FAQ.md` | Частые вопросы |
| `docs/ru/TROUBLESHOOTING.md` | Диагностика по симптомам |
| `docs/ru/COMMUNITY.md` | Комьюнити и правила общения |
| `docs/ru/ROADMAP.md` | Текущий вектор развития |
| `docs/ru/GLOSSARY.md` | Термины проекта |
| `docs/ru/CHANGELOG.md` | История релизов |
| `.github/CONTRIBUTING.ru.md` | Гайд для контрибьюторов (RU) |
| `.github/SECURITY.ru.md` | Политика безопасности (RU) |

## Безопасность

Основные меры:

- строгая валидация runtime-параметров
- allowlist для критичных загрузок
- проверка целостности артефактов (`sha256` и optional strict `minisign`)
- транзакционные записи и rollback
- ограниченный профиль `systemd` и непривилегированный runtime-пользователь

Подробности: [.github/SECURITY.ru.md](.github/SECURITY.ru.md).

## Поддерживаемая платформа

Основная и CI-валидируемая платформа:

- `ubuntu-24.04` (LTS)

Другие Linux-дистрибутивы могут работать, но не входят в текущий CI-контур.

## Проверки качества

```bash
make lint
make test
make release-check
make ci
```

Windows-утилиты:

```powershell
pwsh ./scripts/markdownlint.ps1
pwsh ./scripts/windows/run-validation.ps1
```

## Комьюнити

- Обсуждения: вкладка `GitHub Discussions`
- Баг-репорты и фичи: `GitHub Issues`
- Контакт: X (Twitter) [x.com/neket371](https://x.com/neket371)

## Лицензия

MIT License. См. [LICENSE](LICENSE).
