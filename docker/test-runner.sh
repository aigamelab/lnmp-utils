#!/bin/bash
# lnmp-utils multi-distro CI test runner
#
# Tests install.sh by building the full image for each distro.
# install.sh runs at Docker build time — build success = test pass.
#
# Usage:
#   ./docker/test-runner.sh [distro]       # run one or all
#   ./docker/test-runner.sh rockylinux     # single distro
#   ./docker/test-runner.sh all            # all distros (default)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="${PROJECT_DIR}/docker/logs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

declare -A DISTROS=(
    ["rockylinux"]="rockylinux/rockylinux:10"
    ["centos"]="rockylinux/rockylinux:8"
    ["ubuntu"]="ubuntu:24.04"
    ["debian"]="debian:12"
)

log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "${LOG_DIR}/summary.log"; }

run_test() {
    local name="$1"
    local image="aigameism/lnmp-utils:${name}"
    local log_file="${LOG_DIR}/${name}_${TIMESTAMP}.log"

    mkdir -p "${LOG_DIR}"

    log "============================================"
    log "Testing: ${name} (${DISTROS[$name]})"
    log "  Image: ${image}"
    log "============================================"

    log "Building ${name} (install.sh runs at build time — this IS the test)..."
    if DOCKER_BUILDKIT=1 docker build \
        -t "${image}" \
        -f "${SCRIPT_DIR}/Dockerfile.${name}" \
        "${PROJECT_DIR}" \
        > "${log_file}" 2>&1; then
        log "PASS: ${name} — build succeeded"
    else
        log "FAIL: ${name} — build failed"
        log "  Last 30 lines of ${log_file}:"
        tail -30 "${log_file}" | while IFS= read -r line; do
            log "  | ${line}"
        done
        return 1
    fi

    # Quick checks from build log
    if grep -q "detect_system\|OS_ID" "${log_file}" 2>/dev/null; then
        log "  [OK] detect_system ran"
    fi
    if grep -q "com_install\|mod_install\|Installing" "${log_file}" 2>/dev/null; then
        log "  [OK] Component install started"
    fi
    if grep -qi "error\|fail" "${log_file}" 2>/dev/null; then
        log "  [WARN] Error/fail keywords found — check log"
    fi

    log ""
    return 0
}

main() {
    local target="${1:-all}"
    local distros=()

    case "${target}" in
        all)          distros=("rockylinux" "centos" "ubuntu" "debian") ;;
        rockylinux|centos|ubuntu|debian)
                      distros=("${target}") ;;
        *)            echo "Usage: $0 [rockylinux|centos|ubuntu|debian|all]"; exit 1 ;;
    esac

    echo "lnmp-utils multi-distro CI test"
    echo "Date: $(date)"
    echo "Method: docker build (install.sh runs at build time)"
    echo ""

    mkdir -p "${LOG_DIR}"
    :> "${LOG_DIR}/summary.log"

    local results=()
    local all_pass=true

    for d in "${distros[@]}"; do
        if run_test "$d"; then
            results+=("$d: PASS")
        else
            results+=("$d: FAIL")
            all_pass=false
        fi
    done

    log "============================================"
    log "Test Summary"
    log "============================================"
    for r in "${results[@]}"; do
        log "  $r"
    done

    if $all_pass; then
        log "All tests passed!"
        exit 0
    else
        log "Some tests failed. Check logs in ${LOG_DIR}/"
        exit 1
    fi
}

main "$@"
