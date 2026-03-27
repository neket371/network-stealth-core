#!/usr/bin/env bash
# shellcheck shell=bash

: "${MINISIGN_KEY:=/etc/xray/private/minisign.pub}"
: "${PKG_UPDATE:=:}"
: "${PKG_INSTALL:=:}"
: "${REQUIRE_MINISIGN:=false}"
: "${ALLOW_INSECURE_SHA256:=false}"
: "${NON_INTERACTIVE:=false}"
: "${ASSUME_YES:=false}"
: "${YELLOW:=}"
: "${NC:=}"
: "${SKIP_MINISIGN:=false}"
: "${ALLOW_UNVERIFIED_MINISIGN_BOOTSTRAP:=false}"
: "${MINISIGN_MIRRORS:=}"
: "${GH_PROXY_BASE:=https://ghproxy.com/https://github.com}"
: "${MINISIGN_BIN:=}"
: "${XRAY_VERSION:=}"
: "${XRAY_MIRRORS:=}"
: "${XRAY_BIN:=/usr/local/bin/xray}"
: "${TMPDIR:=/tmp}"
: "${BOLD:=}"

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

    local tty_read_fd="" tty_write_fd=""
    if ! open_interactive_tty_fds tty_read_fd tty_write_fd; then
        log ERROR "$reason"
        log ERROR "Нет доступного TTY для подтверждения fallback-режима minisign"
        hint "Для осознанного продолжения используйте --allow-insecure-sha256"
        return 1
    fi

    printf '\n%b%s%b\n' "$YELLOW" "$reason" "$NC" >&"$tty_write_fd"
    printf '%b⚠️  Внимание: minisign недоступен или не пройден.%b\n' "$YELLOW" "$NC" >&"$tty_write_fd"
    printf '%bПродолжить установку только по SHA256?%b\n' "$YELLOW" "$NC" >&"$tty_write_fd"

    local prompt_rc=0
    if prompt_yes_no_from_tty "$tty_read_fd" "Подтвердите (yes/no): " "Введите yes или no (без кавычек)" "$tty_write_fd"; then
        exec {tty_read_fd}<&-
        exec {tty_write_fd}>&-
        return 0
    fi
    prompt_rc=$?
    exec {tty_read_fd}<&-
    exec {tty_write_fd}>&-
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

install_xray_detect_arch() {
    case "$(uname -m)" in
        x86_64) arch="64" ;;
        aarch64) arch="arm64-v8a" ;;
        armv7l) arch="arm32-v7a" ;;
        *)
            log ERROR "Неподдерживаемая архитектура: $(uname -m)"
            return 1
            ;;
    esac
}

install_xray_resolve_version() {
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
}

install_xray_prepare_download_workspace() {
    local tmp_base="$1"
    tmp_workdir=$(mktemp -d "${tmp_base}/xray-${version}.XXXXXX") || {
        log ERROR "Не удалось создать временную директорию для загрузки Xray"
        return 1
    }
    zip_file="${tmp_workdir}/Xray-linux-${arch}.zip"
    dgst_file="${tmp_workdir}/Xray-linux-${arch}.zip.dgst"
}

install_xray_official_release_base() {
    printf 'https://github.com/XTLS/Xray-core/releases/download/v%s\n' "$version"
}

