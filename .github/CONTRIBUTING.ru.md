# Вклад в проект

Спасибо за вклад в **Network Stealth Core**.

Этот документ описывает базовый рабочий процесс, который нужен для безопасных и проверяемых изменений.

## Базовые правила

- коммиты должны быть узкими и понятными
- rollback и security-поведение нельзя ломать
- изменение функционала должно сопровождаться тестами и обновлением документации
- несовместимые изменения без явной фиксации недопустимы

## Локальная подготовка

### Что нужно

- Linux или WSL
- Bash 4.3+
- Git
- `shellcheck`, `shfmt`, `bats`, `actionlint`
- Node.js (или `npx`) для markdown lint

### Клонирование и upstream

```bash
git clone https://github.com/YOUR_USERNAME/network-stealth-core.git
cd network-stealth-core
git remote add upstream https://github.com/neket371/network-stealth-core.git
git fetch upstream
```

## Обязательные проверки

Перед `push`:

```bash
make lint
make test
make release-check
make ci
```

Прямые эквиваленты:

```bash
bash tests/lint.sh
bats tests/bats
bash scripts/check-release-consistency.sh
```

## Политика сложности shell-кода

В репозитории действует поэтапный complexity-gate для shell.

- лимит stage 3: файл <= 2800 строк
- лимит stage 3: функция <= 320 строк

Если `lib.sh` растёт, лимиты не ослабляются. Логику нужно выносить в `modules/lib/*.sh` без изменения runtime-контрактов.

## Стандарты shell-кода

1. код должен быть безопасен под `set -euo pipefail`
2. переменные должны быть корректно экранированы
3. не использовать `eval` для пользовательского ввода
4. использовать общие валидаторы и утилиты
5. критичные файлы писать атомарно
6. мутации обязаны оставаться rollback-safe

## Риски повышенного внимания

- bootstrap и download verification
- права доступа и пути
- генерация unit-файлов systemd
- применение и rollback firewall
- backup stack и cleanup traps

## Checklist для PR

- [ ] локальные проверки зелёные (`make ci`)
- [ ] изменённое поведение покрыто тестами
- [ ] пользовательская документация обновлена
- [ ] `docs/en/CHANGELOG.md` дополнен при необходимости
- [ ] секреты не попали в коммит
- [ ] rollback и security-контракты сохранены

## Обновление документации

Обычно затрагиваются:

- `README.md`
- `README.ru.md`
- `docs/en/*.md`
- `docs/ru/*.md`
- `.github/CONTRIBUTING.md`
- `.github/SECURITY.md`

## Сообщение об уязвимостях

Публичные issue для уязвимостей не создаются.

Используйте private vulnerability reporting в GitHub.  
См. [.github/SECURITY.ru.md](SECURITY.ru.md).
