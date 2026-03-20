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

CONFIG_SHARED_HELPERS_MODULE="${SCRIPT_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)}/modules/config/shared_helpers.sh"
if [[ ! -f "$CONFIG_SHARED_HELPERS_MODULE" && -n "${XRAY_DATA_DIR:-}" ]]; then
    CONFIG_SHARED_HELPERS_MODULE="$XRAY_DATA_DIR/modules/config/shared_helpers.sh"
fi
if [[ -f "$CONFIG_SHARED_HELPERS_MODULE" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG_SHARED_HELPERS_MODULE"
fi

EXPORT_CAPABILITIES_MODULE="${SCRIPT_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)}/modules/export/capabilities.sh"
if [[ ! -f "$EXPORT_CAPABILITIES_MODULE" && -n "${XRAY_DATA_DIR:-}" ]]; then
    EXPORT_CAPABILITIES_MODULE="$XRAY_DATA_DIR/modules/export/capabilities.sh"
fi
if [[ ! -f "$EXPORT_CAPABILITIES_MODULE" ]]; then
    echo "ERROR: не найден модуль export capabilities: $EXPORT_CAPABILITIES_MODULE" >&2
    exit 1
fi
# shellcheck source=modules/export/capabilities.sh
source "$EXPORT_CAPABILITIES_MODULE"

validate_export_json_schema() {
    local file="$1"
    local kind="$2"

    if [[ ! -f "$file" ]]; then
        log ERROR "Файл экспорта не найден: $file"
        return 1
    fi

    case "$kind" in
        json)
            jq empty "$file" > /dev/null 2>&1 || {
                log ERROR "Некорректный JSON в экспорте: $file"
                return 1
            }
            ;;
        text)
            [[ -s "$file" ]] || {
                log ERROR "Пустой текстовый экспорт: $file"
                return 1
            }
            ;;
        *)
            log ERROR "Неизвестный тип schema проверки: ${kind}"
            return 1
            ;;
    esac

    return 0
}

export_raw_xray_index() {
    local json_file="$1"
    local out_file="$2"
    local tmp_out
    tmp_out=$(mktemp "${out_file}.tmp.XXXXXX") || {
        log ERROR "Не удалось создать временный файл экспорта: ${out_file}"
        return 1
    }

    if ! jq '{
        generated,
        transport,
        schema_version,
        stealth_contract_version,
        xray_min_version,
        configs: [
            .configs[] | {
                name,
                domain,
                provider_family,
                primary_rank,
                sni,
                fingerprint,
                transport,
                transport_endpoint,
                flow,
                vless_encryption,
                vless_decryption,
                recommended_variant,
                variants: [
                    .variants[] | {
                        key,
                        category,
                        label,
                        note,
                        mode,
                        requires,
                        import_hint,
                        vless_encryption,
                        vless_v4,
                        vless_v6,
                        xray_client_file_v4,
                        xray_client_file_v6
                    }
                ]
            }
        ]
    }' "$json_file" > "$tmp_out"; then
        rm -f "$tmp_out"
        log ERROR "Не удалось собрать raw-xray index из ${json_file}"
        return 1
    fi

    if ! validate_export_json_schema "$tmp_out" json; then
        rm -f "$tmp_out"
        return 1
    fi
    if ! mv "$tmp_out" "$out_file"; then
        rm -f "$tmp_out"
        log ERROR "Не удалось сохранить индекс raw Xray: ${out_file}"
        return 1
    fi
    log OK "Индекс raw Xray сохранён: $out_file"
}

