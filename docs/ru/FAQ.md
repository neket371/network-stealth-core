# faq

## почему install такой opinionated?

проект оптимизирован сразу под две вещи:

- почти без вопросов при установке
- самый сильный безопасный дефолт для обхода dpi в рф

поэтому normal path убирает prompt’ы про transport и profile.

## какой bootstrap path брать на реальном сервере?

предпочитай pinned bootstrap path с `XRAY_REPO_COMMIT=<full_commit_sha>`.
если нужен именно опубликованный релиз, а не текущая плавающая ветка, используй tag-pinned путь из readme с `XRAY_REPO_REF=v<release-tag>`.
одного tag url для wrapper недостаточно: bootstrap clone сам по себе не становится pinned.
floating raw bootstrap оставлен для удобства, но не должен быть первым production-like путём.

## когда использовать `install --advanced`?

только когда тебе сознательно нужен ручной prompt выбора профиля доменов.
обычный интерактивный install и так спрашивает число конфигов.

## почему mutating-действия блокируются на старых install?

потому что `update`, `repair`, `add-clients` и `add-keys` не должны молча оставлять более слабый managed-контракт.
запусти:

```bash
sudo xray-reality.sh migrate-stealth --non-interactive --yes
```

## что именно обновляет `migrate-stealth`?

он обновляет и:

- managed legacy `grpc/http2` install
- managed xhttp install, у которых ещё нет strongest-direct контракта v7

## почему canonical client artifact — это raw xray json?

потому что он без потерь выражает strongest-direct контракт:

- xhttp modes
- generated vless encryption
- `xtls-rprx-vision`
- browser-dialer requirements для `emergency`

ссылки генерируются только там, где они остаются честными.

## для чего нужен вариант `emergency`?

`emergency` — это last-resort field tier:

- `xhttp mode=stream-up`
- требует browser dialer
- экспортируется только как raw xray
- не участвует в post-action server self-check

## почему sing-box и clash-meta помечены как unsupported?

потому что проект не хочет генерировать degraded templates, которые искажают strongest-direct контракт.
если нужен точный managed behavior, используй raw xray json.

## зачем нужен `policy.json`?

`/etc/xray-reality/policy.json` хранит операторскую policy отдельно от generated runtime-state.
там лежат:

- domain profile и tier
- self-check settings
- measurement settings
- update и replan settings
- metadata direct-контракта

## что делает `scripts/measure-stealth.sh`?

он переиспользует тот же probe-engine, что и runtime self-check, и добавляет workflow для reports:

- `run`
- `import`
- `compare`
- `prune`
- `summarize`

сохранённые reports питают measurement summary, который используется в `status --verbose`, `diagnose`, `repair` и `update --replan`.

## как прогонять smoke-тест на занятом хосте?

смотри отдельную документацию для сопровождающих:

- [MAINTAINER-LAB.md](MAINTAINER-LAB.md)
- [.github/CONTRIBUTING.ru.md](../../.github/CONTRIBUTING.ru.md)

## как прогнать полный `systemd` lifecycle на занятом сервере?

смотри отдельную документацию для сопровождающих:

- [MAINTAINER-LAB.md](MAINTAINER-LAB.md)
- [.github/CONTRIBUTING.ru.md](../../.github/CONTRIBUTING.ru.md)

## для чего нужен canary bundle?

это переносимая поверхность полевых тестов в `export/canary/`.
используй её, когда generated variants нужно проверять с другой машины или другой сети, особенно `emergency`.

## какая версия xray ожидается?

strongest-direct клиентский контракт объявляет minimum xray version.
сейчас managed artifacts фиксируют `25.9.5` как минимальный baseline для клиента/core.
если локальный xray binary не поддерживает нужные возможности, действие fail-closed.
