#!/usr/bin/env bash
# shellcheck shell=bash

: "${SCRIPT_NAME:=Network Stealth Core}"
: "${SCRIPT_VERSION:=unknown}"
: "${LOG_CONTEXT:=установки}"
: "${INSTALL_LOG:=/var/log/xray-install.log}"
: "${VERBOSE:=false}"
: "${PROGRESS_MODE:=auto}"
: "${XRAY_PROGRESS_MODE:=auto}"
: "${PROGRESS_RENDER_MODE:=}"
: "${PROGRESS_RENDER_MODE_SOURCE:=}"
: "${PROGRESS_LAST_PERCENT:=-1}"
: "${PROGRESS_LINE_OPEN:=false}"
: "${PROGRESS_MODE_WARNED:=false}"
: "${LOGGING_BACKEND:=none}"
: "${LOGGING_STDOUT_FD:=}"
: "${LOGGING_STDERR_FD:=}"
: "${LOGGING_FIFO:=}"
: "${LOGGING_TEE_PID:=}"

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly DIM='\033[2m'
readonly NC='\033[0m'

UI_GLYPHS_INITIALIZED=false
UI_BOX_TL="+"
UI_BOX_TR="+"
UI_BOX_BL="+"
UI_BOX_BR="+"
UI_BOX_V="|"
UI_BOX_H="-"
UI_RULE_H="-"

ui_supports_unicode() {
    local locale="${LC_ALL:-${LC_CTYPE:-${LANG:-}}}"
    [[ -t 1 ]] || return 1
    [[ "$locale" =~ [Uu][Tt][Ff]-?8 ]]
}

ui_init_glyphs() {
    if [[ "${UI_GLYPHS_INITIALIZED:-false}" == "true" ]]; then
        return 0
    fi
    if ui_supports_unicode; then
        UI_BOX_TL="╔"
        UI_BOX_TR="╗"
        UI_BOX_BL="╚"
        UI_BOX_BR="╝"
        UI_BOX_V="║"
        UI_BOX_H="═"
        UI_RULE_H="━"
    else
        UI_BOX_TL="+"
        UI_BOX_TR="+"
        UI_BOX_BL="+"
        UI_BOX_BR="+"
        UI_BOX_V="|"
        UI_BOX_H="-"
        UI_RULE_H="-"
    fi
    UI_GLYPHS_INITIALIZED=true
}

ui_repeat_char() {
    local ch="$1"
    local count="$2"
    local out=""
    local i
    for ((i = 0; i < count; i++)); do
        out+="$ch"
    done
    printf '%s' "$out"
}

ui_box_sanitize_text() {
    local text="${1:-}"
    text="${text//$'\r'/ }"
    text="${text//$'\n'/ }"
    text="${text//$'\t'/ }"
    printf '%s' "$text"
}

ui_box_text_length() {
    local text="${1:-}"
    local ui_locale="${UI_TEXT_LOCALE:-C.UTF-8}"
    local LC_ALL="$ui_locale"
    local LANG="$ui_locale"
    printf '%s' "${#text}"
}

ui_box_text_slice() {
    local text="${1:-}"
    local start="${2:-0}"
    local length="${3:-}"
    local ui_locale="${UI_TEXT_LOCALE:-C.UTF-8}"
    local LC_ALL="$ui_locale"
    local LANG="$ui_locale"
    if [[ -n "$length" ]]; then
        printf '%s' "${text:start:length}"
    else
        printf '%s' "${text:start}"
    fi
}

ui_box_terminal_width() {
    local cols="${UI_BOX_TTY_COLS:-}"
    if [[ "$cols" =~ ^[0-9]+$ ]] && ((cols > 0)); then
        printf '%s' "$cols"
        return 0
    fi

    if [[ -t 1 ]]; then
        cols="${COLUMNS:-}"
        if [[ "$cols" =~ ^[0-9]+$ ]] && ((cols > 0)); then
            printf '%s' "$cols"
            return 0
        fi

        if command -v tput > /dev/null 2>&1; then
            cols=$(tput cols 2> /dev/null || echo 0)
            if [[ "$cols" =~ ^[0-9]+$ ]] && ((cols > 0)); then
                printf '%s' "$cols"
                return 0
            fi
        fi

        if command -v stty > /dev/null 2>&1; then
            cols=$(stty size 2> /dev/null | awk '{print $2}' || echo 0)
            if [[ "$cols" =~ ^[0-9]+$ ]] && ((cols > 0)); then
                printf '%s' "$cols"
                return 0
            fi
        fi
    fi

    printf '%s' 0
}

