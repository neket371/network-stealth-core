#!/usr/bin/env bash
# shellcheck shell=bash

GLOBAL_CONTRACT_MODULE="${SCRIPT_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)}/modules/lib/globals_contract.sh"
if [[ ! -f "$GLOBAL_CONTRACT_MODULE" && -n "${XRAY_DATA_DIR:-}" ]]; then
    GLOBAL_CONTRACT_MODULE="$XRAY_DATA_DIR/modules/lib/globals_contract.sh"
fi
if [[ ! -f "$GLOBAL_CONTRACT_MODULE" ]]; then
    echo "ERROR: не найден модуль global contract: $GLOBAL_CONTRACT_MODULE" >&2
    exit 1
fi
# shellcheck source=modules/lib/globals_contract.sh
source "$GLOBAL_CONTRACT_MODULE"

INSTALL_BOOTSTRAP_MODULE="$SCRIPT_DIR/modules/install/bootstrap.sh"
if [[ ! -f "$INSTALL_BOOTSTRAP_MODULE" && -n "${XRAY_DATA_DIR:-}" ]]; then
    INSTALL_BOOTSTRAP_MODULE="$XRAY_DATA_DIR/modules/install/bootstrap.sh"
fi
if [[ ! -f "$INSTALL_BOOTSTRAP_MODULE" ]]; then
    log ERROR "Не найден модуль bootstrap-логики: $INSTALL_BOOTSTRAP_MODULE"
    exit 1
fi
# shellcheck source=/dev/null
source "$INSTALL_BOOTSTRAP_MODULE"

optimize_system() {
    log STEP "Оптимизируем систему..."

    backup_file /etc/sysctl.d/99-xray.conf
    atomic_write /etc/sysctl.d/99-xray.conf 0644 << 'EOF'
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 60
net.ipv4.tcp_keepalive_probes = 5
net.netfilter.nf_conntrack_max = 1048576
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
fs.file-max = 1000000
EOF

    local sysctl_err=""
    if ! sysctl_err=$(sysctl -e -p /etc/sysctl.d/99-xray.conf 2>&1); then
        if [[ "$sysctl_err" =~ [Pp]ermission[[:space:]]denied|[Oo]peration[[:space:]]not[[:space:]]permitted|[Rr]ead-only[[:space:]]file[[:space:]]system ]]; then
            log INFO "Часть sysctl-параметров недоступна в текущей среде (виртуализация/контейнер)"
            debug_file "sysctl apply constraints: $(echo "$sysctl_err" | tr '\n' ';')"
        else
            log WARN "Не удалось полностью применить sysctl; детали сохранены в debug log"
            debug_file "sysctl apply failed: $(echo "$sysctl_err" | tr '\n' ';')"
        fi
    fi

    backup_file /etc/security/limits.d/99-xray.conf
    atomic_write /etc/security/limits.d/99-xray.conf 0644 << 'EOF'
* soft nofile 1000000
* hard nofile 1000000
EOF

    log OK "BBR и оптимизации применены"
}

create_users() {
    log STEP "Создаём непривилегированных пользователей..."

    if ! getent group "$XRAY_GROUP" > /dev/null 2>&1; then
        groupadd -r "$XRAY_GROUP"
        log OK "Группа ${XRAY_GROUP} создана"
    else
        log INFO "Группа ${XRAY_GROUP} уже существует"
    fi
    if ! id "$XRAY_USER" > /dev/null 2>&1; then
        useradd -r -g "$XRAY_GROUP" -s /usr/sbin/nologin -d "$XRAY_HOME" -m "$XRAY_USER"
        log OK "Пользователь ${XRAY_USER} создан"
    else
        log INFO "Пользователь ${XRAY_USER} уже существует"
    fi

    mkdir -p "$XRAY_HOME" "$XRAY_LOGS" "$XRAY_BACKUP" /etc/xray/private /etc/xray-reality
    chown -R "${XRAY_USER}:${XRAY_GROUP}" "$XRAY_HOME" "$XRAY_LOGS"
    chown root:root "$XRAY_BACKUP"
    chmod 700 "$XRAY_BACKUP"
    chmod 750 /etc/xray/private
    chown "root:${XRAY_GROUP}" /etc/xray/private
}

readonly XRAY_MINISIGN_PUBKEY_COMMENT="untrusted comment: Xray-core public key"
readonly XRAY_MINISIGN_PUBKEY_VALUE="RWQklF4zzcXy3MfHKvEqD1nwJ7rX0kGmKeJFgRsJBMHkPJPjZ2fxJhfU"
readonly XRAY_MINISIGN_PUBKEY_SHA256="294701ab7f6e18646e45b5093033d9e64f3ca181f74c0cf232627628f3d8293e"

confirm_minisign_fallback() {
    local reason="${1:-Minisign проверка недоступна}"

    if [[ "$REQUIRE_MINISIGN" == "true" ]]; then
        log ERROR "$reason"
        log ERROR "REQUIRE_MINISIGN=true: продолжение без minisign запрещено"
        hint "Отключите --require-minisign или явно разрешите fallback: --allow-insecure-sha256"
        return 1
    fi

    if [[ "$ALLOW_INSECURE_SHA256" == "true" ]]; then
        return 0
    fi

    if [[ "$NON_INTERACTIVE" == "true" || "$ASSUME_YES" == "true" ]]; then
        log ERROR "$reason"
        log ERROR "Без minisign требуется явное подтверждение yes/no, но включён non-interactive режим"
        hint "Для осознанного продолжения используйте --allow-insecure-sha256"
        return 1
    fi

    local tty_fd=""
    if ! open_interactive_tty_fd tty_fd; then
        log ERROR "$reason"
        log ERROR "Нет доступного TTY для подтверждения fallback-режима minisign"
        hint "Для осознанного продолжения используйте --allow-insecure-sha256"
        return 1
    fi

    printf '\n%b%s%b\n' "$YELLOW" "$reason" "$NC" >&"$tty_fd"
    printf '%b⚠️  Внимание: minisign недоступен или не пройден.%b\n' "$YELLOW" "$NC" >&"$tty_fd"
    printf '%bПродолжить установку только по SHA256?%b\n' "$YELLOW" "$NC" >&"$tty_fd"

    local prompt_rc=0
    if prompt_yes_no_from_tty "$tty_fd" "Подтвердите (yes/no): " "Введите yes или no (без кавычек)"; then
        exec {tty_fd}>&-
        return 0
    fi
    prompt_rc=$?
    exec {tty_fd}>&-
    if ((prompt_rc == 1)); then
        log ERROR "Операция остановлена пользователем: minisign fallback отклонён"
    else
        log ERROR "Не удалось прочитать подтверждение fallback-режима minisign из /dev/tty"
    fi
    return 1
}

