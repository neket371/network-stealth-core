#!/usr/bin/env bats

@test "help command works" {
    run bash -eo pipefail -c 'bash ./xray-reality.sh --help'
    [ "$status" -eq 0 ]
}

@test "dry-run install exits successfully" {
    run bash -eo pipefail -c 'bash ./xray-reality.sh --dry-run install'
    [ "$status" -eq 0 ]
}

@test "unknown command is rejected instead of falling back to install" {
    run bash -eo pipefail -c 'bash ./xray-reality.sh foo --dry-run'
    [ "$status" -ne 0 ]
    [[ "$output" == *"Неизвестная команда: foo"* ]]
}

@test "status rejects unexpected positional arguments" {
    run bash -eo pipefail -c 'bash ./xray-reality.sh status foo --dry-run'
    [ "$status" -ne 0 ]
    [[ "$output" == *"Неожиданные позиционные аргументы"* ]]
}

@test "help shows add-clients command" {
    run bash -eo pipefail -c 'bash ./xray-reality.sh --help'
    [ "$status" -eq 0 ]
    [[ "$output" == *"add-clients"* ]]
}

@test "help shows add-keys command" {
    run bash -eo pipefail -c 'bash ./xray-reality.sh --help'
    [ "$status" -eq 0 ]
    [[ "$output" == *"add-keys"* ]]
}

@test "dry-run add-clients exits successfully" {
    run bash -eo pipefail -c 'bash ./xray-reality.sh --dry-run add-clients'
    [ "$status" -eq 0 ]
}

@test "add-clients rejects more than one positional argument" {
    run bash -eo pipefail -c 'bash ./xray-reality.sh add-clients 3 4 --dry-run'
    [ "$status" -ne 0 ]
    [[ "$output" == *"Неожиданные позиционные аргументы"* ]]
}

@test "dry-run add-keys exits successfully" {
    run bash -eo pipefail -c 'bash ./xray-reality.sh --dry-run add-keys'
    [ "$status" -eq 0 ]
}

@test "add-clients is parsed as valid action" {
    run bash -eo pipefail -c '
    source ./lib.sh
    parse_args add-clients 3
    echo "$ACTION:$ADD_CLIENTS_COUNT"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "add-clients:3" ]
}

@test "add-clients without count defaults to empty" {
    run bash -eo pipefail -c '
    source ./lib.sh
    parse_args add-clients
    echo "$ACTION:${ADD_CLIENTS_COUNT:-empty}"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "add-clients:empty" ]
}

@test "add-keys is parsed as valid action" {
    run bash -eo pipefail -c '
    source ./lib.sh
    parse_args add-keys 2
    echo "$ACTION:$ADD_CLIENTS_COUNT"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "add-keys:2" ]
}

@test "dry-run uninstall exits successfully" {
    run bash -eo pipefail -c 'bash ./xray-reality.sh --dry-run uninstall'
    [ "$status" -eq 0 ]
}

@test "uninstall is parsed as valid action" {
    run bash -eo pipefail -c '
    source ./lib.sh
    parse_args uninstall
    echo "$ACTION"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "uninstall" ]
}

@test "repair is parsed as valid action" {
    run bash -eo pipefail -c '
    source ./lib.sh
    parse_args repair
    echo "$ACTION"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "repair" ]
}

@test "help shows full removal description for uninstall" {
    run bash -eo pipefail -c 'bash ./xray-reality.sh --help'
    [ "$status" -eq 0 ]
    [[ "$output" == *"Full removal"* ]]
}

@test "wrapper rejects unsafe bootstrap repo url" {
    run bash -eo pipefail -c '
    set -euo pipefail
    tmp="$(mktemp -d)"
    cp ./xray-reality.sh "$tmp/xray-reality.sh"
    chmod +x "$tmp/xray-reality.sh"
    XRAY_REPO_URL="http://example.com/repo.git" bash "$tmp/xray-reality.sh" install
  '
    [ "$status" -ne 0 ]
    [[ "$output" == *"unsupported repo URL"* ]]
}

