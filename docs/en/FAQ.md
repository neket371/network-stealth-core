# faq

## why is install so opinionated?

the project is optimized for two things at once:

- almost no install questions
- the strongest safe default for rf anti-dpi use

that is why the normal path avoids transport and profile prompts.

## when should i use `install --advanced`?

only when you explicitly want manual profile and config-count prompts.
it is not the recommended path for ordinary installs.

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

## how do i smoke-test this on a busy host?

do not run host-level lifecycle tests on a machine that already serves production workloads.
use the isolated lab flow instead:

```bash
make lab-smoke
```

it uses an existing container runtime and keeps the smoke install inside an ubuntu 24.04 container with no published ports.

## how do i run a full `systemd` lifecycle test on a busy host?

use the vm lab instead of the container smoke:

```bash
make vm-lab-prepare
make vm-lab-smoke
```

it boots an isolated ubuntu 24.04 vm under kvm, forwards ssh only to host loopback, and runs the full lifecycle smoke inside the guest.

for manual guest-side work, use `nsc-vm-install-latest` or `nsc-vm-install-repo` instead of a raw `curl` install: the helpers pin `server_ip` to the guest ipv4 automatically.

## what is the canary bundle for?

it is the portable field-testing surface under `export/canary/`.
use it when another machine or another network needs to test the generated variants, especially `emergency`.

## what xray version is expected?

the strongest-direct client contract declares a minimum xray version.
managed artifacts currently record `25.9.5` as the minimum client/core baseline.
if the local xray binary cannot satisfy required features, the action fails closed.
