# changelog

здесь фиксируются изменения **network stealth core**.

формат: [keep a changelog](https://keepachangelog.com/en/1.0.0/)  
версионирование: [semantic versioning](https://semver.org/spec/v2.0.0.html)

## [unreleased]

## [7.10.3] - 2026-03-28

### Fixed
- measurement и self-check storage helpers больше не делают `chmod` на уже существующих custom parent-directory, так что override state-файлов больше не может тихо увести права у shared system path
- managed geo registry теперь следует только активному контракту директории для GeoIP/GeoSite и больше не считает `/usr/local/share/xray` проектным каталогом по умолчанию
- custom URL для GeoIP/GeoSite и checksum теперь переживают и `config.env`, и policy round-trip, так что сохранённый runtime state больше не откатывается молча к default origin
- wrapper completeness validation теперь отслеживает актуальные health runtime modules и `measurements_aggregate.jq`, поэтому неполное custom/pinned tree падает до позднего runtime source

## [7.10.2] - 2026-03-27

### Fixed
- новые bats-гарды для release/runtime contract вынесены в `tests/bats/release_contracts.bats`, так что `tests/bats/unit.bats` снова укладывается в stage-3 complexity budget и hosted `CI` на линии `v7.10.x` снова зелёный

## [7.10.1] - 2026-03-27

### Changed
- self-sync wrapper’а теперь публикует `XRAY_DATA_DIR` как чистый managed mirror, так что stale-файлы, уже удалённые из source tree, больше не переживают последующие апдейты внутри managed wrapper tree
- GeoIP/GeoSite refresh перенесён в обычный runtime-path `update`, а generated auto-update script ужат до тонкой обёртки, которая просто запускает `xray-reality.sh update --non-interactive`
- битый сохранённый measurement summary теперь показывается как явный degraded operator state, а не схлопывается в безликий `unknown`

### Fixed
- custom URL для GeoIP/GeoSite и checksum теперь обязаны проходить `DOWNLOAD_HOST_ALLOWLIST`, так что geo-refresh path больше не доверяет произвольным `https` origin с self-consistent checksum
- `MEASUREMENTS_ROTATION_STATE_FILE` доведён до полного runtime-contract через config loading, policy loading, path validation, destructive guard и persistence в `config.env`
- measurement summary/report persistence и explicit `measure-stealth.sh --output` writes переведены на atomic publish, поэтому обрезанный JSON больше не деградирует decision layer тихо

## [7.10.0] - 2026-03-27

### Changed
- добавлен persisted rotation-state contract в `/var/lib/xray/measurements/rotation-state.json`, чтобы weak-primary streak, cooldown family/domain и last promotion context переживали `repair` и `update --replan`
- `doctor`, `status --verbose`, `diagnose`, `repair`, `update --replan` и `scripts/measure-stealth.sh summarize` переведены на один общий operator decision layer с одинаковыми verdict names, rotation state, cooldown reason и semantics следующего действия
- `repair` и `update --replan` теперь используют один cooldown-aware promotion engine вместо раздельных spare-promotion веток

### Fixed
- path для measurement rotation-state теперь выводится из активного summary/storage path, если measurements перенаправлены, поэтому nested import и изолированные тестовые прогоны больше не шумят permission-ошибками из `/var/lib/xray/measurements`
- overlay field-summary исправлен так, чтобы JSON-пейлоады больше не портились лишней `}` из небезопасного shell default expansion

## [7.9.1] - 2026-03-27

### Changed
- повторно выпускает tranche с операторским `doctor` и анти-корреляцией planner уже на реальном кодовом коммите после того, как `v7.9.0` ушёл как release-prep-only тег
- добавлена read-only команда `doctor`, которая собирает runtime state, последний self-check, сохранённую field recommendation и следующее операторское действие в один экран
- spare ordering теперь уводится от family текущего primary, когда сохранённый field summary уже рекомендует rotation, так что `build_domain_plan` держит более широкое разделение family после primary
- normal/legacy transport normalization вынесена в общий legacy transport contract вместо разрозненных `grpc/http2/h2` case-веток по hot-path модулям

## [7.9.0] - 2026-03-27

### Changed
- добавлен read-only `doctor`, который собирает в один экран runtime state, последний self-check, сохранённую field recommendation и следующее операторское действие
- ordering запасных конфигов теперь сильнее уходит от provider family текущего primary, когда сохранённый field summary уже рекомендует rotation, так что `build_domain_plan` держит более широкое family-разделение после primary-слота
- нормализация normal/legacy transport перенесена в общий legacy transport contract вместо разбросанных `grpc/http2/h2` case-блоков по hot-path модулям

## [7.8.1] - 2026-03-26

### Changed
- fix: split measurement aggregate jq program (bfdbad3)

## [7.8.0] - 2026-03-26

### Changed
- `scripts/measure-stealth.sh import` теперь проходит по nested report tree, игнорирует не-report JSON и дедуплицирует уже импортированные отчёты по content hash вместо того, чтобы валить весь remote-canary batch на одном stray manifest или копии файла
- operator-facing field summary расширен provider-family diversity, long-term trend review, provider-family penalties и более богатыми деталями по current primary / best spare, которые теперь одинаково читают `summarize`, `status --verbose`, `diagnose`, `repair` и `update --replan`
- domain planner теперь смещает выбор в сторону provider family с меньшим накопленным полевым penalty, но при этом сохраняет strongest-direct diversity и priority invariants

### Fixed
- сохраняемые measurement reports теперь несут config-level metadata `domain`, `provider_family` и `primary_rank`, поэтому импортированные field data могут честно влиять на family-aware summary и planner decisions без опоры на случайный runtime state

## [7.7.0] - 2026-03-26

### Changed
- сохранённые field measurements теперь собираются в decision-grade operator summary: с quality coverage, reason для recommendation, статистикой current primary, статистикой лучшего spare и более богатым promotion metadata, который переиспользуют `status --verbose`, `diagnose`, `repair`, `update --replan` и `scripts/measure-stealth.sh summarize`

### Fixed
- при отсутствии сохранённых reports field summary теперь честно показывает `unknown`, а не намекает на деградацию; рекомендация в этом состоянии мягко уходит в `collect-more-data`

## [7.6.3] - 2026-03-26

### Fixed
- два uninstall bats-assert теперь смотрят на success-marker, а не на полное точное совпадение stdout, поэтому hosted linux runner больше не падает из-за incidental control chars или лишнего wrapper-output при том же целевом поведении uninstall

## [7.6.2] - 2026-03-26

### Fixed
- два uninstall bats-гарда теперь проверяют финальный success-marker вместо полного точного совпадения stdout, поэтому hosted linux runner больше не краснит suite на incidental extra output при неизменном uninstall-поведении

## [7.6.1] - 2026-03-25

### Fixed
- тест security release surface теперь выводит supported/unsupported version lines из `SCRIPT_VERSION`, поэтому release и CI больше не падают на stale minor после выпуска нового релиза

## [7.6.0] - 2026-03-25

### Changed
- введён общий registry managed-артефактов и exact-scope destructive path contract: теперь `install`, `update`, `repair`, `rollback` и `uninstall` опираются на один и тот же список managed файлов, директорий, логов и unit-артефактов вместо параллельных cleanup-списков
- `install_self` переведён на staged whole-tree publish, поэтому managed wrapper tree внутри `XRAY_DATA_DIR` больше не может остаться в смешанном состоянии root-файлов при прерывании self-sync

### Fixed
- destructive path validation сужена до реальных project-сегментов, но при этом сохраняет проход для canonical managed system paths и safe mirrored non-system paths из disposable lab и nested custom test tree
- detection managed residue в uninstall теперь учитывает и managed logs с auxiliary artifacts, поэтому `uninstall` больше не выходит раньше времени с `already removed`, когда residue ещё лежит на диске

## [7.5.18] - 2026-03-25

### Fixed
- `scripts/lab/prepare-vm-smoke.sh` теперь публикует ubuntu cloud image только после проверки непустого `.part`-файла и чистит stale temp при ошибке вместо хрупкого `mv`
- `scripts/lab/guest-vm-release-smoke.sh` теперь проверяет реальный quoted-контракт `XRAY_DOMAINS_FILE="..."` и больше не падает ложно на корректном managed `config.env`

## [7.5.17] - 2026-03-24

### Changed
- legacy grpc/mux compatibility defaults вынесены в отдельный shared contract module вместо дублирования этого слоя в главном globals-контуре
- `data/domains/catalog.json` теперь жёстко считается каноном для committed fallback-файлов `domains.tiers` и `sni_pools.map` через отдельный generator + consistency check

### Fixed
- build config и add-clients больше не зависят от скрытых `PROFILE_*` global side-effects: runtime-profile значения теперь передаются явно
- contract-level bats coverage вынесена из `tests/bats/unit.bats`, а новый generator/module подключены в smoke и regression-проверки для generated domain fallbacks
- убраны дубли в busy-host faq, смягчены формулировки maintainer-проверок и приглажен ru-текст в maintainer/docs без изменения продуктового контракта
- trust-check для `XRAY_ALLOW_CUSTOM_DATA_DIR=true` ужесточён: sourced shell-файлы и symlink-target'ы теперь обязаны оставаться внутри trusted tree с безопасными правами, а client-artifact rollback теперь fail-closed на битом publish-manifest

## [7.5.16] - 2026-03-22

### Fixed
- download-failure e2e smoke теперь проверяет новый fail-closed текст про официальный `.dgst`, а не старую формулировку про mirror-only SHA256 path

## [7.5.15] - 2026-03-22

### Changed
- managed version contract defaults вынесены в один shared helper, а `XRAY_FAILURE_PROOF_DIR` теперь явно оформлен как maintainer-only debug hook вместо неявной env-ручки

### Fixed
- из generated inbound JSON убран дублирующийся серверный `settings.flow`, а в server root config больше не пишется нестандартный `version.min`
- `systemctl_uninstall_bounded` теперь реально передаёт все requested unit’ы и больше не теряет хвост аргументов при uninstall cleanup
- SNI pool для `googleapis.com` дедуплицирован, а для catalog, tiers и fallback map добавлен отдельный consistency gate
- rebuild/self-check helper’ы переведены с скрытой multi-output-сцепки на явный контракт, а repeated `jq`-нагрузка в client artifact rendering/inventory assembly снижена
- проверка Xray release теперь по умолчанию предпочитает official digest/signature sidecars, а mirror digest fallback остаётся только в explicit insecure path

## [7.5.14] - 2026-03-22

### Changed
- это был только release-prep tag; actual validated code changes вышли уже в `7.5.15`

### Fixed
- в тег попали только release-метаданные, а сам проверенный code-pass в него не вошёл

## [7.5.13] - 2026-03-21

### Changed
- strongest-direct DNS-контракт теперь явно задокументирован как намеренно IPv4-first на dual-stack хостах, чтобы `queryStrategy: UseIPv4` не выглядела случайным рассинхроном

### Fixed
- container `HEALTHCHECK` усилен: теперь он проверяет bootability wrapper’а, а не просто наличие главных файлов

## [7.5.12] - 2026-03-21

### Changed
- guard-тесты для service и `atomic_write` вынесены из `tests/bats/unit.bats` в тематический bats-набор, чтобы stage-3 complexity gate снова оставался честным без ослабления лимита размера файла

## [7.5.11] - 2026-03-21

### Fixed
- `check-update` теперь деградирует с явным warning вместо crash, если в degraded service-shell context недоступен helper сравнения версий
- `atomic_write` больше не считает весь `/usr/local` разрешённым: доступ сужен до managed subpaths, и посторонние `/usr/local/*` пути больше не проходят неявно

## [7.5.10] - 2026-03-21

### Fixed
- в follow-up patch release реально отгружен queued набор export, транзакционной публикации клиентских артефактов, CLI parser и local QA hardening-правок, чтобы tagged tree наконец совпадало с проверенным fix-pass

## [7.5.9] - 2026-03-21

### Fixed
- в canary и capability export paths теперь сначала создаются parent-директории и только потом вызывается `mktemp`, поэтому first-run export больше не падает на отсутствующем output-каталоге
- публикация клиентских артефактов стала транзакционной: `clients.json`, текстовые экспорты и `raw-xray` теперь сначала собираются в staging, а потом атомарно публикуются в рабочие пути
- CLI parser теперь режет missing values у long-options вместо того, чтобы тихо съедать следующий флаг как аргумент
- в локальный quality gate добавлены обязательные проверки для `tests/bats/*.bats` и PowerShell syntax, а coverage complexity-check расширен на `.bats` и `.ps1`
- `check-dead-functions.sh` оптимизирован: вместо повторного полного сканирования репозитория для каждой функции теперь используется shared candidate scan
- transport endpoint file contract helper дедуплицирован, а крупные CLI/test hotspots разрезаны на более мелкие phase-helpers и тематические bats-файлы

## [7.5.8] - 2026-03-20

### Fixed
- export-helpers теперь дочищают временные файлы при падении `jq` или schema validation и не оставляют orphan `.tmp.*` артефакты
- `repair` теперь завершается fail-closed, если деградирует rebuild клиентских артефактов или подготовка self-check артефактов, вместо вводящего в заблуждение успешного финала
- strict bootstrap pin теперь выдаёт более честную диагностику: при провале auto-pin объясняется fallback на ручной `XRAY_REPO_COMMIT` и вероятная проблема с `git ls-remote` / сетью
- при promotion primary теперь пропускаются пустые optional runtime-массивы, поэтому `PORTS_V6=()` больше не валит корректный reorder
- сборка `inbounds` в build/rebuild теперь делается батчем, без повторного перепарсивания всего JSON-массива через `jq` на каждой итерации

## [7.5.7] - 2026-03-20

### Fixed
- generated `xray-health.sh` больше не падает на timeout блокировки fail-count файла: вместо silent abort теперь пишутся явные предупреждения
- `diagnose` теперь собирает вывод в subshell, поэтому временный `set +e` больше не может протечь в вызывающий shell
- `status --verbose` теперь деградирует в raw transport labels, если shared helper-функции недоступны
- явные legacy-override значения `TRANSPORT` для обычных v7 actions теперь режутся раньше в runtime override layer; `migrate-stealth` по-прежнему допускается
- read-only и cleanup actions теперь сохраняют persisted legacy `TRANSPORT` на managed pre-migration install и не валятся раньше `migrate-stealth`
- generated domain-health updates переведены на `printf '%s\n'`, чтобы JSON state передавался в `jq` единообразно и без зависимости от shell `echo`
- oneshot-таймаут `xray-health.service` уменьшен до `90s`, чтобы зависший health pass фейлился быстро, а не висел `30min`
- из setup health monitoring убран helper с 10 позиционными nameref-аргументами; вместо него используются явные typed normalizers
- grpc/mux defaults явно помечены как legacy compatibility knobs для `migrate-stealth` и explicit legacy rebuild paths
- `rand_between` получил bounded retry sampling и детерминированный fallback вместо потенциально бесконечного rejection loop
- `atomic_write` теперь явно восстанавливает `umask` при провале `mktemp`, а install теперь предупреждает, если export hooks после загрузки недоступны
- rollback теперь логирует точный target восстановления перед аварийным выходом, если копирование snapshot-файла не удалось
- `status` теперь явно предупреждает о нераспознанном inbound transport вместо немого `unknown`
- `atomic_write` теперь режет случайные интерактивные вызовы без pipe/heredoc, чтобы не зависать на чтении из tty
- explicit rollback теперь переигрывает и symlink-артефакты из backup session, а не только обычные файлы
- generated `xray-health.sh` теперь нормализует битый fail-count к `0` с предупреждением вместо падения до restart path
- release-consistency check теперь режет и stale placeholder `TODO: summarize release changes` внутри released секций `docs/ru/CHANGELOG.md`

## [7.5.6] - 2026-03-19

### Fixed
- canary bundle теперь валится fail-closed с явной ошибкой, если ломается сборка source manifest или сталкиваются имена raw-xray файлов
- wrapper теперь предупреждает, когда `SCRIPT_DIR` не удалось определить и вместо локального source tree может быть использован bootstrap path
- regex проверки версии в `check-update` нормализован так, чтобы `-` и `.` были явно литеральными в prerelease suffix
- linux-инструкция для `emergency` browser-dialer исправлена: docs и canary helper теперь используют shell-safe `env 'xray.browser.dialer=...'` вместо невалидного `export`
- `SECURITY.md` и `SECURITY.ru.md` выровнены с текущей поддерживаемой релизной линией `7.5.x`, а release-check теперь следит и за этой поверхностью
- канонический default для `SELF_CHECK_URLS` унифицирован между общими runtime-модулями

## [7.5.5] - 2026-03-18

### Changed
- явные override-пути для domain-data файлов теперь сохраняются при `resolve_paths()`, а managed default-пути по-прежнему корректно привязываются к разрешённому `data dir`
- общий root writer для `config.json` вынесен в один helper и теперь одинаково используется в полном build и rebuild flow

### Fixed
- `atomic_write` теперь режет реальные traversal-сегменты ещё до canonicalization и при этом сохраняет safe-prefix enforcement
- для `xhttp` rebuild path больше не вычисляются лишние gRPC-only timeout-параметры
- health domain probe стал строже: приоритет у реальной TLS-проверки, loose-match по одному `CONNECTED` убран, а безусловный стартовый `sleep` в connectivity check заменён на bounded readiness wait
- fallback-путь shell-рандома расширен для окружений без нормального сильного источника энтропии

## [7.5.4] - 2026-03-18

### Fixed
- release automation теперь корректно переносит заметки из `[unreleased]` в tagged section и больше не дублирует секции с висящими bullet’ами
- layout секции `7.5.3` выровнен, а release docs снова проходят markdownlint после бага в release-script

## [7.5.3] - 2026-03-18

### Changed
- source metadata (`kind`, `ref`, `commit`) теперь сохраняется в managed state и показывается в `status --verbose` и `diagnose`
- `Nightly Smoke` self-hosted зафиксирован как регулярный evidence path, а отдельный self-hosted workflow оставлен только manual/on-demand инструментом
- field validation оформлен как отдельный слой доказательства для реальных сетей вместо подмены anti-dpi proof обычным runtime-green smoke
- несколько рискованных orchestration-функций разрезаны на phase helpers без изменения публичного CLI-контракта

### Fixed
- снят ложный uninstall warning про `reset-failed`, когда после cleanup уже не остаётся ни одного `xray*` unit
- усилены real-host cleanup/rollback residue path и fallback на `xray-health` journal в server lifecycle контуре

## [7.5.2] - 2026-03-17

### Changed
- удалены архивные служебные документы из публичного репозитория, а внутренние quality-check имена выровнены под обычный maintainer workflow

## [7.5.1] - 2026-03-17

### Changed

- расширена release-валидация nightly smoke и rollback путей, чтобы опубликованное состояние ветки совпадало с полностью проверенным server-side lifecycle baseline

### Fixed

- исправлен failure-path `xray-health.service`: health timer больше не завершается раньше времени под `set -e` во время обработки счётчика неудач
- усилен rollback restore flow: связанные systemd unit’ы теперь quiesce’ятся заранее, а runtime-critical файлы восстанавливаются атомарно, без `Text file busy` на `/usr/local/bin/xray`
- `nightly_smoke_install_add_update_uninstall.sh` сделан идемпотентным за счёт уникального временного status-file на каждый прогон

## [7.5.0] - 2026-03-16

### changed

- source of truth для custom-domain install теперь сохраняется в `/etc/xray-reality/custom-domains.txt`, поэтому такие установки переживают `add-clients`, `add-keys` и следующие lifecycle-действия
- добавлен детерминированный vm-lab путь проверки tagged release через `nsc-vm-install-release` и `make vm-lab-release-smoke`

### fixed

- fail-closed валидация custom-профиля теперь рано и явно сообщает об отсутствии managed custom-domain state вместо позднего падения с пустым списком доменов
- release-facing docs и consistency-checks теперь жёстко требуют явный tag-pinned bootstrap path и generic placeholders в issue templates

## [7.3.8] - 2026-03-16

### changed

- оркестрация config, install, service и client-artifact путей разнесена по focused-модулям (`runtime_contract`, `runtime_apply`, `runtime_profiles`, `client_formats`, `client_state`, install output/selection/runtime и service runtime/uninstall helpers)
- активный xhttp planner переведён на catalog-first модель, при этом bootstrap остался совместимым с историческими pinned tag для `migrate-stealth`
- pinned bootstrap, генерация vm-lab proof-pack и host-safe lab workflows оформлены как основной maintainer-grade validation path
- issue templates, support metadata и двуязычные docs выровнены под текущую strongest-direct линию релиза `v7`

### fixed

- усилен lifecycle логов xray на `ubuntu-24.04`: startup, restart и `logrotate` больше не ломаются на hosted runner’ах
- стабилизированы legacy migration fixtures и lifecycle validation для чистых hosted окружений `ubuntu-24.04`
- quality/lint coverage расширен на `modules/export/*`, а для export capability notes и `rebuild_config_for_transport()` добавлены прямые unit-контракты
- pinned docker actions обновлены до node24-ready revisions, и hosted package builds больше не шумят из-за deprecation `Node 20`

## [7.1.0] - 2026-03-07

### changed

- strongest-direct контракт стал managed baseline: `vless + reality + xhttp + vless encryption + xtls-rprx-vision`
- добавлен `/etc/xray-reality/policy.json` как source of truth для managed policy
- `clients.json` поднят до schema v3 с provider metadata, direct-flow полями и тремя variants на конфиг
- добавлен field-only вариант `emergency` (`xhttp stream-up + browser dialer`), при этом `recommended` и `rescue` остались server-validated direct path
- добавлен `data/domains/catalog.json` и awareness planner’а по provider family для более разнообразных наборов конфигов
- `scripts/measure-stealth.sh` расширен до workflow `run`, `compare` и `summarize`, а measurement summaries стали сохраняться на диске
- добавлен `export/canary/` для переносимых полевых тестов, а `export/capabilities.json` поднят до schema v2
- `repair` и `update --replan` теперь используют self-check и field observations при продвижении более сильного spare-config
- `migrate-stealth` теперь обновляет и legacy transport, и pre-v7 xhttp install
- двуязычные docs, release metadata и lifecycle coverage обновлены до strongest-direct baseline v7.1.0

## [6.0.0] - 2026-03-07

### changed

- v6 переведен в xhttp-only режим для mutating product paths; `--transport grpc|http2` теперь отклоняется
- добавлен transport-aware post-action self-check по canonical raw xray client json artifacts
- operator verdict сохраняется в `/var/lib/xray/self-check.json` и показывается в `status --verbose` и `diagnose`
- введен `export/capabilities.json`, а `compatibility-notes.txt` теперь генерируется из capability matrix
- добавлен `scripts/measure-stealth.sh` как local measurement harness для вариантов `recommended` и `rescue`
- `update`, `repair`, `add-clients` и `add-keys` блокируются на managed legacy transport до выполнения `migrate-stealth`
- двуязычная документация, release metadata и тесты обновлены до xhttp-only baseline v6

## [5.1.0] - 2026-03-07

### changed

- `install` переведен в минимальный xhttp-first путь по умолчанию с `ru-auto` и auto-выбором числа конфигов
- ручные prompt’ы выбора профиля и числа конфигов перенесены за `install --advanced`
- добавлен `migrate-stealth` как штатная managed-миграция с legacy `grpc/http2`
- `clients.json` переведен на schema v2 с `variants[]` для каждого конфига
- xhttp-клиентские артефакты теперь создаются как `recommended (auto)` и `rescue (packet-up)` варианты
- raw xray json по вариантам экспортируются в `export/raw-xray/`
- расширено lifecycle-покрытие для minimal install, advanced install и миграции legacy-to-xhttp
- двуязычная документация приведена к xhttp-first baseline и compatibility-окну для legacy transport

## [4.2.3] - 2026-03-06

### changed

- усилена загрузка модулей в wrapper: `source` выполняется только из доверенных директорий (`SCRIPT_DIR`, `XRAY_DATA_DIR`) и больше не зависит от внешнего `MODULE_DIR`
- в `check-security-baseline.sh` добавлено покрытие powershell и заблокированы `Invoke-Expression`/`iex`, download-pipe execution и encoded-command execution
- добавлены canonical-имена global-профиля: `global-50` / `global-50-auto`; legacy-алиасы `global-ms10` / `global-ms10-auto` сохранены для обратной совместимости
- исправлены зависимости release quality-gate: перед `tests/lint.sh` теперь устанавливается `ripgrep`

## [4.2.1] - 2026-03-02

### changed

- усилена устойчивость интерактивного режима (`yes/no`, tty-нормализация, единый prompt helper)
- исправлены рендеринг рамок и стабильность ввода в install/uninstall сценариях
- вынесены и зафиксированы модульные контракты, tightened runtime-валидация путей и параметров
- усилен ci-контур (stage-3 complexity gate, дополнительные e2e и регрессионные проверки)
- документация и структура проекта унифицированы в двуязычном формате

### fixed

- `add-clients`: добавлена fail-safe проверка ipv6 inbound сборки через `jq` и проверка итогового payload
- исключены повторные и ложные циклы подтверждений в fallback-подтверждениях minisign

## [4.2.0] - 2026-02-26

### changed

- нормализованы операционные команды под установленный `xray-reality.sh`
- уточнён поддерживаемый контур: ubuntu 24.04 lts
- добавлены явные compatibility-флаги: `--allow-no-systemd` и `--require-minisign`
- документирована политика trust-anchor для minisign
- пул `tier_global_ms10` расширен с 10 до 50 доменов

### fixed

- install теперь нейтрализует конфликтующие systemd drop-in файлы
- `install`, `update` и `repair` корректно прекращают выполнение без systemd, если не включён compatibility-режим
- в strict minisign режиме реализован fail-closed
- исправлено распределение доменов, исключены соседние дубли
- исправлен diagnostic-путь (`journalctl --no-pager`)

## [4.1.8] - 2026-02-24

### changed

- ci и документация сфокусированы на ubuntu 24.04
- уточнены названия workflow-run и метаданные пакетов
- обновлена формулировка документации для публичного репозитория
- добавлен release-checklist для ubuntu 24.04

### fixed

- исправлена обработка bbr sysctl значений
- улучшено поведение в isolated root окружениях

## [4.1.7] - 2026-02-22

### note

- базовый релиз, с которого начата история в этом репозитории

## [<4.1.7]

### note

- старые релизы до миграции в новый репозиторий здесь не публикуются
- история до 4.1.7 намеренно свернута