format_generated_timestamp() {
    local stamp
    stamp=$(LC_ALL=C date '+%a %b %d %I:%M:%S %p %Z %Y' 2> /dev/null || date '+%a %b %d %I:%M:%S %p %Z %Y')
    stamp=$(printf '%s' "$stamp" | sed -E 's/^([A-Za-z]{3}[[:space:]][A-Za-z]{3})[[:space:]]0([0-9])[[:space:]]/\1 \2 /')
    stamp=$(trim_ws "$stamp")
    printf '%s' "$stamp"
}

ui_box_fit_text() {
    local text="${1:-}"
    local width="${2:-60}"
    if ! [[ "$width" =~ ^[0-9]+$ ]] || ((width < 1)); then
        width=1
    fi

    local sanitized
    sanitized=$(ui_box_sanitize_text "$text")
    local sanitized_len
    sanitized_len=$(ui_box_text_length "$sanitized")

    if ((sanitized_len <= width)); then
        printf '%s' "$sanitized"
        return 0
    fi

    if ((width <= 3)); then
        ui_box_text_slice "$sanitized" 0 "$width"
        return 0
    fi

    printf '%s...' "$(ui_box_text_slice "$sanitized" 0 "$((width - 3))")"
}

ui_box_width_for_lines() {
    local min_width="${1:-60}"
    local max_width="${2:-80}"
    shift 2 || true

    if ! [[ "$min_width" =~ ^[0-9]+$ ]] || ((min_width < 1)); then
        min_width=1
    fi
    if ! [[ "$max_width" =~ ^[0-9]+$ ]] || ((max_width < min_width)); then
        max_width="$min_width"
    fi

    local tty_cols available_width
    tty_cols=$(ui_box_terminal_width)
    if [[ "$tty_cols" =~ ^[0-9]+$ ]] && ((tty_cols > 2)); then
        available_width=$((tty_cols - 2))
        if ((available_width < 1)); then
            available_width=1
        fi
        if ((max_width > available_width)); then
            max_width="$available_width"
        fi
        if ((min_width > available_width)); then
            min_width="$available_width"
        fi
    fi

    local desired="$min_width"
    local line sanitized line_len
    for line in "$@"; do
        sanitized=$(ui_box_sanitize_text "$line")
        line_len=$(ui_box_text_length "$sanitized")
        if ((line_len > desired)); then
            desired="$line_len"
        fi
    done

    if ((desired > max_width)); then
        desired="$max_width"
    fi
    printf '%s' "$desired"
}

ui_box_border_string() {
    local kind="${1:-top}"
    local width="${2:-60}"
    ui_init_glyphs
    case "$kind" in
        top) printf '%s%s%s' "$UI_BOX_TL" "$(ui_repeat_char "$UI_BOX_H" "$width")" "$UI_BOX_TR" ;;
        bottom) printf '%s%s%s' "$UI_BOX_BL" "$(ui_repeat_char "$UI_BOX_H" "$width")" "$UI_BOX_BR" ;;
        *) return 1 ;;
    esac
}

ui_box_line_string() {
    local text="${1:-}"
    local width="${2:-60}"
    local fitted
    local pad_len
    local pad
    ui_init_glyphs
    fitted=$(ui_box_fit_text "$text" "$width")
    pad_len=$((width - $(ui_box_text_length "$fitted")))
    if ((pad_len < 0)); then
        pad_len=0
    fi
    pad=$(ui_repeat_char " " "$pad_len")
    printf '%s%s%s%s' "$UI_BOX_V" "$fitted" "$pad" "$UI_BOX_V"
}