handle_minisign_unavailable() {
    local reason="${1:-Minisign недоступен}"

    if [[ "$ALLOW_INSECURE_SHA256" == "true" ]]; then
        log WARN "${reason}; продолжаем только с SHA256 (ALLOW_INSECURE_SHA256=true)"
        SKIP_MINISIGN=true
        return 0
    fi

    if ! confirm_minisign_fallback "$reason"; then
        return 1
    fi

    SKIP_MINISIGN=true
    log INFO "Продолжаем установку только с SHA256 после подтверждения"
    return 0
}

write_pinned_minisign_key() {
    atomic_write "$MINISIGN_KEY" 0644 << EOF
${XRAY_MINISIGN_PUBKEY_COMMENT}
${XRAY_MINISIGN_PUBKEY_VALUE}
EOF

    if command -v sha256sum > /dev/null 2>&1; then
        local actual_sha256=""
        actual_sha256=$(sha256sum "$MINISIGN_KEY" 2> /dev/null | awk '{print $1}')
        if [[ "$actual_sha256" != "$XRAY_MINISIGN_PUBKEY_SHA256" ]]; then
            log ERROR "Fingerprint pinned minisign-ключа не совпадает"
            debug_file "minisign key fingerprint mismatch: got=${actual_sha256:-empty} expected=${XRAY_MINISIGN_PUBKEY_SHA256}"
            return 1
        fi
    else
        local key_line=""
        key_line=$(sed -n '2p' "$MINISIGN_KEY" 2> /dev/null | tr -d '\r' || true)
        if [[ "$key_line" != "$XRAY_MINISIGN_PUBKEY_VALUE" ]]; then
            log ERROR "Pinned minisign-ключ повреждён"
            return 1
        fi
    fi
    return 0
}

install_minisign() {
    log STEP "Устанавливаем minisign для проверки подписей..."
    local minisign_bin="${MINISIGN_BIN:-/usr/local/bin/minisign}"

    if [[ -x "$minisign_bin" ]]; then
        log INFO "minisign уже установлен: ${minisign_bin}"
        SKIP_MINISIGN=false
        return 0
    fi

    if command -v minisign > /dev/null 2>&1; then
        log INFO "minisign уже установлен"
        SKIP_MINISIGN=false
        return 0
    fi

    if command -v apt-get > /dev/null 2>&1 && command -v apt-cache > /dev/null 2>&1; then
        if apt-cache show minisign > /dev/null 2>&1; then
            log INFO "Пробуем установить minisign из репозитория..."
            if $PKG_UPDATE > /dev/null 2>&1 && $PKG_INSTALL minisign > /dev/null 2>&1; then
                if [[ -x "$minisign_bin" ]] || command -v minisign > /dev/null 2>&1; then
                    log OK "minisign установлен из репозитория"
                    SKIP_MINISIGN=false
                    return 0
                fi
            fi
            log WARN "Не удалось установить minisign из репозитория"
        fi
    fi
    if [[ "$ALLOW_UNVERIFIED_MINISIGN_BOOTSTRAP" != "true" ]]; then
        log INFO "Скачивание minisign из интернета отключено по умолчанию"
        log INFO "Для разрешения установите ALLOW_UNVERIFIED_MINISIGN_BOOTSTRAP=true"
        handle_minisign_unavailable "Minisign не установлен и интернет-bootstrap отключён"
        return $?
    fi

    local arch
    case "$(uname -m)" in
        x86_64) arch="amd64" ;;
        aarch64) arch="arm64" ;;
        armv7l) arch="armhf" ;;
        *)
            log WARN "Неподдерживаемая архитектура для minisign"
            handle_minisign_unavailable "Minisign недоступен для архитектуры $(uname -m)"
            return $?
            ;;
    esac

    local version="0.11"
    local tmp_dir
    tmp_dir=$(mktemp -d) || {
        handle_minisign_unavailable "Не удалось создать временную директорию для minisign"
        return $?
    }
    local tarball=""
    local -a bases=()
    local downloaded=false
    local base

    while read -r base; do
        [[ -n "$base" ]] && bases+=("$base")
    done < <(build_mirror_list "https://github.com/jedisct1/minisign/releases/download/${version}" "$MINISIGN_MIRRORS" "$version")
    local gh_proxy_base="${GH_PROXY_BASE:-https://ghproxy.com/https://github.com}"
    gh_proxy_base="${gh_proxy_base%/}"
    if [[ -n "$gh_proxy_base" ]]; then
        bases+=("${gh_proxy_base}/jedisct1/minisign/releases/download/${version}")
    fi

    declare -A seen=()
    for base in "${bases[@]}"; do
        base="${base%/}"
        [[ -z "$base" || -n "${seen[$base]:-}" ]] && continue
        seen["$base"]=1
        rm -rf "$tmp_dir"
        mkdir -p "$tmp_dir"
        tarball="${tmp_dir}/minisign.tar.gz"
        log INFO "Пробуем источник minisign: $base"
        if ! download_file_allowlist "${base}/minisign-linux-${arch}.tar.gz" "$tarball" "Скачиваем minisign..."; then
            log WARN "Не удалось скачать minisign из $base"
            continue
        fi
        if ! tar tzf "$tarball" > /dev/null 2>&1; then
            log WARN "Архив minisign повреждён ($base)"
            continue
        fi
        if ! tar xzf "$tarball" -C "$tmp_dir" > /dev/null 2>&1; then
            log WARN "Не удалось распаковать minisign ($base)"
            continue
        fi
        downloaded=true
        break
    done

    if [[ "$downloaded" != true ]]; then
        log WARN "Не удалось скачать minisign"
        rm -rf "$tmp_dir"
        handle_minisign_unavailable "Minisign недоступен после попыток загрузки"
        return $?
    fi

    local bin_path
    bin_path=$(find "$tmp_dir" -type f -name minisign -print -quit 2> /dev/null || true)
    if [[ -n "$bin_path" ]]; then
        install -m 755 "$bin_path" "$minisign_bin"
    fi
    rm -rf "$tmp_dir"

    if [[ -x "$minisign_bin" ]]; then
        log OK "minisign установлен"
        SKIP_MINISIGN=false
    else
        log WARN "Не удалось установить minisign"
        handle_minisign_unavailable "Minisign не удалось установить из загруженного архива"
        return $?
    fi
}

