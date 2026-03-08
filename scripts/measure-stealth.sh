#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC2034 # consumed by sourced runtime modules
SCRIPT_DIR="$ROOT_DIR"
# shellcheck disable=SC2034 # consumed by sourced runtime modules
MODULE_DIR="$ROOT_DIR"
DEFAULT_CLIENTS_JSON="/etc/xray/private/keys/clients.json"
DEFAULT_VARIANTS="recommended,rescue"

# shellcheck source=lib.sh
source "$ROOT_DIR/lib.sh"
# shellcheck source=config.sh
source "$ROOT_DIR/config.sh"
# shellcheck source=health.sh
source "$ROOT_DIR/health.sh"

measure_usage() {
    cat << 'EOF'
usage:
  usage: scripts/measure-stealth.sh
  scripts/measure-stealth.sh run [options]
  scripts/measure-stealth.sh import [options]
  scripts/measure-stealth.sh compare [options]
  scripts/measure-stealth.sh prune [options]
  scripts/measure-stealth.sh summarize [options]

run options:
  --clients-json <file>   clients.json path (default: /etc/xray/private/keys/clients.json)
  --variants <list>       comma/space-separated variant keys (default: recommended,rescue)
  --network-tag <name>    label for the tested network (default: default)
  --provider <name>       provider label (default: unknown)
  --region <name>         region label (default: unknown)
  --output <file>         write json report to file
  --save                  save report into managed measurements dir

compare options:
  --input <file>          add one report file (repeatable)
  --dir <dir>             read all *.json reports from dir
  --output <file>         write aggregated json

import options:
  --input <file>          import one report file into managed measurements dir (repeatable)
  --dir <dir>             import all *.json reports from dir
  --output <file>         write refreshed summary json

prune options:
  --keep-last <N>         keep only the newest N stored reports
  --dry-run               show what would be pruned without deleting files
  --output <file>         write prune result json

summarize options:
  --input <file>          add one report file (repeatable)
  --dir <dir>             read all *.json reports from dir
  --output <file>         write aggregated json summary

notes:
  - plain invocation without a subcommand is treated as run
  - run exits nonzero when at least one config has no successful requested variant
EOF
}

measure_require_valid_clients_json() {
    local file="$1"
    [[ -n "$file" ]] || {
        echo "clients.json path is required" >&2
        exit 1
    }
    [[ -f "$file" ]] || {
        echo "clients.json not found: $file" >&2
        exit 1
    }
    if ! jq -e 'type == "object" and (.configs | type == "array")' "$file" > /dev/null 2>&1; then
        echo "clients.json has invalid schema: $file" >&2
        exit 1
    fi
}