install_xray_download_release_with_sha256() {
    used_base=""
    bases=()
    downloaded=false

    local base
    while read -r base; do
        [[ -n "$base" ]] && bases+=("$base")
    done < <(build_mirror_list "https://github.com/XTLS/Xray-core/releases/download/v${version}" "$XRAY_MIRRORS" "$version")

    local gh_proxy_base="${GH_PROXY_BASE:-https://ghproxy.com/https://github.com}"
    gh_proxy_base="${gh_proxy_base%/}"
    if [[ -n "$gh_proxy_base" ]]; then
        bases+=("${gh_proxy_base}/XTLS/Xray-core/releases/download/v${version}")
    fi

    local official_base
    official_base="$(install_xray_official_release_base)"
    local expected_sha256=""
    local official_dgst_available=false
    local mirror_digest_allowed=false

    rm -f "$dgst_file"
    if download_file_allowlist "${official_base}/Xray-linux-${arch}.zip.dgst" "$dgst_file" "Скачиваем официальный SHA256..."; then
        expected_sha256=$(awk -F'= *' 'toupper($1) ~ /SHA(2-)?256/ {print $2; exit}' "$dgst_file" 2> /dev/null || true)
        if [[ -n "$expected_sha256" ]]; then
            official_dgst_available=true
        else
            log WARN "Официальный .dgst скачан, но SHA256 не удалось прочитать"
            rm -f "$dgst_file"
        fi
    fi

    if [[ "$official_dgst_available" != true ]]; then
        if [[ "$ALLOW_INSECURE_SHA256" == "true" ]]; then
            mirror_digest_allowed=true
            log WARN "Официальный .dgst недоступен; разрешён небезопасный fallback к mirror-provided digest (ALLOW_INSECURE_SHA256=true)"
        else
            log ERROR "Не удалось получить официальный .dgst для Xray release"
            hint "Проверьте доступ к github.com или явно разрешите небезопасный fallback: --allow-insecure-sha256"
            return 1
        fi
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

        local candidate_sha256="$expected_sha256"
        if [[ "$mirror_digest_allowed" == "true" ]]; then
            candidate_sha256=""
            local dgst_base=""
            local -A dgst_seen=()
            for dgst_base in "$base" "${bases[@]}"; do
                dgst_base="${dgst_base%/}"
                [[ -z "$dgst_base" || -n "${dgst_seen[$dgst_base]:-}" ]] && continue
                dgst_seen["$dgst_base"]=1
                if ! download_file_allowlist "${dgst_base}/Xray-linux-${arch}.zip.dgst" "$dgst_file" "Скачиваем mirror SHA256..."; then
                    continue
                fi
                candidate_sha256=$(awk -F'= *' 'toupper($1) ~ /SHA(2-)?256/ {print $2; exit}' "$dgst_file" 2> /dev/null || true)
                if [[ -n "$candidate_sha256" ]]; then
                    break
                fi
                log WARN "Не удалось прочитать SHA256 из $dgst_file ($dgst_base)"
            done
            if [[ -z "$candidate_sha256" ]]; then
                log WARN "Не удалось скачать/прочитать mirror .dgst из доступных источников"
                continue
            fi
        fi

        local actual_sha256
        actual_sha256=$(sha256sum "$zip_file" | awk '{print $1}')
        if [[ "$candidate_sha256" != "$actual_sha256" ]]; then
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

    if [[ "$mirror_digest_allowed" == "true" ]]; then
        log OK "✓ SHA256 проверка пройдена через явно разрешённый mirror digest fallback"
    else
        log OK "✓ SHA256 проверка пройдена по официальному .dgst"
    fi
}

install_xray_is_minisig_file() {
    local file="$1"
    [[ -s "$file" ]] || return 1
    local line1 line2
    line1="$(head -n 1 "$file" 2> /dev/null | tr -d '\r' || true)"
    line2="$(head -n 2 "$file" 2> /dev/null | tail -n 1 | tr -d '\r' || true)"
    [[ "$line1" == untrusted\ comment:* ]] || return 1
    [[ "$line2" =~ ^R[0-9A-Za-z+/=]{40,}$ ]] || return 1
    return 0
}

