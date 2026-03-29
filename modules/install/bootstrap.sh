#!/usr/bin/env bash
# shellcheck shell=bash

GLOBAL_CONTRACT_MODULE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../lib" && pwd)/globals_contract.sh"
if [[ ! -f "$GLOBAL_CONTRACT_MODULE" && "${XRAY_SOURCE_TREE_STRICT:-false}" != "true" && -n "${XRAY_DATA_DIR:-}" ]]; then
    GLOBAL_CONTRACT_MODULE="$XRAY_DATA_DIR/modules/lib/globals_contract.sh"
fi
if [[ ! -f "$GLOBAL_CONTRACT_MODULE" ]]; then
    echo "ERROR: не найден модуль global contract: $GLOBAL_CONTRACT_MODULE" >&2
    exit 1
fi
# shellcheck source=modules/lib/globals_contract.sh
source "$GLOBAL_CONTRACT_MODULE"

detect_distro() {
    log STEP "Определяем операционную систему..."

    if [[ ! -f /etc/os-release ]]; then
        log ERROR "Не удалось определить дистрибутив"
        exit 1
    fi

    # shellcheck source=/etc/os-release
    # shellcheck disable=SC1091
    . /etc/os-release

    case "$ID" in
        ubuntu | debian)
            if [[ "$ID" == "ubuntu" ]] && version_lt "$VERSION_ID" "20.04"; then
                log WARN "Рекомендуется Ubuntu 20.04+"
            fi
            PKG_TYPE="deb"
            PKG_MANAGER="apt-get"
            PKG_UPDATE="apt-get update -qq"
            PKG_INSTALL="apt-get install -y -qq"
            export DEBIAN_FRONTEND=noninteractive
            ;;
        fedora)
            PKG_TYPE="rpm"
            PKG_MANAGER="dnf"
            PKG_UPDATE="dnf -y makecache"
            PKG_INSTALL="dnf -y install"
            ;;
        centos | rhel | almalinux | rocky)
            PKG_TYPE="rpm"
            if command -v dnf > /dev/null 2>&1; then
                PKG_MANAGER="dnf"
                PKG_UPDATE="dnf -y makecache"
                PKG_INSTALL="dnf -y install"
            elif command -v yum > /dev/null 2>&1; then
                PKG_MANAGER="yum"
                PKG_UPDATE="yum -y makecache"
                PKG_INSTALL="yum -y install"
            else
                log ERROR "Не найден пакетный менеджер dnf/yum"
                exit 1
            fi
            ;;
        *)
            if [[ "${ID_LIKE:-}" == *"debian"* ]]; then
                PKG_TYPE="deb"
                PKG_MANAGER="apt-get"
                PKG_UPDATE="apt-get update -qq"
                PKG_INSTALL="apt-get install -y -qq"
                export DEBIAN_FRONTEND=noninteractive
            elif [[ "${ID_LIKE:-}" == *"rhel"* || "${ID_LIKE:-}" == *"fedora"* ]]; then
                PKG_TYPE="rpm"
                if command -v dnf > /dev/null 2>&1; then
                    PKG_MANAGER="dnf"
                    PKG_UPDATE="dnf -y makecache"
                    PKG_INSTALL="dnf -y install"
                elif command -v yum > /dev/null 2>&1; then
                    PKG_MANAGER="yum"
                    PKG_UPDATE="yum -y makecache"
                    PKG_INSTALL="yum -y install"
                else
                    log ERROR "Не найден пакетный менеджер dnf/yum"
                    exit 1
                fi
            else
                log ERROR "Поддерживаются только Ubuntu/Debian/Fedora/RHEL-based (обнаружено: $ID)"
                exit 1
            fi
            ;;
    esac

    log OK "Система: ${BOLD}$PRETTY_NAME${NC}"
    log INFO "Пакетный менеджер: ${PKG_MANAGER}"
}

check_disk_space() {
    log STEP "Проверяем свободное место на диске..."

    local min_mb=100 # минимум 100 MB для установки
    local -a check_dirs=(/var /etc /usr /tmp)
    local dir avail_mb

    for dir in "${check_dirs[@]}"; do
        [[ -d "$dir" ]] || continue
        avail_mb=$(df -m "$dir" 2> /dev/null | awk 'NR==2 {print $4}')
        if [[ -n "$avail_mb" && "$avail_mb" =~ ^[0-9]+$ ]] && ((avail_mb < min_mb)); then
            log ERROR "Недостаточно места в ${dir}: ${avail_mb}MB (нужно минимум ${min_mb}MB)"
            hint "Освободите место: apt-get clean, docker system prune, или удалите ненужные файлы"
            exit 1
        fi
    done

    log OK "Свободного места достаточно"
}