ui_rule_string() {
    local width="${1:-58}"
    ui_init_glyphs
    ui_repeat_char "$UI_RULE_H" "$width"
}

ui_section_title_string() {
    local title="${1:-}"
    ui_init_glyphs
    if [[ "$UI_RULE_H" == "━" ]]; then
        printf -- '━━━ %s ━━━' "$title"
    else
        printf -- '--- %s ---' "$title"
    fi
}

russian_count_noun() {
    local count="${1:-0}"
    local one="${2:-}"
    local few="${3:-$one}"
    local many="${4:-$few}"

    if ! [[ "$count" =~ ^-?[0-9]+$ ]]; then
        count=0
    fi
    if ((count < 0)); then
        count=$((-count))
    fi

    local mod10=$((count % 10))
    local mod100=$((count % 100))
    if ((mod100 >= 11 && mod100 <= 14)); then
        printf '%s' "$many"
        return 0
    fi

    case "$mod10" in
        1) printf '%s' "$one" ;;
        2 | 3 | 4) printf '%s' "$few" ;;
        *) printf '%s' "$many" ;;
    esac
}

format_russian_count_noun() {
    local count="${1:-0}"
    shift || true
    printf '%s %s' "$count" "$(russian_count_noun "$count" "$@")"
}

setup_logging() {
    local log_dir
    log_dir=$(dirname "$INSTALL_LOG")
    mkdir -p "$log_dir"

    if [[ "${LOGGING_BACKEND:-none}" == "none" ]]; then
        local tmp_base fifo_path
        tmp_base="${TMPDIR:-/tmp}"
        if [[ ! -d "$tmp_base" || ! -w "$tmp_base" ]]; then
            tmp_base="/tmp"
        fi

        local fifo_dir=""
        fifo_dir=$(mktemp -d "${tmp_base}/xray-log.XXXXXX" 2> /dev/null || true)
        if [[ -n "$fifo_dir" ]]; then
            fifo_path="${fifo_dir}/stream"
        fi

        if [[ -n "$fifo_path" ]] && mkfifo -m 600 "$fifo_path" 2> /dev/null; then
            exec {LOGGING_STDOUT_FD}>&1
            exec {LOGGING_STDERR_FD}>&2
            tee -a "$INSTALL_LOG" < "$fifo_path" >&"$LOGGING_STDOUT_FD" &
            LOGGING_TEE_PID="$!"
            LOGGING_FIFO="$fifo_path"
            exec > "$fifo_path" 2>&1
            rm -f "$fifo_path"
            if [[ -n "$fifo_dir" ]]; then
                rmdir "$fifo_dir" 2> /dev/null || true
            fi
            LOGGING_FIFO=""
            LOGGING_BACKEND="fifo"
        else
            if [[ -n "$fifo_dir" ]]; then
                rm -rf "$fifo_dir" 2> /dev/null || true
            fi
            exec > >(tee -a "$INSTALL_LOG")
            exec 2>&1
            LOGGING_BACKEND="process_subst"
        fi
    fi

    local inner_width
    local title="${SCRIPT_NAME} v${SCRIPT_VERSION}"
    local subtitle="Автоматизация strongest-direct Xray Reality (xhttp + vless encryption + vision)"
    inner_width=$(ui_box_width_for_lines 60 92 "$title" "$subtitle")
    local box_top box_bottom
    box_top=$(ui_box_border_string top "$inner_width")
    box_bottom=$(ui_box_border_string bottom "$inner_width")
    local box_title box_subtitle
    box_title=$(ui_box_line_string "$title" "$inner_width")
    box_subtitle=$(ui_box_line_string "$subtitle" "$inner_width")

    echo "$box_top"
    echo -e "${BOLD}${box_title}${NC}"
    echo "$box_subtitle"
    echo "$box_bottom"
    echo ""
    printf '📝 Начало %s: %s\n\n' "$LOG_CONTEXT" "$(date '+%Y-%m-%d %H:%M:%S')"
}