@test "wrapper strict pin mode fails without commit pin" {
    run bash -eo pipefail -c '
    set -euo pipefail
    tmp="$(mktemp -d)"
    cp ./xray-reality.sh "$tmp/xray-reality.sh"
    chmod +x "$tmp/xray-reality.sh"
    XRAY_BOOTSTRAP_REQUIRE_PIN=true XRAY_BOOTSTRAP_AUTO_PIN=false bash "$tmp/xray-reality.sh" install
  '
    [ "$status" -ne 0 ]
    [[ "$output" == *"XRAY_BOOTSTRAP_REQUIRE_PIN=true"* ]]
}

@test "wrapper treats invalid XRAY_BOOTSTRAP_REQUIRE_PIN as strict mode" {
    run bash -eo pipefail -c '
    set -euo pipefail
    tmp="$(mktemp -d)"
    cp ./xray-reality.sh "$tmp/xray-reality.sh"
    chmod +x "$tmp/xray-reality.sh"
    XRAY_BOOTSTRAP_REQUIRE_PIN=broken XRAY_BOOTSTRAP_AUTO_PIN=false bash "$tmp/xray-reality.sh" install
  '
    [ "$status" -ne 0 ]
    [[ "$output" == *"XRAY_BOOTSTRAP_REQUIRE_PIN=true"* ]]
}

@test "wrapper ignores untrusted MODULE_DIR env and sources modules from trusted paths" {
    run bash -eo pipefail -c '
    set -euo pipefail
    tmp="$(mktemp -d)"
    cp ./xray-reality.sh "$tmp/xray-reality.sh"
    chmod +x "$tmp/xray-reality.sh"
    mkdir -p "$tmp/mockbin"

    cat > "$tmp/mockbin/git" << '"'"'EOF'"'"'
#!/usr/bin/env bash
set -euo pipefail
log_file="${MOCK_GIT_LOG:?}"
printf "%s\n" "$*" >> "$log_file"

if [[ "${1:-}" == "clone" ]]; then
    target="${@: -1}"
    mkdir -p "$target"
    cat > "$target/lib.sh" << '"'"'LIBEOF'"'"'
#!/usr/bin/env bash
MODULE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
main() { echo "wrapper-ok"; }
LIBEOF
    chmod +x "$target/lib.sh"
    : > "$target/install.sh"
    : > "$target/config.sh"
    : > "$target/service.sh"
    : > "$target/health.sh"
    : > "$target/export.sh"
    mkdir -p "$target/modules/lib" "$target/modules/config" "$target/modules/install"
    : > "$target/modules/lib/validation.sh"
    : > "$target/modules/lib/common_utils.sh"
    : > "$target/modules/lib/globals_contract.sh"
    : > "$target/modules/lib/firewall.sh"
    : > "$target/modules/lib/lifecycle.sh"
    : > "$target/modules/lib/runtime_reuse.sh"
    : > "$target/modules/lib/domain_sources.sh"
    : > "$target/modules/config/domain_planner.sh"
    : > "$target/modules/config/add_clients.sh"
    : > "$target/modules/config/shared_helpers.sh"
    : > "$target/modules/install/bootstrap.sh"
    exit 0
fi

exit 0
EOF
    chmod +x "$tmp/mockbin/git"

    log_file="$tmp/git.log"
    mkdir -p "$tmp/evil"
    printf "%s\n" "echo evil-module-source" > "$tmp/evil/install.sh"
    PATH="$tmp/mockbin:$PATH" \
        MOCK_GIT_LOG="$log_file" \
        MODULE_DIR="$tmp/evil" \
        XRAY_BOOTSTRAP_REQUIRE_PIN=false \
        XRAY_BOOTSTRAP_AUTO_PIN=false \
        bash "$tmp/xray-reality.sh" --help > "$tmp/out.txt" 2> "$tmp/err.txt"

    grep -q "wrapper-ok" "$tmp/out.txt"
    if grep -q "evil-module-source" "$tmp/out.txt"; then
        echo "wrapper sourced untrusted MODULE_DIR"
        exit 1
    fi
  '
    [ "$status" -eq 0 ]
}

