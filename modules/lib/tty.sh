#!/usr/bin/env bash
# shellcheck shell=bash

normalize_tty_input() {
    local value="${1:-}"
    # Drop common terminal control artifacts (for example bracketed paste markers).
    value="${value//$'\e[200~'/}"
    value="${value//$'\e[201~'/}"
    value="${value//$'\r\n'/$'\n'}"
    value="${value//$'\r'/}"

    # Remove OSC sequences (ESC ] ... BEL or ESC ] ... ESC \).
    while [[ "$value" == *$'\e]'* ]]; do
        local osc_prefix osc_tail
        osc_prefix="${value%%$'\e]'*}"
        osc_tail="${value#*$'\e]'}"
        if [[ "$osc_tail" == *$'\a'* ]]; then
            osc_tail="${osc_tail#*$'\a'}"
        elif [[ "$osc_tail" == *$'\e\\'* ]]; then
            osc_tail="${osc_tail#*$'\e\\'}"
        else
            osc_tail=""
        fi
        value="${osc_prefix}${osc_tail}"
    done

    # Remove CSI/SS3 and remaining one-byte ESC controls.
    value=$(printf '%s' "$value" | sed -E $'s/\x1B\\[[0-9;?]*[ -\\/]*[@-~]//g; s/\x1BO[ -~]//g; s/\x1B[@-_]//g')

    # Remove common zero-width/BiDi artifacts and non-printable control bytes.
    value="${value//$'\u00A0'/ }"
    value="${value//$'\u200B'/}"
    value="${value//$'\u200C'/}"
    value="${value//$'\u200D'/}"
    value="${value//$'\u200E'/}"
    value="${value//$'\u200F'/}"
    value="${value//$'\u202A'/}"
    value="${value//$'\u202B'/}"
    value="${value//$'\u202C'/}"
    value="${value//$'\u202D'/}"
    value="${value//$'\u202E'/}"
    value="${value//$'\u2060'/}"
    value="${value//$'\u2066'/}"
    value="${value//$'\u2067'/}"
    value="${value//$'\u2068'/}"
    value="${value//$'\u2069'/}"
    value="${value//$'\uFEFF'/}"
    value=$(printf '%s' "$value" | tr -d '\000-\010\013\014\016-\037\177')
    value=$(trim_ws "$value")
    printf '%s' "$value"
}

open_interactive_tty_fd() {
    local out_var="${1:-}"
    [[ -n "$out_var" ]] || return 1

    if command -v tty > /dev/null 2>&1; then
        if ! tty -s > /dev/null 2>&1; then
            return 1
        fi
    fi
    if [[ ! -r /dev/tty || ! -w /dev/tty ]]; then
        return 1
    fi

    local opened_fd=""
    if ! exec {opened_fd}<> /dev/tty 2> /dev/null; then
        return 1
    fi
    printf -v "$out_var" '%s' "$opened_fd"
    return 0
}

open_interactive_tty_fds() {
    local read_var="${1:-}"
    local write_var="${2:-}"
    [[ -n "$read_var" && -n "$write_var" ]] || return 1

    local read_fd="" write_fd=""
    if ! open_interactive_tty_fd read_fd; then
        return 1
    fi
    if ! exec {write_fd}> /dev/tty 2> /dev/null; then
        exec {read_fd}>&-
        return 1
    fi

    printf -v "$read_var" '%s' "$read_fd"
    printf -v "$write_var" '%s' "$write_fd"
    return 0
}

tty_printf() {
    local tty_fd="${1:-}"
    shift || true
    [[ "$tty_fd" =~ ^[0-9]+$ ]] || return 1
    # shellcheck disable=SC2059 # Controlled internal helper: callers pass static format strings.
    printf "$@" >&"$tty_fd"
}

tty_print_line() {
    local tty_fd="${1:-}"
    shift || true
    [[ "$tty_fd" =~ ^[0-9]+$ ]] || return 1
    printf '%s\n' "$*" >&"$tty_fd"
}

tty_print_box() {
    local tty_fd="${1:-}"
    local color="${2:-$NC}"
    local title="${3:-}"
    local min_width="${4:-60}"
    local max_width="${5:-90}"
    local bold="${BOLD:-}"

    [[ "$tty_fd" =~ ^[0-9]+$ ]] || return 1

    local width top line bottom
    width=$(ui_box_width_for_lines "$min_width" "$max_width" "$title")
    top=$(ui_box_border_string top "$width")
    line=$(ui_box_line_string "$title" "$width")
    bottom=$(ui_box_border_string bottom "$width")

    tty_printf "$tty_fd" '%b%s%b\n' "${bold}${color}" "$top" "$NC"
    tty_printf "$tty_fd" '%b%s%b\n' "${bold}${color}" "$line" "$NC"
    tty_printf "$tty_fd" '%b%s%b\n' "${bold}${color}" "$bottom" "$NC"
}