install_dependencies() {
    log STEP "Проверяем зависимости..."

    local deps=()
    local missing=()

    if [[ "${PKG_TYPE:-}" == "rpm" ]]; then
        deps=(curl jq openssl unzip ca-certificates util-linux iproute procps-ng libcap logrotate policycoreutils)
        for dep in "${deps[@]}"; do
            if [[ "$dep" == "curl" ]]; then
                if command -v curl > /dev/null 2>&1 || rpm -q curl-minimal > /dev/null 2>&1; then
                    continue
                fi
            fi
            if ! rpm -q "$dep" > /dev/null 2>&1; then
                missing+=("$dep")
            fi
        done
    else
        deps=(curl jq openssl unzip ca-certificates uuid-runtime iproute2 libcap2-bin logrotate procps)
        for dep in "${deps[@]}"; do
            if ! dpkg -s "$dep" > /dev/null 2>&1; then
                missing+=("$dep")
            fi
        done
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        log INFO "Устанавливаем: ${missing[*]}"
        # shellcheck disable=SC2086 # PKG_UPDATE/PKG_INSTALL contain intentional word splitting
        $PKG_UPDATE > /dev/null 2>&1 || true
        # shellcheck disable=SC2086
        $PKG_INSTALL "${missing[@]}" > /dev/null 2>&1 || {
            log ERROR "Не удалось установить пакеты: ${missing[*]}"
            exit 1
        }
    fi

    log OK "Все зависимости установлены"
}

install_self_source_tree_root_files() {
    if declare -F managed_source_tree_root_files > /dev/null 2>&1; then
        managed_source_tree_root_files
        return 0
    fi
    printf '%s\n' \
        xray-reality.sh \
        domains.tiers \
        sni_pools.map \
        transport_endpoints.map \
        lib.sh \
        install.sh \
        config.sh \
        service.sh \
        health.sh \
        export.sh
}

install_self_copy_tree_into_stage() {
    local src_dir="$1"
    local stage_root="$2"
    local tree_name="$3"
    [[ -d "$src_dir" ]] || return 0

    mkdir -p "${stage_root}/${tree_name}" || return 1
    cp -a "$src_dir/." "${stage_root}/${tree_name}/" || return 1
}

install_self_copy_file_into_stage() {
    local src_path="$1"
    local stage_root="$2"
    local rel_path="$3"
    local dest_path tmp_file

    [[ -f "$src_path" ]] || return 0
    dest_path="${stage_root}/${rel_path}"
    mkdir -p "$(dirname "$dest_path")" || return 1
    tmp_file=$(mktemp "${dest_path}.tmp.XXXXXX") || return 1
    if ! cp -a "$src_path" "$tmp_file"; then
        rm -f "$tmp_file"
        return 1
    fi
    if ! mv -f "$tmp_file" "$dest_path"; then
        rm -f "$tmp_file"
        return 1
    fi
}

install_self_publish_staged_tree() {
    local stage_root="$1"
    local dest_root="$2"
    local dest_parent dest_name backup_root restored_backup=false

    dest_parent=$(dirname "$dest_root")
    dest_name=$(basename "$dest_root")
    mkdir -p "$dest_parent" || return 1

    backup_root=""
    if [[ -d "$dest_root" ]]; then
        backup_root=$(mktemp -d "${dest_parent}/.${dest_name}.backup.XXXXXX") || return 1
        if ! mv "$dest_root" "${backup_root}/${dest_name}"; then
            rm -rf "$backup_root"
            return 1
        fi
    fi

    if ! mv "$stage_root" "$dest_root"; then
        rm -rf -- "$stage_root" 2> /dev/null || true
        if [[ -n "$backup_root" && -d "${backup_root}/${dest_name}" ]]; then
            if mv "${backup_root}/${dest_name}" "$dest_root"; then
                restored_backup=true
            fi
        fi
        if [[ "$restored_backup" == true ]]; then
            rm -rf "$backup_root"
        fi
        return 1
    fi

    rm -rf "$backup_root"
}