@test "wrapper maps legacy main ref to ubuntu and falls back to ref clone in non-strict mode" {
    run bash -eo pipefail -c '
    set -euo pipefail
    tmp="$(mktemp -d)"
    cp ./xray-reality.sh "$tmp/xray-reality.sh"
    chmod +x "$tmp/xray-reality.sh"
    mkdir -p "$tmp/mockbin"

    cat > "$tmp/mockbin/git" << '"'"'EOF'"'"'
#!/usr/bin/env bash
set -euo pipefail
log_file="${MOCK_GIT_LOG:?}"
printf "%s\n" "$*" >> "$log_file"

if [[ "${1:-}" == "ls-remote" ]]; then
    exit 2
fi

if [[ "${1:-}" == "clone" ]]; then
    target="${@: -1}"
    mkdir -p "$target"
    cat > "$target/lib.sh" << '"'"'LIBEOF'"'"'
#!/usr/bin/env bash
MODULE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
main() { echo "wrapper-ok"; }
LIBEOF
    chmod +x "$target/lib.sh"
    : > "$target/install.sh"
    : > "$target/config.sh"
    : > "$target/service.sh"
    : > "$target/health.sh"
    : > "$target/export.sh"
    mkdir -p "$target/modules/lib" "$target/modules/config" "$target/modules/install"
    : > "$target/modules/lib/validation.sh"
    : > "$target/modules/lib/common_utils.sh"
    : > "$target/modules/lib/globals_contract.sh"
    : > "$target/modules/lib/firewall.sh"
    : > "$target/modules/lib/lifecycle.sh"
    : > "$target/modules/lib/runtime_reuse.sh"
    : > "$target/modules/lib/domain_sources.sh"
    : > "$target/modules/config/domain_planner.sh"
    : > "$target/modules/config/add_clients.sh"
    : > "$target/modules/config/shared_helpers.sh"
    : > "$target/modules/install/bootstrap.sh"
    exit 0
fi

exit 0
EOF
    chmod +x "$tmp/mockbin/git"

    log_file="$tmp/git.log"
    PATH="$tmp/mockbin:$PATH" \
        MOCK_GIT_LOG="$log_file" \
        XRAY_REPO_REF=main \
        XRAY_BOOTSTRAP_REQUIRE_PIN=false \
        XRAY_BOOTSTRAP_AUTO_PIN=true \
        bash "$tmp/xray-reality.sh" --help > "$tmp/out.txt" 2> "$tmp/err.txt"

    grep -q "wrapper-ok" "$tmp/out.txt"
    grep -q "XRAY_REPO_REF=main is deprecated; using '\''ubuntu'\''" "$tmp/err.txt"
    grep -q "failed to resolve commit for ref '\''ubuntu'\''" "$tmp/err.txt"
    grep -Eq "^clone .*--branch[[:space:]]+ubuntu" "$log_file"
  '
    [ "$status" -eq 0 ]
}

@test "wrapper defaults to ubuntu branch when no ref is provided" {
    run bash -eo pipefail -c '
    set -euo pipefail
    tmp="$(mktemp -d)"
    cp ./xray-reality.sh "$tmp/xray-reality.sh"
    chmod +x "$tmp/xray-reality.sh"
    mkdir -p "$tmp/mockbin"

    cat > "$tmp/mockbin/git" << '"'"'EOF'"'"'
#!/usr/bin/env bash
set -euo pipefail
log_file="${MOCK_GIT_LOG:?}"
printf "%s\n" "$*" >> "$log_file"

if [[ "${1:-}" == "clone" ]]; then
    target="${@: -1}"
    mkdir -p "$target"
    cat > "$target/lib.sh" << '"'"'LIBEOF'"'"'
#!/usr/bin/env bash
MODULE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
main() { echo "wrapper-ok"; }
LIBEOF
    chmod +x "$target/lib.sh"
    : > "$target/install.sh"
    : > "$target/config.sh"
    : > "$target/service.sh"
    : > "$target/health.sh"
    : > "$target/export.sh"
    mkdir -p "$target/modules/lib" "$target/modules/config" "$target/modules/install"
    : > "$target/modules/lib/validation.sh"
    : > "$target/modules/lib/common_utils.sh"
    : > "$target/modules/lib/globals_contract.sh"
    : > "$target/modules/lib/firewall.sh"
    : > "$target/modules/lib/lifecycle.sh"
    : > "$target/modules/lib/runtime_reuse.sh"
    : > "$target/modules/lib/domain_sources.sh"
    : > "$target/modules/config/domain_planner.sh"
    : > "$target/modules/config/add_clients.sh"
    : > "$target/modules/config/shared_helpers.sh"
    : > "$target/modules/install/bootstrap.sh"
    exit 0
fi

exit 0
EOF
    chmod +x "$tmp/mockbin/git"

    log_file="$tmp/git.log"
    PATH="$tmp/mockbin:$PATH" \
        MOCK_GIT_LOG="$log_file" \
        XRAY_BOOTSTRAP_REQUIRE_PIN=false \
        XRAY_BOOTSTRAP_AUTO_PIN=false \
        bash "$tmp/xray-reality.sh" --help > "$tmp/out.txt" 2> "$tmp/err.txt"

    grep -q "wrapper-ok" "$tmp/out.txt"
    grep -q "Using default bootstrap ref: ubuntu" "$tmp/out.txt"
    grep -Eq "^clone .*--branch[[:space:]]+ubuntu" "$log_file"
  '
    [ "$status" -eq 0 ]
}

