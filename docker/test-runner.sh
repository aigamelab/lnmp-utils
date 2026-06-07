#!/bin/bash
# lnmp-utils multi-distro install test runner
#
# Runs ./install.sh -b -c php mariadb openresty redis memcache
# across Rockylinux 10, CentOS Stream 9, Ubuntu 24.04, Debian 12.
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

# Test configuration
COMPONENTS="php mariadb openresty redis memcache"
INSTALL_ARGS="-b -c ${COMPONENTS}"

declare -A DISTROS=(
    ["rockylinux"]="rockylinux/rockylinux:10|Dockerfile.rockylinux"
    ["centos"]="quay.io/centos/centos:stream9|Dockerfile.centos"
    ["ubuntu"]="ubuntu:24.04|Dockerfile.ubuntu"
    ["debian"]="debian:12|Dockerfile.debian"
)

log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "${LOG_DIR}/summary.log"; }

run_test() {
    local name="$1"
    local image_base="${DISTROS[$name]%%|*}"
    local dockerfile="${DISTROS[$name]##*|}"
    local test_image="lnmp-test-${name}:latest"
    local log_file="${LOG_DIR}/${name}_${TIMESTAMP}.log"

    mkdir -p "${LOG_DIR}"

    log "============================================"
    log "Testing: ${name} (${image_base})"
    log "============================================"

    # Build test image
    log "Building ${name}..."
    if ! docker build \
        -t "${test_image}" \
        -f "${SCRIPT_DIR}/${dockerfile}" \
        "${PROJECT_DIR}" \
        > "${LOG_DIR}/${name}_build.log" 2>&1; then
        log "FAIL: ${name} - build error"
        tail -20 "${LOG_DIR}/${name}_build.log"
        return 1
    fi

    # Run install test
    log "Running install on ${name}..."
    set +e
    docker run --rm --privileged \
        -v "${PROJECT_DIR}:/opt/lnmp-utils" \
        -v /tmp/aigm-test-pkg:/tmp/aigm-lnmp-utils \
        "${test_image}" \
        ${INSTALL_ARGS} \
        > "${log_file}" 2>&1
    local exit_code=$?
    set -e

    # Analyze result
    if [ $exit_code -eq 0 ]; then
        log "PASS: ${name} (exit 0)"
    else
        log "FAIL: ${name} (exit ${exit_code})"
        log "  Last 30 lines of ${log_file}:"
        tail -30 "${log_file}" | while IFS= read -r line; do
            log "  | ${line}"
        done
    fi

    # Quick checks from log
    if grep -q "detect_system\|OS_ID" "${log_file}" 2>/dev/null; then
        log "  [OK] detect_system ran"
    fi
    if grep -q "com_install\|mod_install\|Installing" "${log_file}" 2>/dev/null; then
        log "  [OK] Component install started"
    fi
    if grep -qi "error\|fail" "${log_file}" 2>/dev/null; then
        log "  [WARN] Error/fail keywords found - check log"
    fi

    log ""
    return $exit_code
}

main() {
    local target="${1:-all}"

    echo "lnmp-utils multi-distro install test"
    echo "Date: $(date)"
    echo "Components: ${COMPONENTS}"
    echo "Args: ${INSTALL_ARGS}"
    echo ""

    mkdir -p "${LOG_DIR}"
    :> "${LOG_DIR}/summary.log"

    local results=()
    local all_pass=true

    if [ "${target}" = "all" ]; then
        local distros=("rockylinux" "centos" "ubuntu" "debian")
    else
        local distros=("${target}")
    fi

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
