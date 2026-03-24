# faq

## why is install so opinionated?

the project is optimized for two things at once:

- almost no install questions
- the strongest safe default for rf anti-dpi use

that is why the normal path avoids transport and profile prompts.

## which bootstrap path should i use on a real server?

prefer the pinned bootstrap path with `XRAY_REPO_COMMIT=<full_commit_sha>`.
if you need the exact published release rather than the current floating branch, use the tag-pinned path from the readme with `XRAY_REPO_REF=v<release-tag>`.
fetching the wrapper from a tag url alone does not pin the bootstrap clone.
the floating raw bootstrap stays available for convenience, but it should not be your first production-like path.

## when should i use `install --advanced`?

only when you explicitly want the manual domain-profile prompt.
ordinary interactive installs already ask for the config count.

## why are some mutating actions blocked on older installs?

because `update`, `repair`, `add-clients`, and `add-keys` must not silently keep a weaker managed contract alive.
run:

```bash
sudo xray-reality.sh migrate-stealth --non-interactive --yes
```

## what does `migrate-stealth` upgrade?

it upgrades both:

- managed legacy `grpc/http2` installs
- managed xhttp installs that do not yet have the v7 strongest-direct contract

## why is raw xray json the canonical client artifact?

because it can express the full strongest-direct contract without loss:

- xhttp modes
- generated vless encryption
- `xtls-rprx-vision`
- browser-dialer requirements for `emergency`

links are still emitted only where they stay honest.

## what is the `emergency` variant for?

`emergency` is the last-resort field tier:

- `xhttp mode=stream-up`
- requires browser dialer
- exported as raw xray only
- not used by post-action server self-check

## why are sing-box and clash-meta marked unsupported?

because the project does not want to generate degraded templates that misrepresent the strongest-direct contract.
use raw xray json when you need the exact managed behavior.

## what is `policy.json` for?

`/etc/xray-reality/policy.json` stores the operator-facing policy separately from generated runtime state.
it keeps:

- domain profile and tier
- self-check settings
- measurement settings
- update and replan settings
- direct contract metadata

## what does `scripts/measure-stealth.sh` do?

it reuses the same probe engine as runtime self-check and adds report workflows:

- `run`
- `import`
- `compare`
- `prune`
- `summarize`

saved reports feed the measurement summary used by `status --verbose`, `diagnose`, `repair`, and `update --replan`.

## how do i validate this on a busy host?

use the maintainer-only lab docs and pick the lightest layer that answers your question:

- `make lab-smoke` for a safe first smoke in an isolated container
- `make vm-lab-smoke` for the full prod-like `systemd` lifecycle in an isolated vm
- `make vm-proof-pack` when you need a shareable bundle from that vm-lab run

references:

- [MAINTAINER-LAB.md](MAINTAINER-LAB.md)
- [.github/CONTRIBUTING.md](../../.github/CONTRIBUTING.md)

## what is the canary bundle for?

it is the portable field-testing surface under `export/canary/`.
use it when another machine or another network needs to test the generated variants, especially `emergency`.

## what xray version is expected?

the strongest-direct client contract declares a minimum xray version.
managed artifacts currently record `25.9.5` as the minimum client/core baseline.
if the local xray binary cannot satisfy required features, the action fails closed.
