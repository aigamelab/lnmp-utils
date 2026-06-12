#!/usr/bin/env bash
# lnmp-utils Docker installer — cross-platform LNMP deployment
#
# Works on macOS, Linux, Windows (Git Bash / WSL2).
# Leverages existing docker/ orchestration scripts.
#
# Usage:
#   ./install-docker.sh up                    # build + start (default: lnmp, debian)
#   ./install-docker.sh up -d ubuntu          # specific distro
#   ./install-docker.sh up -b -d debian       # load pre-built tar (fast)
#   ./install-docker.sh down                  # stop and remove
#   ./install-docker.sh status                # show services
#   ./install-docker.sh logs                  # tail logs
#   ./install-docker.sh shell                 # enter container

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}"
DOCKER_DIR="${PROJECT_DIR}/docker"
COMPOSE_FILE="${DOCKER_DIR}/docker-compose.deploy.yml"

# Load shared build logic (find_build_repo, build_full_image)
if [[ -f "${DOCKER_DIR}/build-image.sh" ]]; then
    source "${DOCKER_DIR}/build-image.sh"
fi
BUILD_REPO_DIR=$(find_build_repo "${PROJECT_DIR}")

# ---- Platform detection ----
detect_platform() {
    local os
    os="$(uname -s)"
    case "${os}" in
        Darwin)  echo "macos" ;;
        Linux)   echo "linux" ;;
        MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
        *)       echo "unknown" ;;
    esac
}

PLATFORM="$(detect_platform)"

# ---- Defaults ----
DISTRO="${LNMP_DISTRO:-debian}"
COMPONENTS="${LNMP_COMPONENTS:-lnmp}"
USE_BUILD="0"

# Default data directory per platform
if [[ -z "${DATA_DIR:-}" ]]; then
    case "${PLATFORM}" in
        macos)   DATA_DIR="${HOME}/.lnmp-utils/data" ;;
        linux)   DATA_DIR="/data/lnmp-utils" ;;
        windows) DATA_DIR="${HOME}/lnmp-utils-data" ;;
        *)       DATA_DIR="${PROJECT_DIR}/docker/docker-fs" ;;
    esac
fi
export DATA_DIR

# ---- Helpers ----

log()  { echo -e "\033[0;32m[lnmp-docker]\033[0m $*"; }
warn() { echo -e "\033[1;33m[lnmp-docker]\033[0m $*"; }
err()  { echo -e "\033[0;31m[lnmp-docker]\033[0m $*" >&2; }

check_docker() {
    if ! command -v docker &>/dev/null; then
        err "Docker not found. Please install Docker first:"
        case "${PLATFORM}" in
            macos)   err "  https://docs.docker.com/desktop/install/mac-install/" ;;
            linux)   err "  https://docs.docker.com/engine/install/" ;;
            windows) err "  https://docs.docker.com/desktop/install/windows-install/" ;;
        esac
        exit 1
    fi
    if ! docker info &>/dev/null; then
        err "Docker is not running. Please start Docker first."
        exit 1
    fi
}

_VOLUMES_FILE="${DOCKER_DIR}/docker-compose.volumes.yml"

compose() {
    local _files=(-f "${COMPOSE_FILE}")
    if [[ -n "${DATA_DIR:-}" && -f "${_VOLUMES_FILE}" ]]; then
        _files+=(-f "${_VOLUMES_FILE}")
    fi
    docker compose "${_files[@]}" --project-name "lnmp-utils" "$@"
}

ensure_data_dirs() {
    if [[ -n "${DATA_DIR:-}" ]]; then
        mkdir -p "${DATA_DIR}"/{log,conf,www,db,pkg,cache,script}
        log "Data directory: ${DATA_DIR}"
        cat > "${_VOLUMES_FILE}" <<EOF
services:
  lnmp:
    volumes:
      - ${DATA_DIR}/log:/data/log
      - ${DATA_DIR}/conf:/data/conf
      - ${DATA_DIR}/www:/data/www
      - ${DATA_DIR}/db:/data/db
      - ${DATA_DIR}/pkg:/data/pkg
      - ${DATA_DIR}/cache:/data/cache
      - ${DATA_DIR}/script:/data/script
EOF
    else
        rm -f "${_VOLUMES_FILE}"
        log "DATA_DIR is empty — skipping data volume mounts"
    fi
}

# ---- Image management ----

load_prebuilt_image() {
    local tar_file="${BUILD_REPO_DIR}/docker/lnmp-utils-${DISTRO}.tar"
    if [[ -f "${tar_file}" ]]; then
        log "Loading pre-built image: ${tar_file}"
        docker load < "${tar_file}"
        return 0
    fi
    return 1
}