measure_collect_input_files() {
    local dir="${1:-}"
    shift || true
    local -a files=("$@")
    local -a expanded=()
    if [[ -n "$dir" && -d "$dir" ]]; then
        mapfile -t expanded < <(find "$dir" -maxdepth 1 -type f -name '*.json' | sort)
        files+=("${expanded[@]}")
    fi
    if ((${#files[@]} == 0)); then
        mapfile -t files < <(measurement_collect_report_files)
    fi
    printf '%s\n' "${files[@]}"
}

measure_run() {
    local clients_json="$DEFAULT_CLIENTS_JSON"
    local variants="$DEFAULT_VARIANTS"
    local output_file=""
    local save_report=false
    local network_tag="default"
    local provider="unknown"
    local region="unknown"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --clients-json)
                clients_json="${2:-}"
                shift 2
                ;;
            --variants)
                variants="${2:-}"
                shift 2
                ;;
            --network-tag)
                network_tag="${2:-}"
                shift 2
                ;;
            --provider)
                provider="${2:-}"
                shift 2
                ;;
            --region)
                region="${2:-}"
                shift 2
                ;;
            --output)
                output_file="${2:-}"
                shift 2
                ;;
            --save)
                save_report=true
                shift
                ;;
            --help)
                measure_usage
                exit 0
                ;;
            *)
                echo "unknown run option: $1" >&2
                measure_usage >&2
                exit 1
                ;;
        esac
    done

    measure_require_valid_clients_json "$clients_json"
    # shellcheck disable=SC2034 # consumed by self_check_run_variant_probe through sourced modules
    SELF_CHECK_ENABLED=true

    local report_results='[]'
    local config_summary='[]'
    local requested_variants_json
    requested_variants_json=$(split_list "$variants" | jq -R . | jq -s .)

    local config_name
    while IFS= read -r config_name; do
        config_name=${config_name//$'\r'/}
        config_name=$(self_check_trim_ws "$config_name")
        [[ -n "$config_name" ]] || continue
        local config_success=false

        local variant_key
        while IFS= read -r variant_key; do
            variant_key=${variant_key//$'\r'/}
            variant_key=$(self_check_trim_ws "$variant_key")
            [[ -n "$variant_key" ]] || continue
            local job_json=""
            job_json=$(jq -c \
                --arg config_name "$config_name" \
                --arg variant_key "$variant_key" '
                    .configs[]
                    | select(.name == $config_name)
                    | . as $cfg
                    | ($cfg.variants[] | select(.key == $variant_key) | {
                        config_name: $cfg.name,
                        variant_key: .key,
                        mode: (.mode // ""),
                        raw_v4: (.xray_client_file_v4 // ""),
                        raw_v6: (.xray_client_file_v6 // "")
                    })
                ' "$clients_json" 2> /dev/null | head -n 1 || true)
            [[ -n "$job_json" ]] || continue

            local family
            for family in ipv4 ipv6; do
                local raw_file=""
                case "$family" in
                    ipv4) raw_file=$(jq -r '.raw_v4 // empty' <<< "$job_json") ;;
                    ipv6) raw_file=$(jq -r '.raw_v6 // empty' <<< "$job_json") ;;
                esac
                [[ -n "$raw_file" ]] || continue

                local probe_result
                probe_result=$(self_check_run_variant_probe \
                    "measure-stealth" \
                    "$config_name" \
                    "$variant_key" \
                    "$(jq -r '.mode // ""' <<< "$job_json")" \
                    "$family" \
                    "$raw_file")
                report_results=$(jq --argjson item "$probe_result" '. + [$item]' <<< "$report_results")

                if jq -e '.success == true' <<< "$probe_result" > /dev/null 2>&1; then
                    config_success=true
                fi
            done
        done < <(split_list "$variants")

        config_summary=$(jq \
            --arg config_name "$config_name" \
            --argjson config_success "$config_success" \
            --argjson requested_variants "$requested_variants_json" \
            --argjson results "$report_results" '
                . + [{
                    config_name: $config_name,
                    requested_variants: $requested_variants,
                    success: $config_success,
                    successful_results: (
                        $results
                        | map(select(.config_name == $config_name and .success == true))
                        | length
                    )
                }]
            ' <<< "$config_summary")
    done < <(jq -r '.configs[]?.name // empty' "$clients_json")

    local final_report
    final_report=$(jq -n \
        --arg generated "$(measurement_now_utc)" \
        --arg clients_json "$clients_json" \
        --arg network_tag "$network_tag" \
        --arg provider "$provider" \
        --arg region "$region" \
        --argjson requested_variants "$requested_variants_json" \
        --argjson probe_urls "$(self_check_urls_json)" \
        --argjson results "$report_results" \
        --argjson configs "$config_summary" \
        '{
            generated: $generated,
            clients_json: $clients_json,
            network_tag: $network_tag,
            provider: $provider,
            region: $region,
            requested_variants: $requested_variants,
            probe_urls: $probe_urls,
            configs: $configs,
            results: $results
        }')

    if [[ -n "$output_file" ]]; then
        mkdir -p "$(dirname "$output_file")"
        printf '%s\n' "$final_report" > "$output_file"
    fi
    if [[ "$save_report" == true ]]; then
        measurement_save_report "$final_report" > /dev/null
    fi

    printf '%s\n' "$final_report"

    if jq -e 'all(.configs[]?; .success == true)' <<< "$final_report" > /dev/null 2>&1; then
        return 0
    fi
    return 1
}

measure_compare() {
    local output_file=""
    local dir=""
    local -a input_files=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --input)
                input_files+=("${2:-}")
                shift 2
                ;;
            --dir)
                dir="${2:-}"
                shift 2
                ;;
            --output)
                output_file="${2:-}"
                shift 2
                ;;
            --help)
                measure_usage
                exit 0
                ;;
            *)
                echo "unknown compare option: $1" >&2
                measure_usage >&2
                exit 1
                ;;
        esac
    done

    mapfile -t input_files < <(measure_collect_input_files "$dir" "${input_files[@]}")
    if ((${#input_files[@]} == 0)); then
        echo "no measurement reports found" >&2
        exit 1
    fi

    local aggregated
    aggregated=$(measurement_compare_reports_json "${input_files[@]}")
    if [[ -n "$output_file" ]]; then
        mkdir -p "$(dirname "$output_file")"
        printf '%s\n' "$aggregated" > "$output_file"
    fi
    printf '%s\n' "$aggregated"
}

measure_import() {
    local output_file=""
    local dir=""
    local -a input_files=()
    local -a dir_files=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --input)
                input_files+=("${2:-}")
                shift 2
                ;;
            --dir)
                dir="${2:-}"
                shift 2
                ;;
            --output)
                output_file="${2:-}"
                shift 2
                ;;
            --help)
                measure_usage
                exit 0
                ;;
            *)
                echo "unknown import option: $1" >&2
                measure_usage >&2
                exit 1
                ;;
        esac
    done

    if [[ -n "$dir" && -d "$dir" ]]; then
        mapfile -t dir_files < <(find "$dir" -maxdepth 1 -type f -name '*.json' | sort)
        input_files+=("${dir_files[@]}")
    fi
    if ((${#input_files[@]} == 0)); then
        echo "no measurement reports found for import" >&2
        exit 1
    fi

    local -a imported=()
    local file
    for file in "${input_files[@]}"; do
        [[ -n "$file" ]] || continue
        imported+=("$(measurement_import_report_file "$file")")
    done

    local summary_json
    summary_json=$(measurement_read_summary_json 2> /dev/null || printf '%s\n' '{}')
    local result_json
    result_json=$(jq -n \
        --argjson imported "$(printf '%s\n' "${imported[@]}" | sed '/^$/d' | jq -R . | jq -s .)" \
        --argjson summary "$summary_json" '
            {
                imported_files: $imported,
                imported_count: ($imported | length),
                summary: $summary
            }')

    if [[ -n "$output_file" ]]; then
        mkdir -p "$(dirname "$output_file")"
        printf '%s\n' "$result_json" > "$output_file"
    fi
    printf '%s\n' "$result_json"
}

measure_prune() {
    local keep_last=""
    local dry_run=false
    local output_file=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --keep-last)
                keep_last="${2:-}"
                shift 2
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --output)
                output_file="${2:-}"
                shift 2
                ;;
            --help)
                measure_usage
                exit 0
                ;;
            *)
                echo "unknown prune option: $1" >&2
                measure_usage >&2
                exit 1
                ;;
        esac
    done

    [[ -n "$keep_last" ]] || {
        echo "prune requires --keep-last <N>" >&2
        exit 1
    }

    local result_json
    result_json=$(measurement_prune_reports "$keep_last" "$dry_run")
    if [[ -n "$output_file" ]]; then
        mkdir -p "$(dirname "$output_file")"
        printf '%s\n' "$result_json" > "$output_file"
    fi
    printf '%s\n' "$result_json"
}