install_xray_verify_release_signature() {
    if [[ "$SKIP_MINISIGN" == true ]]; then
        if [[ "$REQUIRE_MINISIGN" == "true" && "$ALLOW_INSECURE_SHA256" != "true" ]]; then
            log ERROR "Minisign недоступен, а REQUIRE_MINISIGN=true"
            return 1
        fi
        log INFO "Minisign недоступен; продолжаем только с SHA256"
        return 0
    fi

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
    local base
    local official_base
    official_base="$(install_xray_official_release_base)"
    local -a sig_bases=("$official_base")
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
            if ! install_xray_is_minisig_file "$sig_file"; then
                log INFO "Официальный источник minisign подписи вернул невалидный формат, пропускаем: $base"
                debug_file "invalid minisig payload from ${base}"
                rm -f "$sig_file"
                [[ "$sig_err_file" != "/dev/null" ]] && rm -f "$sig_err_file"
                continue
            fi
            sig_downloaded=true
            [[ "$sig_err_file" != "/dev/null" ]] && rm -f "$sig_err_file"
            break
        fi

        local sig_err_line=""
        if [[ -f "$sig_err_file" ]]; then
            sig_err_line=$(head -n 1 "$sig_err_file" 2> /dev/null | tr -d '\r' || true)
        fi
        if [[ "$sig_err_line" == *"requested URL returned error: 404"* ]]; then
            debug_file "official minisign signature missing at ${base} (404)"
        elif [[ -n "$sig_err_line" ]]; then
            log WARN "Официальный источник minisign подписи недоступен: ${base}"
            debug_file "minisign download failed from ${base}: ${sig_err_line}"
        fi
        [[ "$sig_err_file" != "/dev/null" ]] && rm -f "$sig_err_file"
    done

    if [[ "$sig_downloaded" != true ]]; then
        if ! confirm_minisign_fallback "Официальная minisign подпись недоступна для релиза"; then
            return 1
        fi
        if [[ "$ALLOW_INSECURE_SHA256" == "true" ]]; then
            log INFO "Официальная minisign подпись недоступна; продолжаем только с SHA256 (ALLOW_INSECURE_SHA256=true)"
        else
            log INFO "Официальная minisign подпись недоступна; продолжаем только с SHA256 после подтверждения"
        fi
        return 0
    fi

    if [[ -n "$sig_file" && -f "$sig_file" ]]; then
        local minisign_cmd="minisign"
        if [[ -n "${MINISIGN_BIN:-}" && -x "${MINISIGN_BIN}" ]]; then
            minisign_cmd="${MINISIGN_BIN}"
        fi
        if ! write_pinned_minisign_key; then
            return 1
        fi

        if "$minisign_cmd" -Vm "$zip_file" -p "$MINISIGN_KEY" -x "$sig_file" > /dev/null 2>&1; then
            log OK "✓ Minisign подпись верна"
        elif [[ "$ALLOW_INSECURE_SHA256" == true ]]; then
            log WARN "Minisign подпись не прошла (возможно, ключ обновился); продолжаем с SHA256"
        else
            if ! confirm_minisign_fallback "Ошибка проверки minisign подписи"; then
                return 1
            fi
            log WARN "Продолжаем только с SHA256 после подтверждения оператора"
        fi
        rm -f "$sig_file"
    fi
}

install_xray_unpack_release_archive() {
    local tmp_base="$1"
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
}

install_xray_finalize_install() {
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
}

xray_geo_asset_url() {
    local asset="$1"
    case "$asset" in
        geoip.dat)
            printf '%s\n' "${XRAY_GEOIP_URL:-https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat}"
            ;;
        geosite.dat)
            printf '%s\n' "${XRAY_GEOSITE_URL:-https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat}"
            ;;
        *)
            return 1
            ;;
    esac
}

xray_geo_asset_sha256_url() {
    local asset="$1"
    case "$asset" in
        geoip.dat)
            printf '%s\n' "${XRAY_GEOIP_SHA256_URL:-https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat.sha256sum}"
            ;;
        geosite.dat)
            printf '%s\n' "${XRAY_GEOSITE_SHA256_URL:-https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat.sha256sum}"
            ;;
        *)
            return 1
            ;;
    esac
}

xray_geo_flag_enabled() {
    case "${1,,}" in
        true | 1 | yes | on)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

xray_geo_expected_sha256() {
    local sha_file="$1"
    sed -n '1{s/[[:space:]].*$//;p;}' "$sha_file"
}

xray_geo_publish_asset() {
    local src_file="$1"
    local dest_file="$2"
    local tmp_file=""

    mkdir -p "$(dirname "$dest_file")" || return 1
    tmp_file=$(mktemp "${dest_file}.tmp.XXXXXX") || return 1
    if ! install -m 644 "$src_file" "$tmp_file"; then
        rm -f "$tmp_file"
        return 1
    fi
    if ! mv -f "$tmp_file" "$dest_file"; then
        rm -f "$tmp_file"
        return 1
    fi
}