build_image_locally() {
    if [[ ! -d "${BUILD_REPO_DIR}" ]]; then
        err "Build repo not found: ${BUILD_REPO_DIR}"
        err "Please clone lnmp-utils-build alongside lnmp-utils,"
        err "or use '-b' with a pre-built image tar."
        exit 1
    fi
    if [[ ! -f "${BUILD_REPO_DIR}/Dockerfile" ]]; then
        err "Build-repo Dockerfile not found in ${BUILD_REPO_DIR}"
        exit 1
    fi

    log "Building LNMP Docker image locally (this will take a while)..."
    log "  Distro: ${DISTRO}"

    source "${DOCKER_DIR}/build-image.sh"
    build_full_image "${DISTRO}" "${BUILD_REPO_DIR}" "${PROJECT_DIR}"
}

ensure_image() {
    # Check if image already exists locally
    if docker image inspect "aigameism/lnmp-utils:${DISTRO}" &>/dev/null; then
        return 0
    fi

    if [[ "${USE_BUILD}" == "1" ]]; then
        # -b: try pre-built tar first, fall back to build
        if load_prebuilt_image; then
            return 0
        fi
        warn "Pre-built image not found, falling back to local build..."
    fi

    build_image_locally
}

# ---- Commands ----

cmd_up() {
    check_docker
    ensure_image
    ensure_data_dirs

    log "Starting LNMP (${DISTRO}, ${COMPONENTS})..."
    LNMP_DISTRO="${DISTRO}" LNMP_COMPONENTS="${COMPONENTS}" compose up -d

    log "LNMP is starting. Wait a few seconds, then run:"
    echo "  ./install-docker.sh status"
    echo "  curl http://localhost"
}

cmd_build() {
    # CI-style build: compile at container start time for full component flexibility
    check_docker
    local _components="${COMPONENTS:-php mariadb openresty redis}"

    # Stop and remove existing container if any
    if docker ps -a --format '{{.Names}}' | grep -q '^lnmp-utils$'; then
        log "Removing existing container..."
        docker rm -f lnmp-utils 2>/dev/null || true
    fi

    # Build build-env stage only (systemd + install scripts, no compiled components)
    log "Building build environment: lnmp-test-${DISTRO}:latest..."
    DOCKER_BUILDKIT=1 docker build \
        --target build-env \
        -t "lnmp-test-${DISTRO}:latest" \
        -f "${DOCKER_DIR}/Dockerfile.${DISTRO}" \
        "${PROJECT_DIR}"

    # Create data dirs
    ensure_data_dirs

    # Build mount arguments
    local mount_args=(
        -v "${PROJECT_DIR}:/opt/lnmp-utils:ro"
    )

    # Mount build repo if available (needed for -b install)
    if [[ -d "${BUILD_REPO_DIR}" ]]; then
        mount_args+=(-v "${BUILD_REPO_DIR}:/opt/lnmp-utils-build:ro")
    fi

    # Mount data dirs if DATA_DIR is set
    if [[ -n "${DATA_DIR:-}" ]]; then
        for _d in log conf www db pkg cache script; do
            mkdir -p "${DATA_DIR}/${_d}"
            mount_args+=(-v "${DATA_DIR}/${_d}:/data/${_d}")
        done
    fi

    log "Starting container with custom components: ${_components}"
    log "Compilation will happen inside the container (this takes a while)..."
    log "Monitor with: docker logs -f lnmp-utils"

    docker run -d --name lnmp-utils --privileged \
        -p "${HOST_PORT_WWW:-80}:80" \
        -p "${HOST_PORT_DB:-3306}:3306" \
        -p "${HOST_PORT_REDIS:-6379}:6379" \
        "${mount_args[@]}" \
        "lnmp-test-${DISTRO}:latest" \
        -b -c ${_components}

    log "Container started. Compilation in progress..."
    echo "  Watch logs:  docker logs -f lnmp-utils"
    echo "  Check status: ./install-docker.sh status"
}

