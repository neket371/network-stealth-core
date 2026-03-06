#!/usr/bin/env bash
# shellcheck shell=bash

trim_ws() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

is_valid_ipv4() {
    local ip="$1"
    local IFS='.'
    local -a octets
    read -r -a octets <<< "$ip"

    [[ ${#octets[@]} -ne 4 ]] && return 1

    local octet
    for octet in "${octets[@]}"; do
        [[ ! "$octet" =~ ^[0-9]+$ ]] && return 1
        [[ ${#octet} -gt 1 && "$octet" == 0* ]] && return 1
        if ((10#$octet > 255)); then
            return 1
        fi
    done
    return 0
}

is_valid_ipv6() {
    local ip="${1:-}"
    local left right stripped total
    local -a groups=()
    local group

    [[ -n "$ip" ]] || return 1
    ip="${ip%%%*}"
    [[ -n "$ip" ]] || return 1
    [[ "$ip" == *:* ]] || return 1
    [[ "$ip" != *":::"* ]] || return 1
    [[ "$ip" != :* || "$ip" == ::* ]] || return 1
    [[ "$ip" != *: || "$ip" == *:: ]] || return 1
    [[ "$ip" =~ ^[0-9A-Fa-f:]+$ ]] || return 1

    if [[ "$ip" == *"::"* ]]; then
        stripped="${ip//::/}"
        [[ "$stripped" != *"::"* ]] || return 1

        left="${ip%%::*}"
        right="${ip##*::}"
        total=0

        if [[ -n "$left" ]]; then
            IFS=':' read -r -a groups <<< "$left"
            for group in "${groups[@]}"; do
                [[ -n "$group" && "$group" =~ ^[0-9A-Fa-f]{1,4}$ ]] || return 1
                total=$((total + 1))
            done
        fi
        if [[ -n "$right" ]]; then
            IFS=':' read -r -a groups <<< "$right"
            for group in "${groups[@]}"; do
                [[ -n "$group" && "$group" =~ ^[0-9A-Fa-f]{1,4}$ ]] || return 1
                total=$((total + 1))
            done
        fi

        ((total < 8)) || return 1
        return 0
    fi

    IFS=':' read -r -a groups <<< "$ip"
    [[ ${#groups[@]} -eq 8 ]] || return 1
    for group in "${groups[@]}"; do
        [[ "$group" =~ ^[0-9A-Fa-f]{1,4}$ ]] || return 1
    done
    return 0
}

is_valid_domain() {
    local domain="$1"
    [[ -z "$domain" ]] && return 1
    [[ ${#domain} -gt 253 ]] && return 1
    [[ ! "$domain" =~ ^[a-zA-Z0-9.-]+$ ]] && return 1
    [[ "$domain" =~ ^[.-] ]] && return 1
    [[ "$domain" =~ [.-]$ ]] && return 1
    [[ "$domain" =~ \.\. ]] && return 1
    [[ ! "$domain" =~ \. ]] && return 1
    local IFS='.'
    local -a labels
    read -r -a labels <<< "$domain"
    local label
    for label in "${labels[@]}"; do
        [[ -z "$label" ]] && return 1
        [[ ${#label} -gt 63 ]] && return 1
        [[ "$label" == -* || "$label" == *- ]] && return 1
    done
    return 0
}

is_valid_port() {
    local port="$1"
    [[ ! "$port" =~ ^[0-9]+$ ]] && return 1
    [[ ${#port} -gt 5 ]] && return 1
    [[ "$port" -lt 1 || "$port" -gt 65535 ]] && return 1
    return 0
}

is_valid_grpc_service_name() {
    local name="$1"
    [[ -n "$name" ]] || return 1
    [[ ${#name} -le 128 ]] || return 1
    [[ "$name" != *".."* ]] || return 1
    [[ "$name" =~ ^[A-Za-z][A-Za-z0-9]*(\.[A-Za-z][A-Za-z0-9_]*){2,}$ ]] || return 1
    return 0
}

is_valid_xhttp_path() {
    local path="${1:-}"
    [[ -n "$path" ]] || return 1
    [[ ${#path} -le 160 ]] || return 1
    [[ "$path" == /* ]] || return 1
    [[ "$path" != *"//"* ]] || return 1
    [[ "$path" != *".."* ]] || return 1
    [[ "$path" != *[[:space:]?#]* ]] || return 1
    [[ "$path" =~ ^/[A-Za-z0-9._~/-]+$ ]] || return 1
    return 0
}

version_lt() {
    local a="${1#v}"
    local b="${2#v}"
    [[ -z "$a" || -z "$b" ]] && return 1
    if [[ "$a" == "$b" ]]; then
        return 1
    fi
    if command -v sort > /dev/null 2>&1 && [[ "$a" != *-* && "$b" != *-* ]] && printf '1\n2\n' | sort -V > /dev/null 2>&1; then
        [[ "$(printf '%s\n' "$a" "$b" | sort -V | head -n 1)" == "$a" ]]
        return $?
    fi

    local a_core b_core a_suffix b_suffix
    a_core="${a%%-*}"
    b_core="${b%%-*}"
    a_suffix=""
    b_suffix=""
    if [[ "$a" == *-* ]]; then
        a_suffix="${a#"$a_core"-}"
    fi
    if [[ "$b" == *-* ]]; then
        b_suffix="${b#"$b_core"-}"
    fi

    local IFS='.'
    local -a a_parts=() b_parts=()
    read -r -a a_parts <<< "$a_core"
    read -r -a b_parts <<< "$b_core"

    local max_len="${#a_parts[@]}"
    if ((${#b_parts[@]} > max_len)); then
        max_len="${#b_parts[@]}"
    fi

    local i a_num b_num
    for ((i = 0; i < max_len; i++)); do
        a_num="${a_parts[$i]:-0}"
        b_num="${b_parts[$i]:-0}"
        [[ "$a_num" =~ ^[0-9]+$ ]] || a_num=0
        [[ "$b_num" =~ ^[0-9]+$ ]] || b_num=0
        if ((10#$a_num < 10#$b_num)); then
            return 0
        fi
        if ((10#$a_num > 10#$b_num)); then
            return 1
        fi
    done

    if [[ -n "$a_suffix" && -z "$b_suffix" ]]; then
        return 0
    fi
    if [[ -z "$a_suffix" && -n "$b_suffix" ]]; then
        return 1
    fi
    if [[ -n "$a_suffix" && -n "$b_suffix" ]]; then
        [[ "$a_suffix" < "$b_suffix" ]]
        return $?
    fi
    return 1
}
