#!/bin/bash
# lnmp-utils multi-distro install test runner
#
# Runs ./install.sh -b -c php mariadb openresty redis memcache
# across Rockylinux 10, CentOS Stream 9, Ubuntu 24.04, Debian 12.
#
# SAFETY: Source mounts are READ-ONLY (:ro) — install never writes to /opt/lnmp-utils*.
# Writable data mounts to /Volumes/data/docker-fs/<project>/ isolated from source.
# Temp data uses system /tmp/ only. See shared docs: 安全规范.md.
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

# Auto-detect build project path (sibling directory)
DEFAULT_BUILD_SRC="$(dirname "$PROJECT_DIR")/lnmp-utils-build"
BUILD_SRC="${BUILD_SRC:-$DEFAULT_BUILD_SRC}"

# Test configuration
COMPONENTS="php mariadb openresty redis memcache"
INSTALL_ARGS="-b -c ${COMPONENTS}"

# Data mount root — writable runtime data isolated from source
DATA_MNT_ROOT="${DATA_MNT_ROOT:-/Volumes/data/docker-fs/lnmp-utils}"
DATA_MNT_DIRS=("log" "conf" "www" "db" "pkg" "cache" "script")

declare -A DISTROS=(
    ["rockylinux"]="rockylinux/rockylinux:10|Dockerfile.rockylinux"
    ["centos"]="quay.io/centos/centos:stream9|Dockerfile.centos"
    ["ubuntu"]="ubuntu:24.04|Dockerfile.ubuntu"
    ["debian"]="debian:12|Dockerfile.debian"
)

log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "${LOG_DIR}/summary.log"; }

# ---- Test runner ----

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

    # Run install test — source :ro, data in docker-fs, temp in /tmp/
    log "Running install on ${name}..."
    set +e

    # Ensure data and temp directories exist
    for _d in "${DATA_MNT_DIRS[@]}"; do
        mkdir -p "${DATA_MNT_ROOT}/${_d}"
    done
    mkdir -p /tmp/aigm-test-pkg

    local mount_args=(
        -v "${PROJECT_DIR}:/opt/lnmp-utils:ro"
        -v /tmp/aigm-test-pkg:/tmp/aigm-lnmp-utils
    )
    if [ -d "${BUILD_SRC}" ]; then
        mount_args+=(-v "${BUILD_SRC}:/opt/lnmp-utils-build:ro")
    fi
    for _d in "${DATA_MNT_DIRS[@]}"; do
        mount_args+=(-v "${DATA_MNT_ROOT}/${_d}:/data/${_d}")
    done

    docker run --rm --privileged \
        "${mount_args[@]}" \
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

# ---- Main ----

main() {
    local target="all"
    local distros=()

    for arg in "$@"; do
        case "$arg" in
            all|rockylinux|centos|ubuntu|debian) target="$arg" ;;
        esac
    done

    echo "lnmp-utils multi-distro install test"
    echo "Date: $(date)"
    echo "Components: ${COMPONENTS}"
    echo "Args: ${INSTALL_ARGS}"
    echo ""

    mkdir -p "${LOG_DIR}"
    :> "${LOG_DIR}/summary.log"

    if [ "${target}" = "all" ]; then
        distros=("rockylinux" "centos" "ubuntu" "debian")
    else
        distros=("${target}")
    fi

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