@test "wrapper can default to latest release tag when XRAY_BOOTSTRAP_DEFAULT_REF=release" {
    run bash -eo pipefail -c '
    set -euo pipefail
    tmp="$(mktemp -d)"
    cp ./xray-reality.sh "$tmp/xray-reality.sh"
    chmod +x "$tmp/xray-reality.sh"
    mkdir -p "$tmp/mockbin"

    cat > "$tmp/mockbin/git" << '"'"'EOF'"'"'
#!/usr/bin/env bash
set -euo pipefail
log_file="${MOCK_GIT_LOG:?}"
printf "%s\n" "$*" >> "$log_file"

if [[ "${1:-}" == "ls-remote" ]]; then
    if [[ "$*" == *"refs/tags/v*"* ]]; then
        echo "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa refs/tags/v4.1.0"
        echo "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb refs/tags/v4.2.0"
        echo "cccccccccccccccccccccccccccccccccccccccc refs/tags/v4.3.0-rc1"
        exit 0
    fi
    exit 0
fi

if [[ "${1:-}" == "clone" ]]; then
    target="${@: -1}"
    mkdir -p "$target"
    cat > "$target/lib.sh" << '"'"'LIBEOF'"'"'
#!/usr/bin/env bash
MODULE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
main() { echo "wrapper-ok"; }
LIBEOF
    chmod +x "$target/lib.sh"
    : > "$target/install.sh"
    : > "$target/config.sh"
    : > "$target/service.sh"
    : > "$target/health.sh"
    : > "$target/export.sh"
    mkdir -p "$target/modules/lib" "$target/modules/config" "$target/modules/install"
    : > "$target/modules/lib/validation.sh"
    : > "$target/modules/lib/common_utils.sh"
    : > "$target/modules/lib/globals_contract.sh"
    : > "$target/modules/lib/firewall.sh"
    : > "$target/modules/lib/lifecycle.sh"
    : > "$target/modules/lib/runtime_reuse.sh"
    : > "$target/modules/lib/domain_sources.sh"
    : > "$target/modules/config/domain_planner.sh"
    : > "$target/modules/config/add_clients.sh"
    : > "$target/modules/config/shared_helpers.sh"
    : > "$target/modules/install/bootstrap.sh"
    exit 0
fi

exit 0
EOF
    chmod +x "$tmp/mockbin/git"

    log_file="$tmp/git.log"
    PATH="$tmp/mockbin:$PATH" \
        MOCK_GIT_LOG="$log_file" \
        XRAY_BOOTSTRAP_DEFAULT_REF=release \
        XRAY_BOOTSTRAP_REQUIRE_PIN=false \
        XRAY_BOOTSTRAP_AUTO_PIN=false \
        bash "$tmp/xray-reality.sh" --help > "$tmp/out.txt" 2> "$tmp/err.txt"

    grep -q "wrapper-ok" "$tmp/out.txt"
    grep -q "Using latest release tag for bootstrap: v4.2.0" "$tmp/out.txt"
    grep -Eq "^clone .*--branch[[:space:]]+v4.2.0" "$log_file"
  '
    [ "$status" -eq 0 ]
}