install_xray() {
    log STEP "Устанавливаем Xray-core с криптографической проверкой..."

    local tmp_workdir=""
    local temp_dir=""
    local sig_file=""
    # shellcheck disable=SC2317,SC2329
    cleanup_install_xray_tmp() {
        rm -f "${sig_file:-}" 2> /dev/null || true
        [[ -n "${temp_dir:-}" ]] && rm -rf "$temp_dir"
        [[ -n "${tmp_workdir:-}" ]] && rm -rf "$tmp_workdir"
        trap - RETURN
    }
    trap cleanup_install_xray_tmp RETURN

    local arch
    case "$(uname -m)" in
        x86_64) arch="64" ;;
        aarch64) arch="arm64-v8a" ;;
        armv7l) arch="arm32-v7a" ;;
        *)
            log ERROR "Неподдерживаемая архитектура: $(uname -m)"
            return 1
            ;;
    esac

    local version
    version="$(trim_ws "${XRAY_VERSION:-}")"
    if [[ "${version,,}" == "latest" ]]; then
        version=""
    fi
    if [[ -z "$version" ]]; then
        version=$(curl_fetch_text_allowlist "https://api.github.com/repos/XTLS/Xray-core/releases/latest" 2> /dev/null |
            jq -r '.tag_name' 2> /dev/null |
            sed 's/^v//' || true)
    fi
    if [[ -z "$version" || "$version" == "null" ]]; then
        local latest_url
        latest_url=$(curl_fetch_text_allowlist "https://github.com/XTLS/Xray-core/releases/latest" -o /dev/null -w "%{url_effective}" 2> /dev/null || true)
        if [[ -n "$latest_url" ]]; then
            version=$(basename "$latest_url" | sed 's/^v//')
        fi
    fi
    if [[ -z "$version" || "$version" == "null" ]]; then
        log ERROR "Не удалось получить версию Xray"
        return 1
    fi

    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9._-]+)?$ ]]; then
        log ERROR "Неверный формат версии Xray: $version"
        return 1
    fi

    log INFO "Версия Xray: ${BOLD}${version}${NC}"

    local tmp_base="${TMPDIR:-/tmp}"
    tmp_workdir=$(mktemp -d "${tmp_base}/xray-${version}.XXXXXX") || {
        log ERROR "Не удалось создать временную директорию для загрузки Xray"
        return 1
    }
    local zip_file="${tmp_workdir}/Xray-linux-${arch}.zip"
    local dgst_file="${tmp_workdir}/Xray-linux-${arch}.zip.dgst"
    local used_base=""
    local -a bases=()
    local downloaded=false
    local base

    while read -r base; do
        [[ -n "$base" ]] && bases+=("$base")
    done < <(build_mirror_list "https://github.com/XTLS/Xray-core/releases/download/v${version}" "$XRAY_MIRRORS" "$version")
    local gh_proxy_base="${GH_PROXY_BASE:-https://ghproxy.com/https://github.com}"
    gh_proxy_base="${gh_proxy_base%/}"
    if [[ -n "$gh_proxy_base" ]]; then
        bases+=("${gh_proxy_base}/XTLS/Xray-core/releases/download/v${version}")
    fi

    declare -A seen=()
    for base in "${bases[@]}"; do
        base="${base%/}"
        [[ -z "$base" || -n "${seen[$base]:-}" ]] && continue
        seen["$base"]=1
        log INFO "Пробуем источник Xray: $base"
        rm -f "$zip_file" "$dgst_file"
        if ! download_file_allowlist "${base}/Xray-linux-${arch}.zip" "$zip_file" "Скачиваем Xray..."; then
            log WARN "Не удалось скачать Xray из $base"
            continue
        fi
        if [[ ! -s "$zip_file" ]]; then
            log WARN "Архив Xray пустой ($base)"
            continue
        fi
        local expected_sha256=""
        local dgst_ok=false
        local dgst_base=""
        local -A dgst_seen=()
        for dgst_base in "$base" "${bases[@]}"; do
            dgst_base="${dgst_base%/}"
            [[ -z "$dgst_base" || -n "${dgst_seen[$dgst_base]:-}" ]] && continue
            dgst_seen["$dgst_base"]=1
            if ! download_file_allowlist "${dgst_base}/Xray-linux-${arch}.zip.dgst" "$dgst_file" "Скачиваем SHA256..."; then
                continue
            fi
            expected_sha256=$(awk -F'= *' 'toupper($1) ~ /SHA(2-)?256/ {print $2; exit}' "$dgst_file" 2> /dev/null || true)
            if [[ -n "$expected_sha256" ]]; then
                dgst_ok=true
                break
            fi
            expected_sha256=""
            log WARN "Не удалось прочитать SHA256 из $dgst_file ($dgst_base)"
        done
        if [[ "$dgst_ok" != true ]]; then
            log WARN "Не удалось скачать/прочитать .dgst из доступных источников"
            continue
        fi
        local actual_sha256
        actual_sha256=$(sha256sum "$zip_file" | awk '{print $1}')

        if [[ "$expected_sha256" != "$actual_sha256" ]]; then
            log WARN "SHA256 не совпадает ($base)"
            continue
        fi

        downloaded=true
        used_base="$base"
        break
    done

    if [[ "$downloaded" != true ]]; then
        log ERROR "Не удалось скачать Xray с проверкой SHA256"
        return 1
    fi

    log OK "✓ SHA256 проверка пройдена"

    if [[ "$SKIP_MINISIGN" == true ]]; then
        if [[ "$REQUIRE_MINISIGN" == "true" && "$ALLOW_INSECURE_SHA256" != "true" ]]; then
            log ERROR "Minisign недоступен, а REQUIRE_MINISIGN=true"
            return 1
        fi
        log INFO "Minisign недоступен; продолжаем только с SHA256"
    else
        log INFO "Проверяем minisign подпись (если доступна в релизе)..."

        sig_file=$(mktemp "${tmp_workdir}/xray-${version}.XXXXXX.minisig" 2> /dev/null || true)
        if [[ -z "$sig_file" ]]; then
            if ! confirm_minisign_fallback "Не удалось создать временный файл подписи minisign"; then
                return 1
            fi
            if [[ "$ALLOW_INSECURE_SHA256" == "true" ]]; then
                log WARN "Не удалось создать временный файл подписи; продолжаем только с SHA256 (ALLOW_INSECURE_SHA256=true)"
            else
                log INFO "Не удалось создать временный файл подписи; продолжаем только с SHA256 после подтверждения"
            fi
        fi
        local sig_downloaded=false
        is_minisig_file() {
            local f="$1"
            [[ -s "$f" ]] || return 1
            local line1 line2
            line1="$(head -n 1 "$f" 2> /dev/null | tr -d '\r' || true)"
            line2="$(head -n 2 "$f" 2> /dev/null | tail -n 1 | tr -d '\r' || true)"
            [[ "$line1" == untrusted\ comment:* ]] || return 1
            [[ "$line2" =~ ^R[0-9A-Za-z+/=]{40,}$ ]] || return 1
            return 0
        }
        local -a sig_bases=("$used_base")
        sig_bases+=("${bases[@]}")
        declare -A sig_seen=()
        for base in "${sig_bases[@]}"; do
            [[ -n "$sig_file" ]] || break
            base="${base%/}"
            [[ -z "$base" || -n "${sig_seen[$base]:-}" ]] && continue
            sig_seen["$base"]=1
            rm -f "$sig_file"
            local sig_err_file
            sig_err_file=$(mktemp "${tmp_workdir}/xray-${version}.XXXXXX.sigerr" 2> /dev/null || true)
            if [[ -z "$sig_err_file" ]]; then
                sig_err_file="/dev/null"
            fi
            if download_file_allowlist "${base}/Xray-linux-${arch}.zip.minisig" "$sig_file" "Скачиваем minisign подпись..." 2> "$sig_err_file"; then
                if ! is_minisig_file "$sig_file"; then
                    log INFO "Источник minisign подписи вернул невалидный формат, пропускаем: $base"
                    debug_file "invalid minisig payload from ${base}"
                    rm -f "$sig_file"
                    [[ "$sig_err_file" != "/dev/null" ]] && rm -f "$sig_err_file"
                    continue
                fi
                sig_downloaded=true
                [[ "$sig_err_file" != "/dev/null" ]] && rm -f "$sig_err_file"
                break
            else
                local sig_err_line=""
                if [[ -f "$sig_err_file" ]]; then
                    sig_err_line=$(head -n 1 "$sig_err_file" 2> /dev/null | tr -d '\r' || true)
                fi
                if [[ "$sig_err_line" == *"requested URL returned error: 404"* ]]; then
                    debug_file "minisign signature missing at ${base} (404)"
                elif [[ -n "$sig_err_line" ]]; then
                    log WARN "Источник minisign подписи недоступен: ${base}"
                    debug_file "minisign download failed from ${base}: ${sig_err_line}"
                fi
            fi
            [[ "$sig_err_file" != "/dev/null" ]] && rm -f "$sig_err_file"
        done
        if [[ "$sig_downloaded" != true ]]; then
            if ! confirm_minisign_fallback "Minisign подпись не найдена в релизе"; then
                return 1
            fi
            if [[ "$ALLOW_INSECURE_SHA256" == "true" ]]; then
                log INFO "Minisign подпись не найдена в релизе; продолжаем только с SHA256 (ALLOW_INSECURE_SHA256=true)"
            else
                log INFO "Minisign подпись не найдена в релизе; продолжаем только с SHA256 после подтверждения"
            fi
        fi

        if [[ "$sig_downloaded" == true && -n "$sig_file" && -f "$sig_file" ]]; then
            local minisign_cmd="minisign"
            if [[ -n "${MINISIGN_BIN:-}" && -x "${MINISIGN_BIN}" ]]; then
                minisign_cmd="${MINISIGN_BIN}"
            fi
            if ! write_pinned_minisign_key; then
                return 1
            fi

            if "$minisign_cmd" -Vm "$zip_file" -p "$MINISIGN_KEY" -x "$sig_file" > /dev/null 2>&1; then
                log OK "✓ Minisign подпись верна"
            else
                if [[ "$ALLOW_INSECURE_SHA256" == true ]]; then
                    log WARN "Minisign подпись не прошла (возможно, ключ обновился); продолжаем с SHA256"
                else
                    if ! confirm_minisign_fallback "Ошибка проверки minisign подписи"; then
                        return 1
                    fi
                    log WARN "Продолжаем только с SHA256 после подтверждения оператора"
                fi
            fi
            rm -f "$sig_file"
        fi
    fi

    temp_dir=$(mktemp -d "${tmp_base}/xray-install.XXXXXX") || {
        log ERROR "Не удалось создать временную директорию"
        return 1
    }
    if ! unzip -q "$zip_file" -d "$temp_dir"; then
        log ERROR "Не удалось распаковать архив Xray"
        return 1
    fi

    if [[ ! -f "$temp_dir/xray" ]]; then
        log ERROR "Бинарник xray не найден в архиве"
        return 1
    fi

    install -m 755 "$temp_dir/xray" "$XRAY_BIN"
    local xray_asset_dir
    xray_asset_dir="$(xray_geo_dir)"
    mkdir -p "$xray_asset_dir"
    local asset
    for asset in geoip.dat geosite.dat; do
        if [[ -f "$temp_dir/$asset" ]]; then
            install -m 644 "$temp_dir/$asset" "$xray_asset_dir/$asset"
        else
            log WARN "В архиве Xray не найден ${asset}; возможны ошибки geoip/geosite"
        fi
    done
    if command -v restorecon > /dev/null 2>&1; then
        restorecon -v "$XRAY_BIN" > /dev/null 2>&1 || log WARN "restorecon не применился для $XRAY_BIN"
    elif command -v getenforce > /dev/null 2>&1 && [[ "$(getenforce)" == "Enforcing" ]]; then
        log WARN "SELinux Enforcing: restorecon не найден (пакет policycoreutils)"
    fi
    if command -v setcap > /dev/null 2>&1; then
        if ! setcap cap_net_bind_service=+ep "$XRAY_BIN"; then
            log WARN "Не удалось выдать CAP_NET_BIND_SERVICE для $XRAY_BIN"
        fi
    else
        log WARN "setcap не найден; порты ниже 1024 могут не работать"
    fi

    local installed_version version_output first_line
    version_output=$("$XRAY_BIN" version 2> /dev/null || true)
    first_line=$(printf '%s\n' "$version_output" | sed -n '1p')
    installed_version=$(printf '%s\n' "$first_line" | awk '{print $2}')
    log OK "Xray ${installed_version} установлен и проверен"
    return 0
}

