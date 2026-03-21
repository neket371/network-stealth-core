# maintainer lab and smoke flows

this document is for maintainers and contributors.
it describes isolated test flows for validating the project on busy hosts without touching the live host namespace.

ordinary users do not need these commands for a normal install.

regular self-hosted evidence belongs to the `Nightly Smoke` workflow and its `nightly smoke self-hosted` job.
the standalone self-hosted workflow is manual/on-demand only and exists for targeted runner checks or maintainer repros.

## host-safe container smoke

when the host already carries production services, keep the first smoke layer isolated:

```bash
make lab-smoke
```

or run the scripts directly:

```bash
bash scripts/lab/prepare-host-safe-smoke.sh
bash scripts/lab/run-container-smoke.sh
bash scripts/lab/collect-container-artifacts.sh
```

this flow:

- expects an existing `docker` or `podman` runtime
- publishes no container ports
- runs a compatibility smoke install only inside the container
- forces `c.utf-8` inside the smoke container
- stores logs and artifacts under the host-safe lab directory instead of the repo tree
- leaves the live host xray, firewall, and published services untouched

## full vm-lab lifecycle on a busy server

when you need the real `systemd` lifecycle without touching the busy host namespace, use the kvm-backed vm lab:

```bash
make vm-lab-prepare
make vm-lab-smoke
make vm-lab-release-smoke RELEASE_TAG=vX.Y.Z
make vm-proof-pack
```

or run the scripts directly:

```bash
bash scripts/lab/prepare-vm-smoke.sh
bash scripts/lab/run-vm-lifecycle-smoke.sh
bash scripts/lab/run-vm-release-smoke.sh
bash scripts/lab/enter-vm-smoke.sh
bash scripts/lab/generate-vm-proof-pack.sh
```

this flow:

- requires `kvm`, `qemu-system-x86_64`, `qemu-img`, `cloud-localds`, and `ssh`
- downloads the ubuntu 24.04 cloud image once under the lab directory
- boots an isolated guest with real `systemd`
- forwards only guest ssh to host loopback
- copies the current repo into the guest
- runs the full nightly lifecycle smoke there, including `install`, `add-clients`, `repair`, `update`, `rollback`, `status`, and `uninstall`
- exposes a separate release-bootstrap smoke path that validates a tagged bootstrap install through the guest helper instead of raw `curl`
- collects guest logs back into the vm-lab log directory
- copies a sanitized proof source bundle back into the vm-lab artifacts directory

default guest-side smoke values:

- `start_port=24440`
- `initial_configs=1`
- `add_configs=1`
- `e2e_server_ip=10.0.2.15`
- `e2e_domain_check=false`
- `e2e_skip_reality_check=false`
- `xray_custom_domains=vk.com,yoomoney.ru,cdek.ru`
- `install_version=latest stable`
- `update_version=install_version`

## manual work inside the vm-lab guest

inside the guest, use the helper commands:

```bash
nsc-vm-install-latest --num-configs 3
nsc-vm-install-release vX.Y.Z --num-configs 1
nsc-vm-install-repo --advanced
```

do not use a raw `curl ... xray-reality.sh` install inside the guest as your evidence path.
in the nat-backed vm-lab that path can auto-detect the host public ip instead of the guest ip and fail the final self-check.
for release/bootstrap validation use `nsc-vm-install-release` or `make vm-lab-release-smoke RELEASE_TAG=...`.

helper reference:

- `nsc-vm-guest-ip` — prints the detected guest ipv4
- `nsc-vm-install-latest` — downloads the latest bootstrap script and runs install with the guest ipv4 pinned into `server_ip`
- `nsc-vm-install-release` — downloads a tagged bootstrap script, pins `xray_repo_ref`, and uses vm-lab-safe defaults for `server_ip`, `start_port`, and `xray_custom_domains`
- `nsc-vm-install-repo` — runs the repo-local script from `~/repo` with the guest ipv4 pinned into `server_ip`

## proof-pack generation

after a successful vm-lab lifecycle run, generate a sanitized proof bundle:

```bash
make vm-proof-pack
```

or:

```bash
bash scripts/lab/generate-vm-proof-pack.sh
```

the proof-pack contains:

- lifecycle verdicts and version transitions
- sanitized `status --verbose` / `diagnose` outputs
- self-check and measurement summaries when present
- a hash inventory of generated artifacts without copying secret-bearing client material
- sanitized vm-lab logs

the proof-pack intentionally excludes:

- private keys
- raw client json
- live `vless://` links
- reusable `uuid`, `short_id`, or `public_key` values

## when to use which layer

- use `make ci-fast` and `make ci-full` for local repo validation
- use `make lab-smoke` for a safe first smoke on a busy host
- use `make vm-lab-smoke` for the full prod-like lifecycle on that same busy host
- use `make vm-lab-release-smoke RELEASE_TAG=vX.Y.Z` for tagged bootstrap validation in the nat-backed guest
- use `make vm-proof-pack` when you need a shareable maintainer/operator evidence bundle from that vm-lab run
- use canary bundle exports for testing from another machine or another network
- use `XRAY_FAILURE_PROOF_DIR=/path` only as a maintainer/debug env hook when you need a local failure bundle from `cleanup_on_error`; do not persist it in `config.env`
- treat `Nightly Smoke` self-hosted as the regular scheduled proof path
- treat `.github/workflows/self-hosted-smoke.yml` as manual/on-demand only