@test "wrapper resolves annotated tag to peeled commit for pin verification" {
    run bash -eo pipefail -c '
    set -euo pipefail
    tmp="$(mktemp -d)"
    cp ./xray-reality.sh "$tmp/xray-reality.sh"
    chmod +x "$tmp/xray-reality.sh"
    mkdir -p "$tmp/mockbin"

    cat > "$tmp/mockbin/git" << '"'"'EOF'"'"'
#!/usr/bin/env bash
set -euo pipefail
log_file="${MOCK_GIT_LOG:?}"
printf "%s\n" "$*" >> "$log_file"

tag_obj="31ffe1393058b491dba91729fe27641439bfbfc6"
tag_commit="cbffe82772164353b3f5ee079abe744b05eed564"

if [[ "${1:-}" == "ls-remote" ]]; then
    if [[ "$*" == *"refs/tags/v9.9.9^{}"* ]]; then
        echo "${tag_commit} refs/tags/v9.9.9^{}"
        exit 0
    fi
    if [[ "$*" == *"refs/tags/v9.9.9"* ]]; then
        echo "${tag_obj} refs/tags/v9.9.9"
        exit 0
    fi
    exit 0
fi

if [[ "${1:-}" == "clone" ]]; then
    target="${@: -1}"
    mkdir -p "$target"
    cat > "$target/lib.sh" << '"'"'LIBEOF'"'"'
#!/usr/bin/env bash
MODULE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
main() { echo "wrapper-ok"; }
LIBEOF
    chmod +x "$target/lib.sh"
    : > "$target/install.sh"
    : > "$target/config.sh"
    : > "$target/service.sh"
    : > "$target/health.sh"
    : > "$target/export.sh"
    mkdir -p "$target/modules/lib" "$target/modules/config" "$target/modules/install"
    : > "$target/modules/lib/validation.sh"
    : > "$target/modules/lib/common_utils.sh"
    : > "$target/modules/lib/globals_contract.sh"
    : > "$target/modules/lib/firewall.sh"
    : > "$target/modules/lib/lifecycle.sh"
    : > "$target/modules/lib/runtime_reuse.sh"
    : > "$target/modules/lib/domain_sources.sh"
    : > "$target/modules/config/domain_planner.sh"
    : > "$target/modules/config/add_clients.sh"
    : > "$target/modules/config/shared_helpers.sh"
    : > "$target/modules/install/bootstrap.sh"
    exit 0
fi

if [[ "${1:-}" == "-C" ]]; then
    shift 2
    case "${1:-}" in
        fetch)
            if [[ "${@: -1}" == "$tag_commit" ]]; then
                exit 0
            fi
            echo "unexpected pinned commit: ${@: -1}" >&2
            exit 1
            ;;
        checkout)
            exit 0
            ;;
        rev-parse)
            echo "$tag_commit"
            exit 0
            ;;
    esac
fi

exit 0
EOF
    chmod +x "$tmp/mockbin/git"

    log_file="$tmp/git.log"
    PATH="$tmp/mockbin:$PATH" \
        MOCK_GIT_LOG="$log_file" \
        XRAY_REPO_REF=v9.9.9 \
        XRAY_BOOTSTRAP_AUTO_PIN=true \
        bash "$tmp/xray-reality.sh" --help > "$tmp/out.txt" 2> "$tmp/err.txt"

    grep -q "wrapper-ok" "$tmp/out.txt"
    grep -q "Pinned source commit verified: cbffe82772164353b3f5ee079abe744b05eed564" "$tmp/out.txt"
    grep -Eq "^-C .* fetch --quiet --depth=1 origin cbffe82772164353b3f5ee079abe744b05eed564" "$log_file"
    if grep -q "unexpected pinned commit" "$tmp/err.txt"; then
        echo "wrapper pinned annotated tag object instead of peeled commit"
        exit 1
    fi
  '
    [ "$status" -eq 0 ]
}