install_self_sync_tree() {
    local src_root="$1"
    local dest_root="$2"
    local dest_parent dest_name stage_root root_file src_path
    local dest_exists=false

    dest_parent=$(dirname "$dest_root")
    dest_name=$(basename "$dest_root")
    mkdir -p "$dest_parent" || {
        log ERROR "Не удалось подготовить родительский каталог managed source tree: ${dest_parent}"
        exit 1
    }

    stage_root=$(mktemp -d "${dest_parent}/.${dest_name}.new.XXXXXX") || {
        log ERROR "Не удалось создать staging-каталог для managed source tree"
        exit 1
    }

    if [[ -d "$dest_root" ]]; then
        dest_exists=true
        if declare -F backup_file > /dev/null 2>&1; then
            backup_file "$dest_root" || {
                rm -rf "$stage_root"
                log ERROR "Не удалось сохранить rollback-снимок managed source tree"
                exit 1
            }
        fi
    elif declare -F record_created_path > /dev/null 2>&1; then
        record_created_path "$dest_root"
    fi

    if ! install_self_copy_tree_into_stage "$src_root/modules" "$stage_root" "modules"; then
        rm -rf "$stage_root"
        log ERROR "Не удалось собрать staging-копию modules"
        exit 1
    fi
    if ! install_self_copy_tree_into_stage "$src_root/data" "$stage_root" "data"; then
        rm -rf "$stage_root"
        log ERROR "Не удалось собрать staging-копию data"
        exit 1
    fi
    if ! install_self_copy_tree_into_stage "$src_root/scripts" "$stage_root" "scripts"; then
        rm -rf "$stage_root"
        log ERROR "Не удалось собрать staging-копию scripts"
        exit 1
    fi

    while IFS= read -r root_file; do
        [[ -n "$root_file" ]] || continue
        src_path="$src_root/$root_file"
        if ! install_self_copy_file_into_stage "$src_path" "$stage_root" "$root_file"; then
            rm -rf "$stage_root"
            log ERROR "Не удалось собрать staging-копию ${root_file}"
            exit 1
        fi
    done < <(install_self_source_tree_root_files)

    if ! install_self_publish_staged_tree "$stage_root" "$dest_root"; then
        if [[ "$dest_exists" == true ]]; then
            log ERROR "Не удалось атомарно обновить managed source tree в ${dest_root}; предыдущий tree сохранён в rollback snapshot"
        else
            log ERROR "Не удалось атомарно обновить managed source tree в ${dest_root}"
        fi
        exit 1
    fi
}

install_self() {
    log STEP "Устанавливаем скрипт управления..."

    if [[ -n "$XRAY_DATA_DIR" ]]; then
        install_self_sync_tree "$SCRIPT_DIR" "$XRAY_DATA_DIR"
        log OK "Данные установлены в $XRAY_DATA_DIR"
    fi

    local src wrapper_src
    wrapper_src="${SCRIPT_DIR}/xray-reality.sh"
    if [[ -f "$wrapper_src" ]]; then
        src="$wrapper_src"
    else
        src=$(readlink -f "$0" 2> /dev/null || realpath "$0" 2> /dev/null || echo "$0")
    fi
    if [[ ! -f "$src" ]]; then
        log WARN "Не удалось определить путь скрипта (curl pipe); используйте $XRAY_DATA_DIR/xray-reality.sh"
        if [[ -f "$wrapper_src" ]]; then
            backup_file "$XRAY_SCRIPT_PATH"
            local tmp
            tmp=$(mktemp "${XRAY_SCRIPT_PATH}.tmp.XXXXXX")
            cp -a "$wrapper_src" "$tmp"
            mv "$tmp" "$XRAY_SCRIPT_PATH"
            chmod +x "$XRAY_SCRIPT_PATH"
            log OK "Скрипт установлен: $XRAY_SCRIPT_PATH"
        fi
        return 0
    fi
    backup_file "$XRAY_SCRIPT_PATH"
    local tmp
    tmp=$(mktemp "${XRAY_SCRIPT_PATH}.tmp.XXXXXX")
    cp -a "$src" "$tmp"
    mv "$tmp" "$XRAY_SCRIPT_PATH"
    chmod +x "$XRAY_SCRIPT_PATH"
    log OK "Скрипт установлен: $XRAY_SCRIPT_PATH"
}

