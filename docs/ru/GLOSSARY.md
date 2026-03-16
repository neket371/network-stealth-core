# глоссарий

## strongest-direct install

default install-контракт: минимум prompt’ов, strongest safe direct stack и canonical raw exports.

## advanced mode

`install --advanced` — явный manual compatibility flow, который включает prompt выбора профиля доменов.

## stealth contract version

версия managed runtime-контракта, которая записывается в policy и client artifacts.
в текущей strongest-direct линии `v7` она обозначает managed strongest-direct baseline.

## policy.json

`/etc/xray-reality/policy.json` — source of truth для managed policy.

## domain catalog

`data/domains/catalog.json` — canonical набор metadata, который использует domain planner.

## provider family

label planner’а, который помогает держать конфиги диверсифицированными по разным domain cohorts.

## client variant

client-профиль внутри `clients.json` `variants[]` для конкретного конфига.

## recommended variant

основной xhttp client artifact с `mode=auto`.

## rescue variant

compatibility fallback xhttp artifact с `mode=packet-up`.

## emergency variant

browser-assisted field tier с `mode=stream-up`; экспортируется только как raw xray.

## raw xray export

canonical per-variant client json в `export/raw-xray/`.

## capability matrix

`export/capabilities.json` — machine-readable карта поддержки generated export-target.

## canary bundle

`export/canary/` — переносимый bundle для полевых тестов с других машин или сетей.

## self-check state

`/var/lib/xray/self-check.json` — последний post-action verdict.

## self-check history

`/var/lib/xray/self-check-history.ndjson` — недавняя история post-action verdict’ов.

## measurement harness

`scripts/measure-stealth.sh` — локальный инструмент для field measurements `run`, `import`, `compare`, `prune` и `summarize`.

## measurement summary

`/var/lib/xray/measurements/latest-summary.json` — агрегированный field verdict для operator surface и promotion logic.

## replan

`update --replan` — пересборка, которая позволяет recent self-check и field data влиять на приоритет конфигов.

## xtls-rprx-vision

direct flow, который использует strongest-direct контракт.

## vless encryption

generated outbound-side encryption metadata, парная inbound `decryption` в strongest-direct контракте.