sanitize_log_message() {
    local input="$*"
    if [[ -z "$input" ]]; then
        echo ""
        return 0
    fi

    printf '%s' "$input" | sed -E \
        -e 's/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/UUID-REDACTED/g' \
        -e 's/("privateKey"[[:space:]]*:[[:space:]]*")[^"]+/\1***REDACTED***/g' \
        -e 's/("password"[[:space:]]*:[[:space:]]*")[^"]+/\1***REDACTED***/g' \
        -e 's/(Private Key:[[:space:]]*)[^[:space:]]+/\1***REDACTED***/g' \
        -e 's/([?&](pbk|sid|password|token|privateKey)=)[^&#[:space:]]+/\1***REDACTED***/gI' \
        -e 's#vless://[^[:space:]]+#VLESS-REDACTED#gI' \
        -e 's/(password[[:space:]]*[:=][[:space:]]*)[^[:space:]]+/\1***REDACTED***/gI'
}

log() {
    local level="$1"
    shift
    local icon=""
    local color="${NC}"
    local message="$*"

    case "$level" in
        DEBUG)
            [[ "$VERBOSE" == "true" ]] || return 0
            icon="•"
            color="${DIM}"
            ;;
        INFO)
            icon="ℹ️ "
            color="${BLUE}"
            ;;
        OK)
            icon="✅"
            color="${GREEN}"
            ;;
        WARN)
            icon="⚠️ "
            color="${YELLOW}"
            ;;
        ERROR)
            icon="❌"
            color="${RED}"
            ;;
        STEP)
            icon="▶️ "
            color="${CYAN}"
            ;;
        *)
            icon="•"
            color="${NC}"
            ;;
    esac

    local sanitized_message
    sanitized_message=$(sanitize_log_message "$message")
    if [[ "${PROGRESS_LINE_OPEN:-false}" == "true" ]]; then
        printf '\r\033[K\n'
        PROGRESS_LINE_OPEN=false
    fi
    echo -e "${color}${icon} ${sanitized_message}${NC}"
}

debug() {
    log DEBUG "$@"
}

debug_file() {
    local msg="$*"
    msg=$(sanitize_log_message "$msg")
    if [[ -n "${INSTALL_LOG:-}" && -w "$(dirname "${INSTALL_LOG}")" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] DEBUG: $msg" >> "$INSTALL_LOG"
    fi
}

cleanup_logging_processes() {
    local backend="${LOGGING_BACKEND:-none}"
    if [[ "$backend" == "none" ]]; then
        return 0
    fi

    if [[ "$backend" == "fifo" ]]; then
        if [[ -n "${LOGGING_STDOUT_FD:-}" && -n "${LOGGING_STDERR_FD:-}" ]]; then
            exec 1>&"$LOGGING_STDOUT_FD" 2>&"$LOGGING_STDERR_FD"
            exec {LOGGING_STDOUT_FD}>&-
            exec {LOGGING_STDERR_FD}>&-
            LOGGING_STDOUT_FD=""
            LOGGING_STDERR_FD=""
        fi
        if [[ -n "${LOGGING_TEE_PID:-}" && "$LOGGING_TEE_PID" =~ ^[0-9]+$ ]]; then
            wait "$LOGGING_TEE_PID" 2> /dev/null || true
        fi
        if [[ -n "${LOGGING_FIFO:-}" && -p "${LOGGING_FIFO}" ]]; then
            rm -f "$LOGGING_FIFO" 2> /dev/null || true
        fi
        LOGGING_TEE_PID=""
        LOGGING_FIFO=""
        LOGGING_BACKEND="none"
        return 0
    fi

    if command -v pgrep > /dev/null 2>&1; then
        local -a tee_pids=()
        mapfile -t tee_pids < <(pgrep -P $$ -x tee || true)
        local pid
        for pid in "${tee_pids[@]}"; do
            [[ "$pid" =~ ^[0-9]+$ ]] || continue
            kill "$pid" 2> /dev/null || true
            wait "$pid" 2> /dev/null || true
        done
    fi
    LOGGING_BACKEND="none"
}

hint() {
    if [[ "${PROGRESS_LINE_OPEN:-false}" == "true" ]]; then
        printf '\r\033[K\n'
        PROGRESS_LINE_OPEN=false
    fi
    echo -e "  ${DIM}💡 Подсказка: $*${NC}"
}

resolve_progress_mode() {
    local mode="${PROGRESS_MODE:-${XRAY_PROGRESS_MODE:-auto}}"
    mode=$(trim_ws "${mode,,}")
    [[ -z "$mode" ]] && mode="auto"
    [[ "$mode" == "off" ]] && mode="none"

    if [[ -n "${PROGRESS_RENDER_MODE:-}" && "${PROGRESS_RENDER_MODE_SOURCE:-}" == "$mode" ]]; then
        printf '%s\n' "$PROGRESS_RENDER_MODE"
        return 0
    fi

    case "$mode" in
        bar | plain | none)
            PROGRESS_RENDER_MODE="$mode"
            ;;
        auto)
            if [[ ! -t 1 || "${TERM:-}" == "dumb" ]]; then
                PROGRESS_RENDER_MODE="plain"
            else
                local cols=0
                if command -v tput > /dev/null 2>&1; then
                    cols=$(tput cols 2> /dev/null || echo 0)
                fi
                if [[ "$cols" =~ ^[0-9]+$ ]] && ((cols > 0 && cols < 120)); then
                    PROGRESS_RENDER_MODE="plain"
                else
                    PROGRESS_RENDER_MODE="bar"
                fi
            fi
            ;;
        *)
            if [[ "${PROGRESS_MODE_WARNED:-false}" != "true" ]]; then
                log WARN "Некорректный PROGRESS_MODE: ${mode} (используем auto)"
                PROGRESS_MODE_WARNED=true
            fi
            PROGRESS_RENDER_MODE="bar"
            mode="auto"
            ;;
    esac

    PROGRESS_RENDER_MODE_SOURCE="$mode"
    printf '%s\n' "$PROGRESS_RENDER_MODE"
}

