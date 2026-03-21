# изолированные стенды и smoke-проверки для сопровождающих

этот документ для сопровождающих и контрибьюторов.
здесь описаны изолированные сценарии проверки проекта на занятых хостах без захода в namespace живого хоста.

обычному пользователю эти команды для стандартной установки не нужны.

регулярное self-hosted evidence живёт в workflow `Nightly Smoke` и его job `nightly smoke self-hosted`.
отдельный self-hosted workflow — только manual/on-demand инструмент для точечных проверок runner'а и воспроизведения maintainer-багов.

## host-safe container smoke

если на хосте уже крутятся production-сервисы, используй сначала изолированный smoke-слой:

```bash
make lab-smoke
```

или запускай скрипты напрямую:

```bash
bash scripts/lab/prepare-host-safe-smoke.sh
bash scripts/lab/run-container-smoke.sh
bash scripts/lab/collect-container-artifacts.sh
```

этот сценарий:

- ожидает уже существующий `docker` или `podman`
- не публикует container ports
- гоняет compatibility smoke install только внутри контейнера
- форсирует `c.utf-8` внутри smoke-контейнера
- складывает логи и артефакты в host-safe lab directory, а не в дерево репозитория
- не трогает живой host xray, firewall и опубликованные сервисы

## полный vm-lab lifecycle на занятом сервере

если нужен уже настоящий `systemd` lifecycle без захода в namespace занятого хоста, используй kvm-backed vm lab:

```bash
make vm-lab-prepare
make vm-lab-smoke
make vm-lab-release-smoke RELEASE_TAG=vX.Y.Z
make vm-proof-pack
```

или запускай скрипты напрямую:

```bash
bash scripts/lab/prepare-vm-smoke.sh
bash scripts/lab/run-vm-lifecycle-smoke.sh
bash scripts/lab/run-vm-release-smoke.sh
bash scripts/lab/enter-vm-smoke.sh
bash scripts/lab/generate-vm-proof-pack.sh
```

этот сценарий:

- требует `kvm`, `qemu-system-x86_64`, `qemu-img`, `cloud-localds` и `ssh`
- один раз скачивает ubuntu 24.04 cloud image в lab-директорию
- поднимает изолированного гостя с настоящим `systemd`
- пробрасывает на loopback хоста только гостевой ssh
- копирует текущий репозиторий в гостя
- гоняет там полный nightly lifecycle smoke: `install`, `add-clients`, `repair`, `update`, `rollback`, `status`, `uninstall`
- даёт отдельный release-bootstrap smoke path, где tagged bootstrap install валидируется через guest helper, а не через raw `curl`
- возвращает guest-логи обратно в vm-lab log directory
- копирует обратно в vm-lab artifacts directory санитизированный proof source bundle

дефолтные guest-side значения:

- `start_port=24440`
- `initial_configs=1`
- `add_configs=1`
- `e2e_server_ip=10.0.2.15`
- `e2e_domain_check=false`
- `e2e_skip_reality_check=false`
- `xray_custom_domains=vk.com,yoomoney.ru,cdek.ru`
- `install_version=latest stable`
- `update_version=install_version`

## ручная работа внутри гостя vm-lab

внутри гостя используй helper-команды:

```bash
nsc-vm-install-latest --num-configs 3
nsc-vm-install-release vX.Y.Z --num-configs 1
nsc-vm-install-repo --advanced
```

raw `curl ... xray-reality.sh` install внутри гостя не используй как evidence path.
в nat-backed vm-lab такой путь может автоопределить public ip хоста вместо guest ip и завалить финальный self-check.
для release/bootstrap validation используй `nsc-vm-install-release` или `make vm-lab-release-smoke RELEASE_TAG=...`.

что делает каждый helper:

- `nsc-vm-guest-ip` — печатает guest ipv4
- `nsc-vm-install-latest` — скачивает latest bootstrap script и запускает install с guest ipv4 в `server_ip`
- `nsc-vm-install-release` — скачивает tagged bootstrap script, фиксирует `xray_repo_ref` и использует vm-lab-safe defaults для `server_ip`, `start_port` и `xray_custom_domains`
- `nsc-vm-install-repo` — запускает repo-local script из `~/repo` с guest ipv4 в `server_ip`

## генерация proof-pack

после успешного vm-lab lifecycle run собери санитизированный proof bundle:

```bash
make vm-proof-pack
```

или:

```bash
bash scripts/lab/generate-vm-proof-pack.sh
```

в proof-pack входят:

- lifecycle verdicts и переходы версий
- санитизированные `status --verbose` / `diagnose`
- self-check и measurement summaries, если они есть
- hash inventory generated artifacts без копирования чувствительного client material
- санитизированные vm-lab логи

proof-pack намеренно не включает:

- private keys
- raw client json
- live `vless://` links
- переиспользуемые `uuid`, `short_id` или `public_key`

## какой слой когда использовать

- `make ci-fast` и `make ci-full` — локальная валидация репозитория
- `make lab-smoke` — безопасный первый smoke на занятом хосте
- `make vm-lab-smoke` — полный prod-like lifecycle на том же занятом хосте
- `make vm-lab-release-smoke RELEASE_TAG=vX.Y.Z` — tagged bootstrap validation в nat-backed guest
- `make vm-proof-pack` — shareable maintainer/operator evidence bundle из последнего vm-lab run
- canary bundle exports — проверка с другой машины или другой сети
- `XRAY_FAILURE_PROOF_DIR=/path` — только maintainer/debug env hook для локального failure bundle из `cleanup_on_error`; не сохраняй это в `config.env`
- `Nightly Smoke` self-hosted — регулярный scheduled proof-path
- `.github/workflows/self-hosted-smoke.yml` — только manual/on-demand workflow