export_v2rayn_fragment_template() {
    local json_file="$1"
    local out_file="$2"
    local tmp_out
    tmp_out=$(mktemp "${out_file}.tmp.XXXXXX") || {
        log ERROR "Не удалось создать временный файл экспорта: ${out_file}"
        return 1
    }

    if ! jq '{
        generated,
        transport,
        profiles: [
            .configs[] as $cfg
            | ($cfg.variants // [])[]
            | select((.vless_v4 // "") | length > 0)
            | {
                name: ($cfg.name + " / " + (.label // .key // "standard")),
                config_name: $cfg.name,
                domain: $cfg.domain,
                server: .vless_v4,
                transport: ($cfg.transport // .transport),
                transport_endpoint: ($cfg.transport_endpoint // .transport_endpoint),
                mode: .mode,
                vless_link: .vless_v4,
                vless_link_ipv6: .vless_v6,
                raw_xray_file_v4: .xray_client_file_v4,
                raw_xray_file_v6: .xray_client_file_v6
            }
        ]
    }' "$json_file" > "$tmp_out"; then
        rm -f "$tmp_out"
        log ERROR "Не удалось собрать шаблон ссылок v2rayN из ${json_file}"
        return 1
    fi

    if ! validate_export_json_schema "$tmp_out" json; then
        rm -f "$tmp_out"
        return 1
    fi
    if ! mv "$tmp_out" "$out_file"; then
        rm -f "$tmp_out"
        log ERROR "Не удалось сохранить шаблон ссылок v2rayN: ${out_file}"
        return 1
    fi
    log OK "Шаблон ссылок v2rayN сохранён: $out_file"
}

export_nekoray_fragment_template() {
    local json_file="$1"
    local out_file="$2"
    local tmp_out
    tmp_out=$(mktemp "${out_file}.tmp.XXXXXX") || {
        log ERROR "Не удалось создать временный файл экспорта: ${out_file}"
        return 1
    }

    if ! jq '{
        generated,
        transport,
        note: "xhttp-first export. import vless link or open raw xray json directly.",
        profiles: [
            .configs[] as $cfg
            | ($cfg.variants // [])[]
            | select((.vless_v4 // "") | length > 0)
            | {
                name: ($cfg.name + " / " + (.label // .key // "standard")),
                domain: $cfg.domain,
                sni: $cfg.sni,
                fingerprint: $cfg.fingerprint,
                transport: ($cfg.transport // .transport),
                transport_endpoint: ($cfg.transport_endpoint // .transport_endpoint),
                mode: .mode,
                vless_link: .vless_v4,
                vless_link_ipv6: .vless_v6,
                raw_xray_file_v4: .xray_client_file_v4,
                raw_xray_file_v6: .xray_client_file_v6
            }
        ]
    }' "$json_file" > "$tmp_out"; then
        rm -f "$tmp_out"
        log ERROR "Не удалось собрать шаблон nekoray из ${json_file}"
        return 1
    fi

    if ! validate_export_json_schema "$tmp_out" json; then
        rm -f "$tmp_out"
        return 1
    fi
    if ! mv "$tmp_out" "$out_file"; then
        rm -f "$tmp_out"
        log ERROR "Не удалось сохранить шаблон nekoray: ${out_file}"
        return 1
    fi
    log OK "Шаблон nekoray сохранён: $out_file"
}

export_compatibility_notes() {
    local capabilities_file="$1"
    local out_file="$2"

    export_capabilities_notes_from_json "$capabilities_file" "$out_file"
    if ! validate_export_json_schema "$out_file" text; then
        return 1
    fi
    log OK "Compatibility notes сохранены: $out_file"
}

copy_canary_raw_file() {
    local source_file="$1"
    local raw_dir="$2"

    [[ -n "$source_file" && -f "$source_file" ]] || return 0

    local dest_file=""
    dest_file="${raw_dir}/$(basename "$source_file")"
    if [[ -e "$dest_file" ]]; then
        log ERROR "export_canary_bundle: коллизия raw-xray имени: $(basename "$source_file")"
        return 1
    fi

    cp -f -- "$source_file" "$dest_file" || {
        log ERROR "export_canary_bundle: не удалось скопировать raw-xray файл: $source_file"
        return 1
    }
}

export_canary_bundle() {
    local json_file="$1"
    local out_dir="$2"
    local out_parent
    out_parent="$(dirname "$out_dir")"
    mkdir -p "$out_parent" || {
        log ERROR "export_canary_bundle: не удалось создать каталог: ${out_parent}"
        return 1
    }
    local bundle_tmp
    bundle_tmp=$(mktemp -d "${out_dir}.tmp.XXXXXX") || {
        log ERROR "export_canary_bundle: не удалось создать временный каталог: ${out_dir}"
        return 1
    }
    local manifest_file="${bundle_tmp}/manifest.json"
    local raw_dir="${bundle_tmp}/raw-xray"
    mkdir -p "$raw_dir"

    local variant_rows
    variant_rows=$(jq -r '.configs[] | .variants[] | [.key, .xray_client_file_v4 // "", .xray_client_file_v6 // ""] | @tsv' "$json_file" 2> /dev/null) || {
        log ERROR "export_canary_bundle: не удалось разобрать variants из ${json_file}"
        rm -rf -- "$bundle_tmp"
        return 1
    }

    while IFS=$'\t' read -r _ raw_v4 raw_v6; do
        copy_canary_raw_file "$raw_v4" "$raw_dir" || {
            rm -rf -- "$bundle_tmp"
            return 1
        }
        copy_canary_raw_file "$raw_v6" "$raw_dir" || {
            rm -rf -- "$bundle_tmp"
            return 1
        }
    done <<< "$variant_rows"

    local source_json
    source_json=$(jq '. | {
        schema_version,
        stealth_contract_version,
        xray_min_version,
        generated,
        transport,
        configs: [
            .configs[] | {
                name,
                domain,
                recommended_variant,
                variants: [
                    .variants[] | {
                        key,
                        category,
                        mode,
                        requires,
                        import_hint,
                        raw_xray_ipv4: (if (.xray_client_file_v4 // "") != "" then ("raw-xray/" + ((.xray_client_file_v4 | gsub("\\\\"; "/")) | split("/") | last)) else null end),
                        raw_xray_ipv6: (if (.xray_client_file_v6 // "") != "" then ("raw-xray/" + ((.xray_client_file_v6 | gsub("\\\\"; "/")) | split("/") | last)) else null end)
                    }
                ]
            }
        ]
    }' "$json_file" 2> /dev/null) || {
        log ERROR "export_canary_bundle: не удалось сформировать source JSON"
        rm -rf -- "$bundle_tmp"
        return 1
    }

    local manifest_tmp
    manifest_tmp=$(mktemp "${manifest_file}.tmp.XXXXXX")
    jq -n \
        --arg generated "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
        --arg root "$out_dir" \
        --arg browser_dialer_env "${BROWSER_DIALER_ENV_NAME:-xray.browser.dialer}" \
        --arg browser_dialer_address "${XRAY_BROWSER_DIALER_ADDRESS:-127.0.0.1:11050}" \
        --argjson source "$source_json" \
        '{
            generated: $generated,
            root: $root,
            browser_dialer_env: $browser_dialer_env,
            browser_dialer_address: $browser_dialer_address,
            source: $source
        }' > "$manifest_tmp" || {
        log ERROR "export_canary_bundle: не удалось записать manifest.json"
        rm -f -- "$manifest_tmp"
        rm -rf -- "$bundle_tmp"
        return 1
    }

    if ! validate_export_json_schema "$manifest_tmp" json; then
        rm -f -- "$manifest_tmp"
        rm -rf -- "$bundle_tmp"
        return 1
    fi
    mv -f -- "$manifest_tmp" "$manifest_file"

    cat > "${bundle_tmp}/measure-linux.sh" << 'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$ROOT_DIR/manifest.json"
if [[ ! -f "$MANIFEST" ]]; then
  echo "manifest.json not found" >&2
  exit 1
fi
echo "use the bundle with xray and curl installed."
echo "recommended flow:"
echo "  1. inspect manifest.json"
echo "  2. if you test emergency on a POSIX shell, launch the client with:"
echo "     env 'xray.browser.dialer=127.0.0.1:11050' xray run -config raw-xray/<emergency-config>.json"
echo "     use browser_dialer_env/browser_dialer_address from manifest.json if they differ from the defaults"
echo "  3. run repo-local scripts/measure-stealth.sh for full JSON reports when possible"
cat "$MANIFEST"
EOF
    chmod +x "${bundle_tmp}/measure-linux.sh"

    cat > "${bundle_tmp}/measure-windows.ps1" << 'EOF'
param()
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$manifest = Join-Path $root 'manifest.json'
if (-not (Test-Path $manifest)) {
  Write-Error 'manifest.json not found'
  exit 1
}
Write-Host 'use the bundle with xray and curl installed.'
Write-Host 'for full field reports prefer scripts/measure-stealth.sh from the repo when available.'
Get-Content $manifest
EOF

    rm -rf -- "$out_dir"
    mv -- "$bundle_tmp" "$out_dir"
    log OK "Canary bundle сохранён: $out_dir"
}

export_all_configs() {
    local export_dir="${XRAY_KEYS}/export"
    local json_file="${XRAY_KEYS}/clients.json"
    mkdir -p "$export_dir"

    if [[ ! -f "$json_file" ]]; then
        log WARN "clients.json не найден; экспорт пропущен"
        return 0
    fi
    if declare -F validate_clients_json_file > /dev/null 2>&1; then
        validate_clients_json_file "$json_file" || return 1
    fi

    export_raw_xray_index "$json_file" "${export_dir}/raw-xray-index.json"
    export_v2rayn_fragment_template "$json_file" "${export_dir}/v2rayn-links.json"
    export_nekoray_fragment_template "$json_file" "${export_dir}/nekoray-template.json"
    export_canary_bundle "$json_file" "${export_dir}/canary"
    export_capabilities_json "$export_dir" "${export_dir}/capabilities.json"
    validate_export_json_schema "${export_dir}/capabilities.json" json || return 1
    log OK "Capability matrix сохранена: ${export_dir}/capabilities.json"
    export_compatibility_notes "${export_dir}/capabilities.json" "${export_dir}/compatibility-notes.txt"

    local -a artifacts=()
    mapfile -t artifacts < <(find "$export_dir" -mindepth 1 -maxdepth 2 -type f)
    if ((${#artifacts[@]} > 0)); then
        chmod 640 "${artifacts[@]}"
        chown "root:${XRAY_GROUP}" "${artifacts[@]}" 2> /dev/null || true
    fi
    if [[ -f "${export_dir}/canary/measure-linux.sh" ]]; then
        chmod 750 "${export_dir}/canary/measure-linux.sh" 2> /dev/null || true
    fi
    log OK "Все форматы экспортированы в ${export_dir}/"
}