@test "parse_args accepts --server-ip and --server-ip6 with equals syntax" {
    run bash -eo pipefail -c '
    source ./lib.sh
    parse_args install --server-ip=1.1.1.1 --server-ip6=2001:db8::1 --num-configs=1
    echo "${ACTION}|${SERVER_IP}|${SERVER_IP6}|${XRAY_NUM_CONFIGS}"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "install|1.1.1.1|2001:db8::1|1" ]
}

@test "parse_args accepts --progress-mode with equals syntax" {
    run bash -eo pipefail -c '
    source ./lib.sh
    parse_args install --progress-mode=plain --num-configs=1
    echo "${ACTION}|${PROGRESS_MODE}|${XRAY_NUM_CONFIGS}"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "install|plain|1" ]
}

@test "wrapper does not pass --branch when XRAY_REPO_REF is commit hash" {
    run bash -eo pipefail -c '
    set -euo pipefail
    tmp="$(mktemp -d)"
    cp ./xray-reality.sh "$tmp/xray-reality.sh"
    chmod +x "$tmp/xray-reality.sh"
    mkdir -p "$tmp/mockbin"

    cat > "$tmp/mockbin/git" << '"'"'EOF'"'"'
#!/usr/bin/env bash
set -euo pipefail
log_file="${MOCK_GIT_LOG:?}"
printf "%s\n" "$*" >> "$log_file"

if [[ "${1:-}" == "clone" ]]; then
    target="${@: -1}"
    mkdir -p "$target"
    cat > "$target/lib.sh" << '"'"'LIBEOF'"'"'
#!/usr/bin/env bash
MODULE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
main() { echo "wrapper-ok"; }
LIBEOF
    chmod +x "$target/lib.sh"
    : > "$target/install.sh"
    : > "$target/config.sh"
    : > "$target/service.sh"
    : > "$target/health.sh"
    : > "$target/export.sh"
    mkdir -p "$target/modules/lib" "$target/modules/config" "$target/modules/install"
    : > "$target/modules/lib/validation.sh"
    : > "$target/modules/lib/common_utils.sh"
    : > "$target/modules/lib/globals_contract.sh"
    : > "$target/modules/lib/firewall.sh"
    : > "$target/modules/lib/lifecycle.sh"
    : > "$target/modules/lib/runtime_reuse.sh"
    : > "$target/modules/lib/domain_sources.sh"
    : > "$target/modules/config/domain_planner.sh"
    : > "$target/modules/config/add_clients.sh"
    : > "$target/modules/config/shared_helpers.sh"
    : > "$target/modules/install/bootstrap.sh"
    exit 0
fi

if [[ "${1:-}" == "-C" ]]; then
    shift 2
    case "${1:-}" in
        fetch | checkout)
            exit 0
            ;;
        rev-parse)
            echo "1111111111111111111111111111111111111111"
            exit 0
            ;;
    esac
fi

if [[ "${1:-}" == "ls-remote" ]]; then
    echo "1111111111111111111111111111111111111111    refs/heads/ubuntu"
    exit 0
fi

exit 0
EOF
    chmod +x "$tmp/mockbin/git"

    log_file="$tmp/git.log"
    PATH="$tmp/mockbin:$PATH" \
        MOCK_GIT_LOG="$log_file" \
        XRAY_REPO_REF=1111111 \
        XRAY_BOOTSTRAP_AUTO_PIN=true \
        bash "$tmp/xray-reality.sh" --help > "$tmp/out.txt" 2> "$tmp/err.txt"

    grep -q "wrapper-ok" "$tmp/out.txt"
    if grep -Eq "clone .*--branch[[:space:]]+1111111" "$log_file"; then
        echo "clone called with --branch for commit ref"
        exit 1
    fi
  '
    [ "$status" -eq 0 ]
}

@test "uninstall without tty requires explicit --yes confirmation" {
    run bash -eo pipefail -c '
    set -euo pipefail
    source ./lib.sh
    source ./service.sh
    ASSUME_YES=false
    NON_INTERACTIVE=false
    uninstall_all
  '
    [ "$status" -ne 0 ]
    [[ "$output" == *"/dev/tty недоступен"* ]]
    [[ "$output" == *"--yes --non-interactive"* ]]
}
