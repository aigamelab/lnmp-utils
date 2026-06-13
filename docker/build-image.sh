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
#     Uses --build-context to inject local build-repo directly (no registry lookup).

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

    echo "Building aigameism/lnmp-utils:${distro}..."
    DOCKER_BUILDKIT=1 docker build \
        --build-context "build-repo=${build_repo_dir}" \
        -t "aigameism/lnmp-utils:${distro}" \
        -f "${project_dir}/docker/Dockerfile.${distro}" \
        "${project_dir}"
}