detect_ips() {
    log STEP "Определяем IP-адреса сервера..."

    if [[ -z "${SERVER_IP:-}" ]]; then
        SERVER_IP=$(fetch_ip 4 || true)
    else
        log INFO "IPv4 задан заранее: ${SERVER_IP}"
    fi
    if [[ -z "$SERVER_IP" ]]; then
        log ERROR "Не удалось определить IPv4 автоматически. Укажите SERVER_IP или --server-ip."
        exit 1
    fi

    if ! is_valid_ipv4 "$SERVER_IP"; then
        log ERROR "Некорректный IPv4 адрес: $SERVER_IP"
        log INFO "Подсказка: используйте формат X.X.X.X (например: 185.100.50.25)"
        exit 1
    fi

    log OK "IPv4: ${BOLD}${SERVER_IP}${NC}"

    if [[ -z "${SERVER_IP6:-}" ]]; then
        SERVER_IP6=$(fetch_ip 6 || true)
    else
        log INFO "IPv6 задан заранее: ${SERVER_IP6}"
    fi

    if [[ -n "$SERVER_IP6" ]]; then
        if is_valid_ipv6 "$SERVER_IP6"; then
            log OK "IPv6: ${BOLD}${SERVER_IP6}${NC}"
            HAS_IPV6=true
        else
            log WARN "Авто-детект вернул невалидный IPv6: ${SERVER_IP6} (IPv6 отключён)"
            SERVER_IP6=""
            HAS_IPV6=false
        fi
    else
        log INFO "IPv6 недоступен"
        HAS_IPV6=false
    fi
    : "${HAS_IPV6}"

    echo ""
}