progress_bar() {
    local current="$1"
    local total="$2"
    if [[ ! "$current" =~ ^[0-9]+$ ]] || [[ ! "$total" =~ ^[0-9]+$ ]]; then
        return 0
    fi
    if [[ "$total" -le 0 ]]; then
        return 0
    fi

    local mode
    mode=$(resolve_progress_mode)
    local percentage=$((current * 100 / total))

    if [[ "$mode" == "none" ]]; then
        PROGRESS_LINE_OPEN=false
        if ((current == total)); then
            PROGRESS_LAST_PERCENT=-1
        fi
        return 0
    fi

    if [[ "$mode" == "plain" ]]; then
        if ((current <= 1)); then
            PROGRESS_LAST_PERCENT=-1
        fi
        if ((percentage != PROGRESS_LAST_PERCENT || current == total)); then
            printf '%b[%3d%%] %d/%d%b\n' "$CYAN" "$percentage" "$current" "$total" "$NC"
            PROGRESS_LAST_PERCENT=$percentage
        fi
        PROGRESS_LINE_OPEN=false
        if ((current == total)); then
            PROGRESS_LAST_PERCENT=-1
        fi
        return 0
    fi

    local width=40
    local filled=$((width * current / total))
    local empty=$((width - filled))
    local fill_char="█"
    local empty_char="░"
    local locale="${LC_ALL:-${LC_CTYPE:-${LANG:-}}}"
    if [[ "$locale" != *[Uu][Tt][Ff]-8* && "$locale" != *[Uu][Tt][Ff]8* ]]; then
        fill_char="#"
        empty_char="-"
    fi

    local bar
    printf '\r\033[K%b[' "$CYAN"
    bar=$(printf "%${filled}s")
    bar=${bar// /$fill_char}
    printf "%s" "$bar"
    bar=$(printf "%${empty}s")
    bar=${bar// /$empty_char}
    printf "%s" "$bar"
    printf '] %3d%% %b' "$percentage" "$NC"

    if [[ $current -eq $total ]]; then
        echo ""
        PROGRESS_LINE_OPEN=false
        PROGRESS_LAST_PERCENT=-1
    else
        PROGRESS_LINE_OPEN=true
    fi
    return 0
}
