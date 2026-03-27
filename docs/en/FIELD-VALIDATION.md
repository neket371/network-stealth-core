# field validation

runtime-green and hosted CI do not prove real-network anti-dpi effectiveness.
they only prove that the managed lifecycle, exports, and rollback model behave correctly.

use this playbook when you need an honest field verdict for the active strongest-direct baseline.

## minimum matrix

- at least 2 independent networks
- at least 2 client stacks
- validate `recommended` and `rescue`
- try `emergency` only when `recommended` and `rescue` are degraded
- keep ipv4 and ipv6 observations separate when both exist

## required report fields

every saved field report should capture:

- provider
- region
- network tag
- client name
- variant key
- verdict
- latency
- observed block mode
- timestamp

## canonical workflow

1. generate or refresh the managed canary bundle on the server.
2. copy `export/canary/` to the remote test machine.
3. run the canary probes there for `recommended`, then `rescue`, then `emergency` only if needed.
4. collect the produced reports into one directory.
5. import them back on the managed node:

```bash
sudo bash scripts/measure-stealth.sh import \
  --dir ./remote-canary-reports \
  --output /tmp/measure-import.json
```

`import --dir` now walks nested directories, skips non-report JSON, and deduplicates already imported reports by content hash.

1. compare the imported reports:

```bash
sudo bash scripts/measure-stealth.sh compare \
  --dir /var/lib/xray/measurements \
  --output /tmp/measure-compare.json
```

1. summarize the current picture:

```bash
sudo bash scripts/measure-stealth.sh summarize \
  --dir /var/lib/xray/measurements \
  --output /tmp/measure-summary.json
```

the rendered summary is now the operator-grade layer:

- `coverage: ok|warning` tells you whether the saved reports are representative enough
- `family diversity: ok|warning` tells you whether the current config set still spans enough independent provider families
- `long-term: ok|warning` tells you whether recent report windows show a degrading trend
- `rotation verdict` tells you whether the stronger spare is promotable now or still cooling down
- `operator recommendation` tells you whether to keep the primary, promote a spare, collect more data, or field-test `emergency`
- `promotion candidate` tells you which spare `update --replan` or `repair` is likely to elevate and whether that move improves provider-family independence
- `cooldown families` and `cooldown domains` show which recently burned paths are intentionally kept out of the next rotation round

1. if the summary says `operator recommendation: promote-spare`, run:

```bash
sudo xray-reality.sh update --replan --non-interactive --yes
```

## claim discipline

- `CI`, `Ubuntu smoke`, `Nightly Smoke`, lab-smoke, and real-host lifecycle runs prove runtime correctness.
- only imported field reports and summaries prove real-network effectiveness.
- keep these two layers separate in release notes, operator guidance, and incident reports.
