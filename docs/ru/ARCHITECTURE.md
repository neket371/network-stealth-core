# архитектура

## strongest-direct runtime контракт

текущая strongest-direct линия `v7` задаёт один managed direct baseline:

- protocol: `vless`
- security: `reality`
- transport: `xhttp`
- direct flow: `xtls-rprx-vision`
- для каждого конфига генерируется `vless encryption` и парный inbound `decryption`

managed client variants:

- `recommended` = `xhttp mode=auto`
- `rescue` = `xhttp mode=packet-up`
- `emergency` = `xhttp mode=stream-up + browser dialer`

`recommended` и `rescue` входят в post-action validation.
`emergency` — field-only вариант, который экспортируется как raw xray json плюс canary metadata.

## модель state

проект теперь разделяет managed policy и generated runtime-state.

| файл или путь | роль |
|---|---|
| `/etc/xray-reality/policy.json` | операторский source of truth для policy |
| `data/domains/catalog.json` | canonical metadata доменов и provider family |
| `/etc/xray/config.json` | живой server config xray |
| `/etc/xray-reality/config.env` | compatibility snapshot generated state |
| `/etc/xray/private/keys/clients.json` | инвентарь артефактов schema v3 |
| `/etc/xray/private/keys/export/raw-xray/` | canonical per-variant client configs |
| `/etc/xray/private/keys/export/canary/` | bundle для полевых тестов |
| `/var/lib/xray/self-check.json` | последний post-action verdict |
| `/var/lib/xray/self-check-history.ndjson` | недавняя история self-check |
| `/var/lib/xray/measurements/*.json` | сохранённые field reports |
| `/var/lib/xray/measurements/latest-summary.json` | aggregate field verdict и promotion hints |

## входы planner’а

решения planner’а строятся из трёх слоёв:

1. запрошенный domain profile из `policy.json`
2. canonical metadata в `data/domains/catalog.json`
3. runtime health и история измерений

для активного `xhttp`-planner path каталог теперь является основным источником metadata для canonical tier.
`domains.tiers` и `sni_pools.map` остаются fallback/compatibility-источниками, а `transport_endpoints.map`
используется только для legacy migration coverage.

`catalog.json` даёт planner’у структурированные поля:

- `tier`
- `provider_family`
- `region`
- candidate `ports`
- `priority`
- `risk`
- `sni_pool`

это позволяет не выжигать одну provider family и держать более сильные spare-конфиги.

## модель mutating-flow

все mutating-действия сохраняют одну общую форму:

1. загрузка policy, config и текущих артефактов
2. валидация входов и feature contract
3. backup managed state
4. сборка candidate config и артефактов
5. проверка через `xray -test`
6. атомарное применение
7. post-action self-check через canonical raw xray clients
8. запись verdict’ов и либо сохранение state, либо rollback

## граница миграции

`migrate-stealth` — единственный mutating-мост со старых managed-контрактов.
он обновляет и:

- legacy `grpc/http2` install
- pre-v7 xhttp install, который ещё не соответствует strongest-direct контракту

пока такая миграция не выполнена, `update`, `repair`, `add-clients` и `add-keys` fail-closed.

## модель клиентских артефактов

`clients.json` schema v3 хранит managed contract в machine-readable виде.

каждый config содержит:

- identity material вроде `uuid`, `short_id` и `public_key`
- selection metadata вроде `provider_family`, `primary_rank` и `recommended_variant`
- direct-contract поля вроде `transport`, `flow`, `vless_encryption` и `vless_decryption`
- per-variant outputs: raw xray files, ссылки там, где это честно, и browser-dialer requirements

raw xray json остаётся canonical artifact, потому что он без потерь выражает strongest-direct контракт.

## модель validation и promotion

есть два observation loop’а.

### post-action self-check

- использует generated raw xray client json
- сначала проверяет `recommended`, потом `rescue`
- пишет `/var/lib/xray/self-check.json`
- дописывает `/var/lib/xray/self-check-history.ndjson`
- запускает rollback, если оба direct-варианта не проходят

### field measurement

- использует `scripts/measure-stealth.sh run|import|compare|prune|summarize`
- сохраняет reports в `/var/lib/xray/measurements/`
- агрегирует latest summary для операторов и promotion logic
- может рекомендовать `emergency`, когда direct-варианты слишком слабы на реальных сетях

`repair` и `update --replan` могут продвинуть более сильный spare-config, если недавние self-check или field data это оправдывают.

## export layer

экспорты capability-driven:

- raw xray json: native
- `clients.txt` и `clients.json`: native
- v2rayn и nekoray: link-only там, где это честно
- sing-box и clash-meta: явно unsupported для strongest-direct контракта
- canary bundle: native field-testing surface

эта карта поддержки записывается в `export/capabilities.json`.

## карта модулей

| модуль | роль |
|---|---|
| `lib.sh` | dispatcher, validation, path safety и command contracts |
| `install.sh` | orchestration для install/update/repair/migrate |
| `config.sh` | orchestration сборки конфига поверх focused-модулей runtime-contract, runtime-apply и client-artifacts |
| `service.sh` | systemd, firewall, status, uninstall и cleanup |
| `health.sh` | входные точки диагностики и health |
| `modules/health/self_check.sh` | canonical engine post-action self-check |
| `modules/health/measurements.sh` | агрегация field reports и promotion hints |
| `modules/lib/policy.sh` | сериализация и загрузка managed policy |
| `modules/config/client_artifacts.sh` | тонкий loader клиентских артефактов для focused-модулей formats и state |
| `modules/config/client_formats.sh` | рендеринг client links/json/text, генерация raw-xray client export и server key file |
| `modules/config/client_state.sh` | нормализация clients.json, готовность self-check и helper’ы пересборки артефактов |
| `modules/config/domain_planner.sh` | выбор доменов и diversity-aware planning |
| `modules/config/runtime_profiles.sh` | выделение портов, генерация runtime-профилей и ключей |
| `modules/config/runtime_contract.sh` | генерация xray config-contract, feature gates, mux setup и helper’ы для vless encryption |
| `modules/config/runtime_apply.sh` | запуск `xray -test`, атомарное применение конфига и сохранение snapshot окружения |
| `export.sh` | генерация export’ов, capability matrix и canary bundle |

## дизайн-идея

проект намеренно предпочитает:

- меньше вопросов при установке
- один strongest safe default
- честные экспорты вместо фейковой совместимости
- fail-closed mutation на слабых контрактах
- operator visibility через сохранённые verdict’ы вместо догадок
