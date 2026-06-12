#!/bin/bash
# Shared Docker image build logic — sourced by install.sh, install-docker.sh
#
# Provides:
#   find_build_repo [project_dir]
#     Returns the path to lnmp-utils-build/. Creates ./lnmp-utils-build/docker/
#     if missing. Checks the local subdirectory only; use a symlink for the
#     sibling-project layout.
#
#   build_full_image <distro> <build_repo_dir> <project_dir>
#     Builds the full-stack aigameism/lnmp-utils:<distro> image.
#     Prerequisite image aigm/lnmp-utils-build is built automatically if missing.

find_build_repo() {
    local project_dir="${1:-${PROJECT_DIR:-.}}"
    local _dir="${project_dir}/lnmp-utils-build"
    if [[ ! -d "${_dir}" ]]; then
        mkdir -p "${_dir}/docker"
    fi
    echo "${_dir}"
}

build_full_image() {
    local distro="$1"
    local build_repo_dir="$2"
    local project_dir="$3"

    # Stage 0: build-repo image (FROM scratch, provides source tarballs)
    if ! docker image inspect aigm/lnmp-utils-build &>/dev/null; then
        echo "[0/2] Building aigm/lnmp-utils-build..."
        DOCKER_BUILDKIT=1 docker build \
            -t aigm/lnmp-utils-build \
            "${build_repo_dir}"
    else
        echo "[0/2] aigm/lnmp-utils-build already exists, skipping."
    fi

    # Stage 1: full-stack image (compiles all components, this IS the CI test)
    echo "[1/2] Building aigameism/lnmp-utils:${distro}..."
    DOCKER_BUILDKIT=1 docker build \
        -t "aigameism/lnmp-utils:${distro}" \
        -f "${project_dir}/docker/Dockerfile.${distro}" \
        "${project_dir}"
}