canonicalize_confirmation_token() {
    local value
    value=$(normalize_tty_input "${1:-}")
    value=$(strip_confirmation_wrappers "$value")
    # Normalize known uppercase Cyrillic symbols explicitly (locale-agnostic).
    value="${value//Ё/e}"
    value="${value//Е/e}"
    value="${value//О/o}"
    value="${value//У/y}"
    value="${value//С/s}"
    value="${value//Ѕ/s}"
    value="${value//Н/n}"
    value="${value//Д/d}"
    value="${value//А/a}"
    value="${value//Т/t}"
    value="${value,,}"
    # Normalize mixed-layout lookalikes, then keep ASCII letters/digits only.
    value="${value//ё/e}"
    value="${value//е/e}"
    value="${value//о/o}"
    value="${value//у/y}"
    value="${value//с/s}"
    value="${value//ѕ/s}"
    value="${value//н/n}"
    value="${value//д/d}"
    value="${value//а/a}"
    value="${value//т/t}"
    value=$(printf '%s' "$value" | sed -E 's/[^a-z0-9]+//g')
    printf '%s' "$value"
}

strip_confirmation_wrappers() {
    local value
    value=$(trim_ws "${1:-}")

    local first last pair
    while ((${#value} >= 2)); do
        first="${value:0:1}"
        last="${value: -1}"
        pair="${first}${last}"
        case "$pair" in
            "''" | "\"\"" | '``' | "[]" | "()" | "{}" | "<>")
                value="${value:1:${#value}-2}"
                value=$(trim_ws "$value")
                ;;
            *)
                break
                ;;
        esac
    done

    printf '%s' "$value"
}

normalize_yes_no_token() {
    local value
    value=$(canonicalize_confirmation_token "${1:-}")
    printf '%s' "$value"
}

normalize_yes_token_hint() {
    local value
    value=$(normalize_yes_no_token "${1:-}")
    printf '%s' "$value"
}

extract_confirmation_token_tail() {
    local value tail token
    value=$(normalize_tty_input "${1:-}")
    [[ -n "$value" ]] || return 0

    tail=$(printf '%s' "$value" | sed -E 's/^.*[]:>][[:space:]]*//')
    if [[ -n "$tail" && "$tail" != "$value" ]]; then
        token=$(normalize_yes_no_token "$tail")
        if is_yes_input "$token" || is_no_input "$token"; then
            printf '%s' "$token"
            return 0
        fi
    fi

    if looks_like_confirmation_prompt_echo "$value"; then
        tail=$(printf '%s' "$value" | sed -E 's/^.*[[:space:]]+//')
        token=$(normalize_yes_no_token "$tail")
        if is_yes_input "$token" || is_no_input "$token"; then
            printf '%s' "$token"
        fi
    fi
}

looks_like_confirmation_prompt_echo() {
    local value lowered
    value=$(normalize_tty_input "${1:-}")
    [[ -n "$value" ]] || return 1

    lowered="${value,,}"
    [[ "$lowered" == *"yes"* && "$lowered" == *"no"* ]] || return 1

    case "$lowered" in
        *"вы уверены"* | *"подтверд"* | *"(yes/no)"* | *"для подтверждения"* | *"для отмены"*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

is_yes_input() {
    local value
    value=$(normalize_yes_token_hint "${1:-}")
    case "$value" in
        yes | y | da | d) return 0 ;;
        *) return 1 ;;
    esac
}

is_no_input() {
    local value
    value=$(normalize_yes_no_token "${1:-}")
    case "$value" in
        no | n | net) return 0 ;;
        *) return 1 ;;
    esac
}

prompt_yes_no_from_tty() {
    local tty_fd="${1:-}"
    local prompt_text="${2:-}"
    local retry_text="${3:-Введите yes или no}"
    local tty_write_fd="${4:-$tty_fd}"
    local answer normalized token

    [[ "$tty_fd" =~ ^[0-9]+$ ]] || return 2
    [[ "$tty_write_fd" =~ ^[0-9]+$ ]] || return 2

    while true; do
        if ! tty_printf "$tty_write_fd" '%s' "$prompt_text"; then
            return 2
        fi
        if ! read -r -u "$tty_fd" answer; then
            return 2
        fi
        normalized=$(normalize_tty_input "$answer")
        if [[ -z "$normalized" ]]; then
            return 1
        fi
        token=$(normalize_yes_no_token "$normalized")
        if is_yes_input "$token"; then
            return 0
        fi
        if is_no_input "$token"; then
            return 1
        fi
        token=$(extract_confirmation_token_tail "$normalized")
        if is_yes_input "$token"; then
            return 0
        fi
        if is_no_input "$token"; then
            return 1
        fi
        if ! tty_printf "$tty_write_fd" '%s\n' "$retry_text"; then
            return 2
        fi
    done
}