auto_configure() {
    SPIDER_MODE=$(parse_bool "$SPIDER_MODE" true)
    validate_install_config
    log OK "Авто-конфигурация: ${DOMAIN_TIER}, transport=${TRANSPORT}, порт ${START_PORT}, ${NUM_CONFIGS} конфигов, spider=${SPIDER_MODE}"
}

auto_profile_default_num_configs() {
    local tier_raw="${1:-tier_ru}"
    local tier
    if ! tier=$(normalize_domain_tier "$tier_raw"); then
        tier="tier_ru"
    fi
    case "$tier" in
        tier_global_ms10) echo 10 ;;
        *) echo 5 ;;
    esac
}

ask_domain_profile() {
    local has_tty=false
    if [[ -t 0 || -t 1 || -t 2 ]]; then
        has_tty=true
    fi
    AUTO_PROFILE_MODE=false

    if [[ "$REUSE_EXISTING_CONFIG" == true ]]; then
        local requested_profile="${XRAY_DOMAIN_PROFILE:-${XRAY_DOMAIN_TIER:-}}"
        if [[ -n "$requested_profile" ]]; then
            local installed_tier requested_tier
            installed_tier="${DOMAIN_TIER:-tier_ru}"
            if ! installed_tier=$(normalize_domain_tier "$installed_tier" 2> /dev/null); then
                installed_tier="tier_ru"
            fi
            if requested_tier=$(normalize_domain_tier "$requested_profile" 2> /dev/null); then
                if [[ "$requested_tier" != "$installed_tier" ]]; then
                    log WARN "REUSE_EXISTING=true: запрошенный профиль ${requested_profile} игнорируется (используется установленный ${installed_tier})"
                fi
            else
                log WARN "REUSE_EXISTING=true: запрошенный профиль ${requested_profile} невалиден и игнорируется"
            fi
        fi
        return 0
    fi

    if [[ -n "${XRAY_DOMAIN_PROFILE:-}" ]] || [[ -n "${XRAY_DOMAIN_TIER:-}" ]]; then
        local explicit_profile="${XRAY_DOMAIN_PROFILE:-${XRAY_DOMAIN_TIER:-$DOMAIN_TIER}}"
        if is_legacy_global_profile_alias "$explicit_profile"; then
            log WARN "Профиль ${explicit_profile} является legacy-алиасом; используйте global-50 или global-50-auto"
        fi
        if is_auto_domain_profile_alias "$explicit_profile"; then
            AUTO_PROFILE_MODE=true
        fi
        if ! DOMAIN_TIER=$(normalize_domain_tier "$explicit_profile"); then
            DOMAIN_TIER="tier_ru"
        fi
        if [[ "$AUTO_PROFILE_MODE" == "true" ]]; then
            log INFO "Используем авто-профиль доменов: ${explicit_profile} -> $(domain_tier_label "$DOMAIN_TIER") (${DOMAIN_TIER})"
        else
            log INFO "Используем профиль доменов из параметров: $(domain_tier_label "$DOMAIN_TIER") (${DOMAIN_TIER})"
        fi
        return 0
    fi

    if [[ "${ADVANCED_MODE:-false}" != "true" ]]; then
        DOMAIN_TIER="tier_ru"
        AUTO_PROFILE_MODE=true
        log INFO "Минимальный install path: профиль доменов ru-auto (${DOMAIN_TIER})"
        return 0
    fi

    if [[ "$NON_INTERACTIVE" == "true" ]]; then
        DOMAIN_TIER="tier_ru"
        AUTO_PROFILE_MODE=true
        log INFO "Non-interactive режим: профиль доменов по умолчанию ru-auto (${DOMAIN_TIER})"
        return 0
    fi

    if [[ "$has_tty" != "true" ]]; then
        log ERROR "Не удалось открыть /dev/tty для выбора профиля доменов"
        exit 1
    fi

    local tty_fd=""
    if ! open_interactive_tty_fd tty_fd; then
        log ERROR "Не удалось открыть /dev/tty для выбора профиля доменов"
        exit 1
    fi

    printf '\n' >&"$tty_fd"
    local input
    while true; do
        printf '%s\n' "Выберите профиль доменов:" >&"$tty_fd"
        printf '%s\n' "  1) ru (ручной ввод числа ключей, до 100)" >&"$tty_fd"
        printf '%s\n' "  2) global-50 (ручной ввод числа ключей, до 10)" >&"$tty_fd"
        printf '%s\n' "  3) ru-auto (автоматически: 5 ключей)" >&"$tty_fd"
        printf '%s\n' "  4) global-50-auto (автоматически: 10 ключей)" >&"$tty_fd"
        if ! printf "Профиль [1/2/3/4]: " >&"$tty_fd"; then
            exec {tty_fd}>&-
            log ERROR "Не удалось вывести запрос выбора профиля в /dev/tty"
            exit 1
        fi
        if ! read -r -u "$tty_fd" input; then
            exec {tty_fd}>&-
            log ERROR "Не удалось прочитать выбор профиля из /dev/tty"
            exit 1
        fi
        input=$(normalize_tty_input "$input")
        case "${input,,}" in
            "" | 1 | ru | russia | rf | tier_ru)
                DOMAIN_TIER="tier_ru"
                AUTO_PROFILE_MODE=false
                break
                ;;
            2 | global | global-50 | g50 | tier_global_50)
                DOMAIN_TIER="tier_global_ms10"
                AUTO_PROFILE_MODE=false
                break
                ;;
            global-ms10 | ms10 | tier_global_ms10)
                DOMAIN_TIER="tier_global_ms10"
                AUTO_PROFILE_MODE=false
                log WARN "Профиль ${input} является legacy-алиасом; используйте global-50"
                break
                ;;
            3 | ru-auto | russia-auto | rf-auto | tier_ru_auto)
                DOMAIN_TIER="tier_ru"
                AUTO_PROFILE_MODE=true
                break
                ;;
            4 | global-auto | global-50-auto | g50-auto | tier_global_50_auto)
                DOMAIN_TIER="tier_global_ms10"
                AUTO_PROFILE_MODE=true
                break
                ;;
            global-ms10-auto | ms10-auto | tier_global_ms10_auto)
                DOMAIN_TIER="tier_global_ms10"
                AUTO_PROFILE_MODE=true
                log WARN "Профиль ${input} является legacy-алиасом; используйте global-50-auto"
                break
                ;;
            *)
                printf '%bВведите 1, 2, 3 или 4 (пустой ввод = ru)%b\n' "$RED" "$NC" >&"$tty_fd"
                ;;
        esac
    done
    exec {tty_fd}>&-
    if ! DOMAIN_TIER=$(normalize_domain_tier "$DOMAIN_TIER"); then
        DOMAIN_TIER="tier_ru"
    fi
    if [[ "$AUTO_PROFILE_MODE" == "true" ]]; then
        log OK "Профиль доменов: $(domain_tier_label "$DOMAIN_TIER") (${DOMAIN_TIER}, auto)"
    else
        log OK "Профиль доменов: $(domain_tier_label "$DOMAIN_TIER") (${DOMAIN_TIER})"
    fi
    echo ""
}

