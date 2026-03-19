# troubleshooting

## 1. install is asking questions i did not expect

default install should stay minimal.
ordinary interactive installs still ask for the config count.
if you used `install --advanced`, the extra domain-profile prompt is expected.
for unattended installs use:

```bash
sudo xray-reality.sh install --non-interactive --yes
```

## 2. `update`, `repair`, or `add-clients` says the managed install must migrate first

you are on a legacy or pre-v7 managed contract.
run:

```bash
sudo xray-reality.sh migrate-stealth --non-interactive --yes
```

then verify:

```bash
sudo xray-reality.sh status --verbose
```

## 3. status shows `warning` or `broken`

collect the operator picture first:

```bash
sudo xray-reality.sh status --verbose
sudo xray-reality.sh diagnose
```

then take the next step:

- `warning`: save real-network measurements and run `update --replan` or `repair`
- `broken`: run `repair` first, then inspect whether a stronger spare is promoted

```bash
sudo bash scripts/measure-stealth.sh run --save --output /tmp/measure.json
sudo xray-reality.sh update --replan --non-interactive --yes
```

## 4. client artifacts look stale or missing

rebuild them from the live managed state:

```bash
sudo xray-reality.sh repair --non-interactive --yes
```

this should refresh:

- `clients.txt`
- `clients.json`
- `export/raw-xray/`
- `export/capabilities.json`
- `export/canary/`
- `policy.json`

## 5. `scripts/measure-stealth.sh run` reports no successful variants for a config

first compare direct variants:

```bash
sudo bash scripts/measure-stealth.sh run --variants recommended,rescue --output /tmp/measure.json
jq . /tmp/measure.json
```

if both direct variants are weak on the tested network:

- inspect `status --verbose` for `recommend_emergency`
- use the canary bundle or raw xray `emergency` config on the client side
- ensure the client sets `xray.browser.dialer`

## 6. i need to test `emergency`

`emergency` is field-only.
use the raw xray artifact from `export/raw-xray/` or the `export/canary/` bundle.
example client-side env:

```bash
env 'xray.browser.dialer=127.0.0.1:11050' xray run -config /path/to/emergency.json
```

do not use the dotted `export` form in bash or other POSIX shells: dotted env names are not valid shell identifiers there.

it is normal that server-side post-action self-check does not execute `emergency`.

## 7. `scripts/measure-stealth.sh` usage failed

use one of the supported forms:

```bash
sudo bash scripts/measure-stealth.sh run --save
sudo bash scripts/measure-stealth.sh import --dir ./remote-canary-reports
sudo bash scripts/measure-stealth.sh compare --dir /var/lib/xray/measurements
sudo bash scripts/measure-stealth.sh prune --keep-last 30
sudo bash scripts/measure-stealth.sh summarize --dir /var/lib/xray/measurements
```

plain invocation without a subcommand is equivalent to `run`.

## 8. `migrate-stealth` failed

collect diagnostics before trying random edits:

```bash
sudo xray-reality.sh diagnose
sudo xray-reality.sh rollback
```

then inspect:

- xray feature support
- self-check errors
- field summary
- policy and artifact paths

## 9. external client imports do not match the raw xray config

this is usually intentional.
for strongest-direct features, raw xray json is the canonical source of truth.
use `export/capabilities.json` to see which targets are native, link-only, or unsupported.