setup_logrotate() {
    log STEP "Настраиваем logrotate..."
    local safe_logs_dir safe_health_log safe_install_log safe_update_log safe_diag_log safe_repair_log
    safe_logs_dir=$(printf '%s' "${XRAY_LOGS:-/var/log/xray}" | tr -d '\000-\037\177')
    if [[ -z "$safe_logs_dir" || "$safe_logs_dir" != /* ]]; then
        safe_logs_dir="/var/log/xray"
    fi
    safe_health_log=$(printf '%s' "${HEALTH_LOG:-${safe_logs_dir%/}/xray-health.log}" | tr -d '\000-\037\177')
    if [[ -z "$safe_health_log" || "$safe_health_log" != /* ]]; then
        safe_health_log="${safe_logs_dir%/}/xray-health.log"
    fi
    safe_install_log=$(printf '%s' "${INSTALL_LOG:-/var/log/xray-install.log}" | tr -d '\000-\037\177')
    safe_update_log=$(printf '%s' "${UPDATE_LOG:-/var/log/xray-update.log}" | tr -d '\000-\037\177')
    safe_diag_log=$(printf '%s' "${DIAG_LOG:-/var/log/xray-diagnose.log}" | tr -d '\000-\037\177')
    safe_repair_log="/var/log/xray-repair.log"

    backup_file /etc/logrotate.d/xray
    atomic_write /etc/logrotate.d/xray 0644 << EOF
${safe_logs_dir%/}/access.log ${safe_logs_dir%/}/error.log {
    daily
    rotate 14
    missingok
    notifempty
    compress
    delaycompress
    copytruncate
    create 0640 xray xray
}

${safe_health_log} ${safe_install_log} ${safe_update_log} ${safe_diag_log} ${safe_repair_log} {
    daily
    rotate 14
    missingok
    notifempty
    compress
    delaycompress
    su root root
    copytruncate
    create 0640 root root
}
EOF
    log OK "logrotate настроен"
}

setup_auto_update() {
    log STEP "Настраиваем авто-обновления..."

    if ! systemctl_available; then
        log WARN "systemctl не найден; авто-обновления пропущены"
        return 0
    fi

    if [[ "$AUTO_UPDATE_ONCALENDAR" == *$'\n'* ]] || [[ "$AUTO_UPDATE_ONCALENDAR" =~ [[:cntrl:]] ]]; then
        log ERROR "AUTO_UPDATE_ONCALENDAR содержит недопустимые символы"
        return 1
    fi
    if [[ "$AUTO_UPDATE_RANDOM_DELAY" == *$'\n'* ]] || [[ "$AUTO_UPDATE_RANDOM_DELAY" =~ [[:cntrl:]] ]]; then
        log ERROR "AUTO_UPDATE_RANDOM_DELAY содержит недопустимые символы"
        return 1
    fi
    if ! validate_safe_executable_path "XRAY_SCRIPT_PATH" "$XRAY_SCRIPT_PATH"; then
        return 1
    fi
    if ! validate_safe_executable_path "XRAY_UPDATE_SCRIPT" "$XRAY_UPDATE_SCRIPT"; then
        return 1
    fi

    backup_file "$XRAY_UPDATE_SCRIPT"
    {
        printf '%s\n' '#!/usr/bin/env bash'
        printf '%s\n' 'set -euo pipefail'
        printf 'exec %q update --non-interactive\n' "$XRAY_SCRIPT_PATH"
    } | atomic_write "$XRAY_UPDATE_SCRIPT" 0755

    local _safe_update_script
    _safe_update_script=$(realpath -m "$XRAY_UPDATE_SCRIPT" 2> /dev/null || echo "$XRAY_UPDATE_SCRIPT")

    backup_file /etc/systemd/system/xray-auto-update.service
    atomic_write /etc/systemd/system/xray-auto-update.service 0644 << EOF
[Unit]
Description=Xray Auto Update
After=network.target

[Service]
Type=oneshot
ExecStart=${_safe_update_script}
EOF

    backup_file /etc/systemd/system/xray-auto-update.timer
    atomic_write /etc/systemd/system/xray-auto-update.timer 0644 << EOF
[Unit]
Description=Xray Auto Update Time

[Timer]
OnCalendar=${AUTO_UPDATE_ONCALENDAR}
RandomizedDelaySec=${AUTO_UPDATE_RANDOM_DELAY}
Persistent=true

[Install]
WantedBy=timers.target
EOF

    if ! systemd_running; then
        log WARN "systemd не запущен; авто-обновления пропущены"
        return 0
    fi
    if ! systemctl_run_bounded daemon-reload; then
        log WARN "systemd недоступен; авто-обновления пропущены"
        return 0
    fi
    if [[ "$AUTO_UPDATE" == true ]]; then
        local auto_update_enable_link=""
        local auto_update_enable_link_missing=false
        if auto_update_enable_link=$(systemd_enable_symlink_path_for_unit xray-auto-update.timer 2> /dev/null); then
            if [[ ! -e "$auto_update_enable_link" && ! -L "$auto_update_enable_link" ]]; then
                auto_update_enable_link_missing=true
            fi
        fi
        if systemctl_run_bounded enable --now xray-auto-update.timer; then
            if [[ "$auto_update_enable_link_missing" == true && -n "$auto_update_enable_link" ]] && declare -F record_created_path_literal > /dev/null 2>&1; then
                if [[ -e "$auto_update_enable_link" || -L "$auto_update_enable_link" ]]; then
                    record_created_path_literal "$auto_update_enable_link"
                fi
            fi
            log OK "Авто-обновления включены (${AUTO_UPDATE_ONCALENDAR})"
        else
            log WARN "Не удалось включить авто-обновления"
        fi
    else
        if ! systemctl_run_bounded disable --now xray-auto-update.timer; then
            log WARN "Не удалось отключить авто-обновления через systemd"
        fi
        log INFO "Авто-обновления отключены"
    fi
}