ask_num_configs() {
    local has_tty=false
    if [[ -t 0 || -t 1 || -t 2 ]]; then
        has_tty=true
    fi

    if [[ "$REUSE_EXISTING_CONFIG" == true ]]; then
        return 0
    fi

    local max_configs
    max_configs=$(max_configs_for_tier "$DOMAIN_TIER")

    if [[ -n "${XRAY_NUM_CONFIGS:-}" ]]; then
        if [[ "$XRAY_NUM_CONFIGS" =~ ^[0-9]+$ ]] && ((XRAY_NUM_CONFIGS >= 1 && XRAY_NUM_CONFIGS <= max_configs)); then
            NUM_CONFIGS="$XRAY_NUM_CONFIGS"
            log INFO "Используем переданный NUM_CONFIGS=${NUM_CONFIGS}"
            return 0
        fi
        log ERROR "Некорректное значение --num-configs: ${XRAY_NUM_CONFIGS} (допустимо 1-${max_configs})"
        exit 1
    fi

    if [[ "${AUTO_PROFILE_MODE:-false}" == "true" ]] || [[ "${ADVANCED_MODE:-false}" != "true" ]] || [[ "$NON_INTERACTIVE" == "true" ]]; then
        NUM_CONFIGS=$(auto_profile_default_num_configs "$DOMAIN_TIER")
        log INFO "Количество ключей выбрано автоматически (${NUM_CONFIGS})"
        return 0
    fi

    if [[ "$has_tty" != "true" ]]; then
        log ERROR "Не удалось открыть /dev/tty для обязательного ввода NUM_CONFIGS"
        exit 1
    fi

    local tty_fd=""
    if ! open_interactive_tty_fd tty_fd; then
        log ERROR "Не удалось открыть /dev/tty для обязательного ввода NUM_CONFIGS"
        exit 1
    fi

    printf '\n' >&"$tty_fd"
    local input
    while true; do
        if ! printf "Количество VPN-ключей (1-%s): " "$max_configs" >&"$tty_fd"; then
            exec {tty_fd}>&-
            log ERROR "Не удалось вывести запрос NUM_CONFIGS в /dev/tty"
            exit 1
        fi
        if ! read -r -u "$tty_fd" input; then
            exec {tty_fd}>&-
            log ERROR "Не удалось прочитать значение NUM_CONFIGS из /dev/tty"
            exit 1
        fi
        input=$(normalize_tty_input "$input")
        if [[ "$input" =~ ^[0-9]+$ ]] && ((input >= 1 && input <= max_configs)); then
            exec {tty_fd}>&-
            NUM_CONFIGS="$input"
            log OK "Количество ключей: ${NUM_CONFIGS}"
            echo ""
            return 0
        fi
        printf '%bВведите число от 1 до %s (пустой ввод не допускается)%b\n' "$RED" "$max_configs" "$NC" >&"$tty_fd"
    done
}

