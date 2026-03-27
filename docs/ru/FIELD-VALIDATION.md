# field validation

зелёный runtime и hosted CI не доказывают anti-dpi эффективность в реальных сетях.
они доказывают только корректность managed lifecycle, export-слоя и rollback-модели.

этот playbook нужен, когда тебе нужен честный полевой verdict по текущему strongest-direct baseline.

## минимальная матрица

- минимум 2 независимые сети
- минимум 2 клиентских стека
- обязательно проверить `recommended` и `rescue`
- `emergency` трогать только если `recommended` и `rescue` деградировали
- ipv4 и ipv6 фиксировать раздельно, если доступны оба

## обязательные поля отчёта

каждый сохранённый field-report должен содержать:

- provider
- region
- network tag
- client name
- variant key
- verdict
- latency
- observed block mode
- timestamp

## канонический workflow

1. сгенерируй или обнови managed canary bundle на сервере.
2. перенеси `export/canary/` на удалённую тестовую машину.
3. прогоняй canary-пробы там: сначала `recommended`, потом `rescue`, и только потом `emergency`, если нужно.
4. собери получившиеся reports в один каталог.
5. импортируй их обратно на managed node:

```bash
sudo bash scripts/measure-stealth.sh import \
  --dir ./remote-canary-reports \
  --output /tmp/measure-import.json
```

`import --dir` теперь проходит по nested-каталогам, пропускает не-report JSON и дедуплицирует уже импортированные отчёты по content hash.

1. сравни импортированные reports:

```bash
sudo bash scripts/measure-stealth.sh compare \
  --dir /var/lib/xray/measurements \
  --output /tmp/measure-compare.json
```

1. собери актуальную summary-картину:

```bash
sudo bash scripts/measure-stealth.sh summarize \
  --dir /var/lib/xray/measurements \
  --output /tmp/measure-summary.json
```

отрендеренная summary теперь и есть operator-grade слой:

- `coverage: ok|warning` показывает, достаточно ли сохранённых reports для доверия полевой картине
- `family diversity: ok|warning` показывает, достаточно ли текущий config set разведён по независимым provider family
- `long-term: ok|warning` показывает, есть ли деградация на последних окнах отчётов
- `rotation verdict` показывает, можно ли продвигать более сильный spare прямо сейчас или он ещё держится в cooldown
- `operator recommendation` говорит, оставлять ли current primary, повышать spare, добирать данные или переходить к полевой проверке `emergency`
- `promotion candidate` показывает, какой spare с высокой вероятностью поднимут `update --replan` или `repair`, и даст ли это выигрыш по provider-family independence
- `cooldown families` и `cooldown domains` показывают, какие недавно сгоревшие пути специально удерживаются вне ближайшего rotation round

1. если в summary написано `operator recommendation: promote-spare`, выполни:

```bash
sudo xray-reality.sh update --replan --non-interactive --yes
```

## дисциплина claims

- `CI`, `Ubuntu smoke`, `Nightly Smoke`, lab-smoke и real-host lifecycle доказывают runtime correctness.
- только импортированные field-reports и их summary доказывают эффективность в реальных сетях.
- эти два слоя надо держать раздельно в release notes, operator guidance и incident reports.