refresh_geo_asset() {
    local asset="$1"
    local asset_url sha_url verify_hash strict_mode asset_dir dest_file
    local tmp_dir="" tmp_asset="" tmp_sha="" expected_hash="" actual_hash=""

    asset_url=$(xray_geo_asset_url "$asset") || {
        log ERROR "Неизвестный geo asset: ${asset}"
        return 1
    }
    sha_url=$(xray_geo_asset_sha256_url "$asset") || {
        log ERROR "Неизвестный checksum path для geo asset: ${asset}"
        return 1
    }
    verify_hash=false
    strict_mode=false
    xray_geo_flag_enabled "${GEO_VERIFY_HASH:-true}" && verify_hash=true
    xray_geo_flag_enabled "${GEO_VERIFY_STRICT:-false}" && strict_mode=true

    validate_curl_target "$asset_url" true || return 1
    if [[ "$verify_hash" == true ]]; then
        validate_curl_target "$sha_url" true || return 1
    fi

    asset_dir=$(xray_geo_dir)
    dest_file="${asset_dir%/}/${asset}"
    tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/xray-geo.XXXXXX") || {
        log ERROR "Не удалось создать временную директорию для ${asset}"
        return 1
    }
    # shellcheck disable=SC2317,SC2329
    cleanup_refresh_geo_asset() {
        rm -f "${tmp_asset:-}" "${tmp_sha:-}" 2> /dev/null || true
        rm -rf "${tmp_dir:-}" 2> /dev/null || true
        trap - RETURN
    }
    trap cleanup_refresh_geo_asset RETURN

    tmp_asset=$(mktemp "${tmp_dir}/${asset}.part.XXXXXX") || return 1
    if ! download_file_allowlist "$asset_url" "$tmp_asset" "Скачиваем ${asset}..."; then
        log ERROR "Не удалось скачать ${asset}"
        return 1
    fi

    if [[ "$verify_hash" == true ]]; then
        tmp_sha=$(mktemp "${tmp_dir}/${asset}.sha256.XXXXXX") || return 1
        if ! download_file_allowlist "$sha_url" "$tmp_sha" "Скачиваем SHA256 для ${asset}..."; then
            if [[ "$strict_mode" == true ]]; then
                log ERROR "Не удалось скачать SHA256 для ${asset} при GEO_VERIFY_STRICT=true"
                return 1
            fi
            log WARN "Не удалось скачать SHA256 для ${asset}; оставляем текущий файл без замены"
            return 1
        fi

        expected_hash=$(xray_geo_expected_sha256 "$tmp_sha")
        actual_hash=$(sha256sum "$tmp_asset" | awk '{print $1}')
        if [[ -z "$expected_hash" || "$expected_hash" != "$actual_hash" ]]; then
            log ERROR "Контрольная сумма ${asset} не совпала"
            return 1
        fi
    fi

    if ! xray_geo_publish_asset "$tmp_asset" "$dest_file"; then
        log ERROR "Не удалось атомарно обновить ${asset}"
        return 1
    fi
    log OK "${asset} обновлён"
}

refresh_geo_assets() {
    local strict_mode=false
    local had_failure=false
    local asset

    xray_geo_flag_enabled "${GEO_VERIFY_STRICT:-false}" && strict_mode=true

    log STEP "Обновляем GeoIP/GeoSite..."
    for asset in geoip.dat geosite.dat; do
        if ! refresh_geo_asset "$asset"; then
            if [[ "$strict_mode" == true ]]; then
                return 1
            fi
            had_failure=true
        fi
    done

    if [[ "$had_failure" == true ]]; then
        log WARN "Часть geo assets не обновилась; оставлены предыдущие рабочие файлы"
        return 0
    fi

    log OK "GeoIP/GeoSite обновлены"
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

    local arch=""
    local version=""
    local zip_file=""
    local dgst_file=""
    # shellcheck disable=SC2034 # Shared across install_xray_* helpers in the same shell.
    local used_base=""
    local downloaded=false
    local -a bases=()
    local tmp_base="${TMPDIR:-/tmp}"

    install_xray_detect_arch || return 1
    install_xray_resolve_version || return 1
    install_xray_prepare_download_workspace "$tmp_base" || return 1
    install_xray_download_release_with_sha256 || return 1
    install_xray_verify_release_signature || return 1
    install_xray_unpack_release_archive "$tmp_base" || return 1
    install_xray_finalize_install || return 1
    return 0
}