install_flow() {
    INSTALL_START_TIME=$(date +%s)
    LOG_CONTEXT="установки"
    : "${LOG_CONTEXT}"
    setup_logging
    resolve_paths
    detect_distro
    check_disk_space
    install_dependencies
    require_cmd curl
    require_cmd jq
    require_cmd openssl

    require_cmd unzip
    install_self
    setup_logrotate
    optimize_system
    create_users
    install_minisign
    install_xray
    maybe_reuse_existing_config || true
    ask_domain_profile
    ask_num_configs
    detect_ips
    auto_configure
    setup_domains
    allocate_ports
    generate_keys
    build_config
    create_systemd_service
    setup_diagnose_service
    configure_firewall
    save_environment
    setup_health_monitoring
    setup_auto_update
    save_client_configs
    if declare -F export_all_configs > /dev/null 2>&1; then
        export_all_configs
    fi
    if ! verify_ports_available; then
        log ERROR "Некоторые порты заняты. Перезапустите установку."
        exit 1
    fi
    start_services
    if ! verify_ports_listening_after_start; then
        log ERROR "Проверка listening-портов после запуска не пройдена."
        exit 1
    fi
    test_reality_connectivity
    if ! post_action_verdict "install"; then
        log ERROR "Финальная self-check (install) завершилась с verdict=BROKEN"
        exit 1
    fi
    show_install_result
}

show_install_result() {
    local duration=""
    if [[ -n "${INSTALL_START_TIME:-}" ]]; then
        local elapsed=$(($(date +%s) - INSTALL_START_TIME))
        duration=" за ${elapsed}s"
    fi

    echo ""
    local title="УСТАНОВКА УСПЕШНО ЗАВЕРШЕНА${duration}"
    local box_width box_top box_line box_bottom
    box_width=$(ui_box_width_for_lines 60 90 "$title")
    box_top=$(ui_box_border_string top "$box_width")
    box_line=$(ui_box_line_string "$title" "$box_width")
    box_bottom=$(ui_box_border_string bottom "$box_width")
    echo -e "${BOLD}${GREEN}${box_top}${NC}"
    echo -e "${BOLD}${GREEN}${box_line}${NC}"
    echo -e "${BOLD}${GREEN}${box_bottom}${NC}"
    echo ""

    local client_file="${XRAY_KEYS}/clients.txt"
    if [[ -f "$client_file" ]]; then
        print_secret_file_to_tty "$client_file" "Клиентские ссылки" || true
    fi

    echo -e "${BOLD}📁 Файлы:${NC}"
    echo -e "  Клиентские конфиги: ${XRAY_KEYS}/clients.txt"
    echo -e "  Клиентские конфиги (JSON): ${XRAY_KEYS}/clients.json"
    if [[ -d "${XRAY_KEYS}/qr" ]]; then
        echo -e "  QR-коды: ${XRAY_KEYS}/qr/"
    fi
    if [[ -d "${XRAY_KEYS}/export" ]]; then
        echo -e "  Экспорт: ${XRAY_KEYS}/export/ (raw xray, client templates)"
    fi
    echo -e "  Конфигурация Xray: ${XRAY_CONFIG}"
    echo -e "  Окружение: ${XRAY_ENV}"
    echo ""
    echo -e "${BOLD}🔧 Управление:${NC}"
    echo -e "  Статус:    ${YELLOW}xray-reality.sh status${NC}"
    echo -e "  Логи:      ${YELLOW}xray-reality.sh logs${NC}"
    echo -e "  Обновить:  ${YELLOW}xray-reality.sh update${NC}"
    echo -e "  Удалить:   ${YELLOW}xray-reality.sh uninstall${NC}"
    echo ""

}

update_flow() {
    LOG_CONTEXT="обновления"
    : "${LOG_CONTEXT}"
    INSTALL_LOG="$UPDATE_LOG"
    : "${INSTALL_LOG}"
    setup_logging
    resolve_paths
    detect_distro
    install_dependencies
    require_cmd curl
    require_cmd jq
    require_cmd openssl

    require_cmd unzip
    install_self
    setup_logrotate
    update_xray
    setup_diagnose_service
    setup_auto_update
    if ! post_action_verdict "update"; then
        log ERROR "Финальная self-check (update) завершилась с verdict=BROKEN"
        exit 1
    fi
    log OK "Обновление завершено"
}

