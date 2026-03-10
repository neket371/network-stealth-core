# изолированные стенды и smoke-проверки для сопровождающих

этот документ для сопровождающих и контрибьюторов.
здесь описаны изолированные сценарии проверки проекта на занятых хостах без захода в namespace живого хоста.

обычному пользователю эти команды для стандартной установки не нужны.

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
```

или запускай скрипты напрямую:

```bash
bash scripts/lab/prepare-vm-smoke.sh
bash scripts/lab/run-vm-lifecycle-smoke.sh
bash scripts/lab/enter-vm-smoke.sh
```

этот сценарий:

- требует `kvm`, `qemu-system-x86_64`, `qemu-img`, `cloud-localds` и `ssh`
- один раз скачивает ubuntu 24.04 cloud image в lab-директорию
- поднимает изолированного гостя с настоящим `systemd`
- пробрасывает на loopback хоста только гостевой ssh
- копирует текущий репозиторий в гостя
- гоняет там полный nightly lifecycle smoke: `install`, `add-clients`, `repair`, `update`, `rollback`, `status`, `uninstall`
- возвращает guest-логи обратно в vm-lab log directory

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
nsc-vm-install-repo --advanced
```

raw `curl ... xray-reality.sh` install внутри гостя не используй.
в nat-backed vm-lab такой путь может автоопределить public ip хоста вместо guest ip и завалить финальный self-check.

что делает каждый helper:

- `nsc-vm-guest-ip` — печатает guest ipv4
- `nsc-vm-install-latest` — скачивает latest bootstrap script и запускает install с guest ipv4 в `server_ip`
- `nsc-vm-install-repo` — запускает repo-local script из `~/repo` с guest ipv4 в `server_ip`

## какой слой когда использовать

- `make ci-fast` и `make ci-full` — локальная валидация репозитория
- `make lab-smoke` — безопасный первый smoke на занятом хосте
- `make vm-lab-smoke` — полный prod-like lifecycle на том же занятом хосте
- canary bundle exports — проверка с другой машины или другой сети