cmd_pack() {
    local target="${1:-all}"
    local distros=()

    case "${target}" in
        all)       distros=("debian" "ubuntu" "centos" "rockylinux") ;;
        debian|ubuntu|centos|rockylinux)
                   distros=("${target}") ;;
        *)         err "Unknown distro: ${target}. Use: debian|ubuntu|centos|rockylinux|all"; return 1 ;;
    esac

    check_docker
    if [[ ! -f "${BUILD_REPO_DIR}/Dockerfile" ]]; then
        err "Build-repo Dockerfile not found at ${BUILD_REPO_DIR}/Dockerfile"
        err "lnmp-utils-build must contain the build-repo source (Dockerfile + linux/)."
        err "Tip: ln -s ../../lnmp-utils-build ${PROJECT_DIR}/lnmp-utils-build"
        return 1
    fi

    log "Packing images: ${distros[*]}"
    for d in "${distros[@]}"; do
        log "============================================"
        log "Packing: ${d}"
        log "============================================"

        build_full_image "${d}" "${BUILD_REPO_DIR}" "${PROJECT_DIR}"

        log "Exporting lnmp-utils-${d}.tar..."
        mkdir -p "${BUILD_REPO_DIR}/docker"
        docker save "aigameism/lnmp-utils:${d}" \
            > "${BUILD_REPO_DIR}/docker/lnmp-utils-${d}.tar"
        log "Done: ${BUILD_REPO_DIR}/docker/lnmp-utils-${d}.tar"
    done

    log "All done."
}

cmd_down() {
    log "Stopping LNMP..."
    compose down "$@"
    log "Stopped."
}

cmd_restart() {
    log "Restarting..."
    compose restart "$@"
    log "Restarted."
}

cmd_status() {
    echo "=== Container ==="
    compose ps 2>/dev/null || echo "  (not running)"

    echo ""
    echo "=== Services ==="
    if docker exec lnmp-utils systemctl list-units --type=service --state=running 2>/dev/null \
        | grep -qE 'openresty|mariadb|php-fpm|redis|memcached|mongod'; then
        docker exec lnmp-utils systemctl list-units --type=service --state=running 2>/dev/null \
            | grep -E 'openresty|mariadb|php-fpm|redis|memcached|mongod|UNIT' \
            | awk '{printf "  %-15s %s %s %s\n", $1, $2, $3, $4}'
    else
        echo "  (no services running — container may still be starting)"
    fi
}

cmd_logs() {
    compose logs -f --tail="${1:-100}"
}

cmd_shell() {
    log "Opening shell in container..."
    docker exec -it lnmp-utils bash 2>/dev/null || docker exec -it lnmp-utils sh
}

cmd_help() {
    cat <<'EOF'
lnmp-utils Docker installer — cross-platform LNMP deployment

Usage: ./install-docker.sh <command> [options]

Commands:
  up        Start LNMP stack (pre-built image, fast, fixed components)
  build     Build and start with custom components (CI-style, flexible)
  pack      Build full image and export tar to lnmp-utils-build/docker/
  down      Stop and remove the container
  restart   Restart all services
  status    Show container and service status
  logs      Tail container logs (default: last 100 lines)
  shell     Open bash inside the container
  help      Show this help

Options:
  -d, --distro <name>   Linux distro: debian|ubuntu|centos|rockylinux (default: debian)
  -c <components>       Components for 'build': php,mariadb,openresty,redis,...
                        Components preset for 'up': lnmp|full|minimal|nosql
  -b                    For 'up': use pre-built image from lnmp-utils-build/docker/ (fast)

Environment:
  DATA_DIR              Host path for persistent data (default: platform-specific)
                        Leave empty to skip data volume mounts.
  LNMP_COMPONENTS       Default components preset (default: lnmp)
  LNMP_DISTRO           Default distro (default: debian)

Examples:
  ./install-docker.sh up                       # pre-built: lnmp + debian
  ./install-docker.sh up -b -d debian          # load pre-built tar (fastest)
  ./install-docker.sh build -c php redis       # custom components, compile at runtime
  ./install-docker.sh build -d ubuntu -c php mariadb openresty
  ./install-docker.sh pack debian              # build + export tar
  ./install-docker.sh pack all                 # build all 4 distros
  DATA_DIR= ./install-docker.sh up             # no data mounts
  ./install-docker.sh status
  ./install-docker.sh down

EOF
}

# ---- Main ----

# Parse global options before command
ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--distro)
            DISTRO="$2"; shift 2 ;;
        --distro=*)
            DISTRO="${1#*=}"; shift ;;
        -c)
            COMPONENTS="$2"; shift 2 ;;
        -b)
            USE_BUILD="1"; shift ;;
        *)
            ARGS+=("$1"); shift ;;
    esac
done

# Restore positional args for subcommands
set -- "${ARGS[@]}"

case "${1:-help}" in
    up)       cmd_up ;;
    build)    cmd_build ;;
    pack)     shift; cmd_pack "$@" ;;
    down)     shift; cmd_down "$@" ;;
    restart)  shift; cmd_restart "$@" ;;
    status)   cmd_status ;;
    logs)     cmd_logs "${2:-100}" ;;
    shell)    cmd_shell ;;
    help|*)   cmd_help ;;
esac