repair_flow() {
    LOG_CONTEXT="восстановления"
    : "${LOG_CONTEXT}"
    INSTALL_LOG="/var/log/xray-repair.log"
    : "${INSTALL_LOG}"
    setup_logging
    resolve_paths
    detect_distro
    install_dependencies
    require_cmd curl
    require_cmd jq
    require_cmd openssl
    require_cmd unzip

    install_self
    setup_logrotate
    create_users
    install_minisign

    if [[ ! -x "$XRAY_BIN" ]]; then
        log WARN "Бинарник Xray не найден; устанавливаем заново"
        install_xray
    fi

    local config_ready=false
    if [[ -f "$XRAY_CONFIG" ]]; then
        if ! jq empty "$XRAY_CONFIG" > /dev/null 2>&1; then
            log ERROR "Найденный config.json повреждён (невалидный JSON)"
            exit 1
        fi
        if ! xray_config_test_ok "$XRAY_CONFIG"; then
            log ERROR "Текущий config.json не проходит xray -test"
            exit 1
        fi
        config_ready=true
    else
        log WARN "Конфигурация Xray не найдена: ${XRAY_CONFIG}"
    fi

    create_systemd_service
    setup_diagnose_service

    if [[ "$config_ready" == "true" ]]; then
        load_existing_ports_from_config
        load_existing_metadata_from_config
        load_keys_from_config
        if ((${#PORTS[@]} > 0)); then
            configure_firewall
        else
            log WARN "В config.json нет inbounds для восстановления правил firewall"
        fi
    fi

    setup_health_monitoring
    setup_auto_update

    if [[ "$config_ready" == "true" ]]; then
        start_services
        if ((${#PORTS[@]} > 0)); then
            if ! verify_ports_listening_after_start; then
                log WARN "После repair часть портов не слушается"
            fi
            test_reality_connectivity || true
        fi
        if client_artifacts_missing || client_artifacts_inconsistent "${#PORTS[@]}"; then
            if ! rebuild_client_artifacts_from_config; then
                log WARN "Не удалось полностью восстановить клиентские артефакты"
            fi
        fi

        NUM_CONFIGS=${#PORTS[@]}
        if ((NUM_CONFIGS > 0)); then
            START_PORT="${PORTS[0]}"
        fi
        if [[ -z "${SERVER_IP:-}" ]]; then
            SERVER_IP=$(fetch_ip 4 || true)
        fi
        if [[ -z "${SERVER_IP6:-}" ]]; then
            SERVER_IP6=$(fetch_ip 6 || true)
        fi
        save_environment || log WARN "Не удалось обновить окружение после repair"
    fi

    if ! post_action_verdict "repair"; then
        log ERROR "Финальная self-check (repair) завершилась с verdict=BROKEN"
        exit 1
    fi

    log OK "Восстановление завершено"
}

migrate_stealth_flow() {
    LOG_CONTEXT="миграции transport"
    : "${LOG_CONTEXT}"
    INSTALL_LOG="/var/log/xray-migrate-stealth.log"
    : "${INSTALL_LOG}"
    setup_logging
    resolve_paths
    detect_distro
    install_dependencies
    require_cmd curl
    require_cmd jq
    require_cmd openssl
    require_cmd unzip

    install_self
    setup_logrotate
    create_users
    install_minisign

    if [[ -x "$XRAY_BIN" ]]; then
        update_xray
    else
        install_xray
    fi

    if [[ ! -f "$XRAY_CONFIG" ]]; then
        log ERROR "Конфигурация Xray не найдена: ${XRAY_CONFIG}"
        exit 1
    fi
    if ! jq empty "$XRAY_CONFIG" > /dev/null 2>&1; then
        log ERROR "config.json повреждён (невалидный JSON)"
        exit 1
    fi
    if ! xray_config_test_ok "$XRAY_CONFIG"; then
        log ERROR "Текущий config.json не проходит xray -test"
        exit 1
    fi

    load_existing_ports_from_config
    load_existing_metadata_from_config
    load_keys_from_config
    NUM_CONFIGS=${#PORTS[@]}
    if ((NUM_CONFIGS < 1)); then
        log ERROR "Не найдены managed reality inbounds для миграции"
        exit 1
    fi
    if ! build_public_keys_for_current_config; then
        exit 1
    fi

    if [[ -z "${SERVER_IP:-}" ]]; then
        detect_ips
    fi

    MUX_MODE="off"
    if [[ "${TRANSPORT:-xhttp}" == "xhttp" ]]; then
        log INFO "Managed transport уже использует xhttp; обновляем только артефакты и окружение"
    else
        log WARN "Обнаружен legacy transport (${TRANSPORT}); выполняем миграцию на xhttp"
        if ! rebuild_config_for_transport "xhttp"; then
            log ERROR "Не удалось пересобрать config.json под xhttp"
            exit 1
        fi
    fi

    create_systemd_service
    setup_diagnose_service
    configure_firewall
    setup_health_monitoring
    setup_auto_update
    save_environment
    start_services
    if ! verify_ports_listening_after_start; then
        log ERROR "Проверка listening-портов после migrate-stealth не пройдена."
        exit 1
    fi
    test_reality_connectivity
    rebuild_client_artifacts_from_config || exit 1
    if ! post_action_verdict "migrate-stealth"; then
        log ERROR "Финальная self-check (migrate-stealth) завершилась с verdict=BROKEN"
        exit 1
    fi
    log OK "Миграция на xhttp завершена"
}

diagnose_flow() {
    LOG_CONTEXT="диагностики"
    : "${LOG_CONTEXT}"
    INSTALL_LOG="$DIAG_LOG"
    : "${INSTALL_LOG}"
    setup_logging
    diagnose
}

rollback_flow() {
    LOG_CONTEXT="отката"
    : "${LOG_CONTEXT}"
    setup_logging
    rollback_from_session "$ROLLBACK_DIR"
}

uninstall_flow() {
    LOG_CONTEXT="удаления"
    : "${LOG_CONTEXT}"
    if ! uninstall_has_managed_artifacts; then
        echo ""
        log INFO "Network Stealth Core уже удалён: управляемые артефакты не обнаружены"
        return 0
    fi
    setup_logging
    uninstall_all
}
