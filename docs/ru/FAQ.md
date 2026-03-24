# faq

## почему обычный install такой жёсткий по умолчанию?

проект оптимизирован сразу под две вещи:

- почти без вопросов при установке
- самый сильный безопасный дефолт для обхода dpi в рф

поэтому обычный путь не задаёт лишних вопросов про transport и профиль доменов.

## какой bootstrap-способ брать на реальном сервере?

предпочитай фиксированный bootstrap по коммиту с `XRAY_REPO_COMMIT=<full_commit_sha>`.
если нужен именно опубликованный релиз, а не текущая плавающая ветка, используй путь с фиксированным тегом из readme и `XRAY_REPO_REF=v<release-tag>`.
одного tag url для wrapper недостаточно: bootstrap clone сам по себе не становится зафиксированным.
плавающий raw-bootstrap оставлен для удобства, но не должен быть первым production-like путём.

## когда использовать `install --advanced`?

только когда тебе сознательно нужен ручной выбор профиля доменов.
обычный интерактивный install и так спрашивает число конфигов.

## почему изменяющие команды блокируются на старых установках?

потому что `update`, `repair`, `add-clients` и `add-keys` не должны молча оставлять более слабый managed-контракт.
запусти:

```bash
sudo xray-reality.sh migrate-stealth --non-interactive --yes
```

## что именно переводит `migrate-stealth`?

он обновляет и:

- управляемые legacy `grpc/http2` install
- управляемые xhttp install, у которых ещё нет strongest-direct контракта v7

## почему канонический клиентский артефакт — это raw xray json?

потому что он без потерь выражает strongest-direct контракт:

- xhttp modes
- generated vless encryption
- `xtls-rprx-vision`
- требования browser dialer для `emergency`

ссылки генерируются только там, где они остаются честными.

## для чего нужен вариант `emergency`?

`emergency` — это последний полевой запасной вариант:

- `xhttp mode=stream-up`
- требует browser dialer
- экспортируется только как raw xray
- не участвует в post-action server self-check

## почему sing-box и clash-meta помечены как unsupported?

потому что проект не хочет генерировать degraded templates, которые искажают strongest-direct контракт.
если нужен точный managed behavior, используй raw xray json.

## зачем нужен `policy.json`?

`/etc/xray-reality/policy.json` хранит операторскую политику отдельно от сгенерированного runtime-state.
там лежат:

- профиль доменов и tier
- настройки self-check
- настройки измерений
- настройки update и replan
- metadata direct-контракта

## что делает `scripts/measure-stealth.sh`?

он переиспользует тот же probe-engine, что и runtime self-check, и добавляет workflow для отчётов:

- `run`
- `import`
- `compare`
- `prune`
- `summarize`

сохранённые отчёты питают сводку измерений, которая используется в `status --verbose`, `diagnose`, `repair` и `update --replan`.

## как проверять проект на занятом хосте?

используй maintainer-only lab docs и выбирай самый лёгкий слой под задачу:

- `make lab-smoke` для безопасного первого smoke в изолированном контейнере
- `make vm-lab-smoke` для полного prod-like `systemd` lifecycle в изолированной vm
- `make vm-proof-pack`, если нужен shareable bundle из этого vm-lab run

документация:

- [MAINTAINER-LAB.md](MAINTAINER-LAB.md)
- [.github/CONTRIBUTING.ru.md](../../.github/CONTRIBUTING.ru.md)

## для чего нужен canary bundle?

это переносимая поверхность полевых тестов в `export/canary/`.
используй её, когда с другой машины или из другой сети нужно проверить generated variants, особенно `emergency`.

## какая версия xray ожидается?

strongest-direct клиентский контракт объявляет minimum xray version.
сейчас managed artifacts фиксируют `25.9.5` как минимальный baseline для клиента и core.
если локальный xray binary не поддерживает нужные возможности, действие fail-closed.