measure_summarize() {
    local output_file=""
    local dir=""
    local -a input_files=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --input)
                input_files+=("${2:-}")
                shift 2
                ;;
            --dir)
                dir="${2:-}"
                shift 2
                ;;
            --output)
                output_file="${2:-}"
                shift 2
                ;;
            --help)
                measure_usage
                exit 0
                ;;
            *)
                echo "unknown summarize option: $1" >&2
                measure_usage >&2
                exit 1
                ;;
        esac
    done

    mapfile -t input_files < <(measure_collect_input_files "$dir" "${input_files[@]}")
    if ((${#input_files[@]} == 0)); then
        echo "no measurement reports found" >&2
        exit 1
    fi

    local aggregated
    aggregated=$(measurement_compare_reports_json "${input_files[@]}")
    if [[ -n "$output_file" ]]; then
        mkdir -p "$(dirname "$output_file")"
        printf '%s\n' "$aggregated" > "$output_file"
    fi

    jq -r '
        "field verdict: " + (.field_verdict // "unknown"),
        "current primary: " + (.current_primary // "n/a"),
        "best spare: " + (.best_spare // "n/a"),
        "recommend emergency: " + ((.recommend_emergency // false) | tostring),
        "reports: " + ((.report_count // 0) | tostring),
        "",
        "configs:",
        (
            .configs[]
            | "  - " + .config_name
              + " | recommended=" + ((.recommended_success_rate_last5 // 0) | tostring)
              + "% | rescue=" + ((.rescue_success_rate_last5 // 0) | tostring)
              + "% | emergency=" + ((.emergency_success_rate_last5 // 0) | tostring)
              + "% | best=" + (.best_variant // "n/a")
        ),
        (
            if .promotion_candidate == null then
                ""
            else
                "promotion candidate: " + (.promotion_candidate.config_name // "n/a") + " (" + (.promotion_candidate.reason // "n/a") + ")"
            end
        )
    ' <<< "$aggregated"
}

subcommand="${1:-run}"
case "$subcommand" in
    run | compare | import | prune | summarize)
        shift || true
        ;;
    --help | -h)
        measure_usage
        exit 0
        ;;
    *)
        subcommand="run"
        ;;
esac

case "$subcommand" in
    run) measure_run "$@" ;;
    compare) measure_compare "$@" ;;
    import) measure_import "$@" ;;
    prune) measure_prune "$@" ;;
    summarize) measure_summarize "$@" ;;
esac
