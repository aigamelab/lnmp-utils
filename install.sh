#!/bin/bash
# lnmp-utils — Linux NMP environment installer
# https://github.com/tinyphporg/lnmp-utils

PATH="/usr/local/bin:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/sbin:${HOME}/bin"
export PATH

if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root."
    exit 1
fi

# Script directory and its parent
CURRENT_DIR=$(cd "$(dirname "$0")" && pwd)"/"
PARENT_DIR=$(dirname "$CURRENT_DIR")

# Default install and data root directories (override in install.conf)
DATA_DIR="/data/"
INSTALL_DIR="/usr/local/"


# Load shared functions: detect_system, os_init, in_array, show_help, etc.
FUNC_INIT_FILE="${CURRENT_DIR}/func_init.sh"
if [ -f "${FUNC_INIT_FILE}" ]; then
    source "${FUNC_INIT_FILE}"
else
    echo "Error: ${FUNC_INIT_FILE} does not exist."
    exit 1
fi

# System detection & OS-specific init script
detect_system

# Source the OS-specific init script (init_rhel.sh / init_debian.sh)
OS_SCRIPT_FILE="${CURRENT_DIR}/init_${OS_SCRIPT_NAME}.sh"
if [ -f "${OS_SCRIPT_FILE}" ]; then
    source "${OS_SCRIPT_FILE}"
else
    echo "Error: ${OS_ID} is not supported."
    exit 1
fi

# Validate OS version and install required system packages
os_install_check

# Option defaults (must be initialized before the parsing loop)
INSTALL_IS_QUIET="0"
INSTALL_IS_BUILD="0"
INSTALL_NO_CLEAR="0"
INSTALL_COMPONENTS=()
INSTALL_MODULES=()
INSTALL_OPTIONS=()

# Command-line option parsing
opt_init
while [ -n "$1" ]; do
    case "${1}" in
        -q|--quiet)
            shift
            INSTALL_IS_QUIET='1'
            ;;
        -c|--component)
            shift
            while [ -n "${1}" ] && [ "${1:0:1}" != "-" ]; do
                INSTALL_COMPONENTS[${#INSTALL_COMPONENTS}]="$1"
                shift
            done
            ;;
        -m|--mode)
            shift
            while [ -n "${1}" ] && [ "${1:0:1}" != "-" ]; do
                INSTALL_MODULES[${#INSTALL_MODULES}]="$1"
                shift
            done
            ;;
        -o)
            shift
            while [ -n "${1}" ] && [ "${1:0:1}" != "-" ]; do
                INSTALL_OPTIONS[${#INSTALL_OPTIONS}]="$1"
                shift
            done
            ;;
        -h|--help)
            shift
            show_help
            ;;
        -b|--build)
            shift
            INSTALL_IS_BUILD="1"
            ;;
        --no-clear)
            shift
            INSTALL_NO_CLEAR="1"
            ;;
        *)
            shift
            ;;
    esac
done

check_dir "${INSTALL_DIR}"
check_dir "${DATA_DIR}"
CPU_NUM=$(grep -c -e "model name" -e "processor" /proc/cpuinfo)

# Auto-select source mirror based on network speed (GitHub vs Gitee)
# Set MIRROR=github or MIRROR=gitee to force a specific mirror.
GIT_URL_GITHUB="https://github.com/aigameism/lnmp-utils-packages.git"
SOURCE_URL_GITHUB="https://raw.githubusercontent.com/aigameism/lnmp-utils-packages/master/"
GIT_URL_GITEE="https://gitee.com/aigameism/lnmp-utils-packages.git"
SOURCE_URL_GITEE="https://raw.giteeusercontent.com/aigameism/lnmp-utils-packages/raw/master/"

if [ "${MIRROR:-}" = "github" ]; then
    GIT_URL="${GIT_URL_GITHUB}"
    SOURCE_URL="${SOURCE_URL_GITHUB}"
    echo "Using GitHub mirror (forced)"
elif [ "${MIRROR:-}" = "gitee" ]; then
    GIT_URL="${GIT_URL_GITEE}"
    SOURCE_URL="${SOURCE_URL_GITEE}"
    echo "Using Gitee mirror (forced)"
else
    _github_time=$(curl -s --connect-timeout 3 -o /dev/null -w "%{time_total}" \
        "https://raw.githubusercontent.com" 2>/dev/null)
    _gitee_time=$(curl -s --connect-timeout 3 -o /dev/null -w "%{time_total}" \
        "https://raw.giteeusercontent.com" 2>/dev/null)

    # Use the faster mirror; prefer GitHub for anonymous git clone
    if [ -n "${_github_time}" ]; then
        GIT_URL="${GIT_URL_GITHUB}"
        SOURCE_URL="${SOURCE_URL_GITHUB}"
        echo "Using GitHub mirror (default)"
    elif [ -n "${_gitee_time}" ]; then
        GIT_URL="${GIT_URL_GITEE}"
        SOURCE_URL="${SOURCE_URL_GITEE}"
        echo "Using Gitee mirror (GitHub unreachable)"
    else
        GIT_URL="${GIT_URL_GITHUB}"
        SOURCE_URL="${SOURCE_URL_GITHUB}"
        echo "Using GitHub mirror (all unreachable, trying anyway)"
    fi
fi

BUILD_DIR="${PARENT_DIR}/lnmp-utils-build"
GIT_DIR="${CURRENT_DIR}/lnmp-utils-packages"


# ---- Package and temp directory setup ----
PKG_DIR="${CURRENT_DIR}pkg/"
PKG_MODULE_DIR="${PKG_DIR}module/"
PKG_COMPONENT_DIR="${PKG_DIR}component/"
PKG_SOURCE_CONF=""

# ---- Temporary directories ----
TMP_RANDOM_ID=$((RANDOM % 10000 + 30000))
TMP_DIR="/tmp/aigm-lnmp-utils/${TMP_RANDOM_ID}/"
TMP_COMPONENT_DIR="${TMP_DIR}component/"
TMP_MODULE_DIR="${TMP_DIR}module/"
TMP_PKG_DIR="${TMP_DIR}pkg/"

# ---- Source directories ----
SOURCE_DIR="${TMP_DIR}source/"
if [[ "${INSTALL_IS_BUILD}" == "1" ]]; then
    SOURCE_DIR="${BUILD_DIR}/linux/"
    if [ ! -d "$SOURCE_DIR" ]; then
        if [ ! -d "$GIT_DIR" ]; then
            mkdir -p "$GIT_DIR"
        fi
        if [ ! -f "$GIT_DIR/pkg.cnf" ] || [ ! -d "$GIT_DIR/pkg" ]; then
            cd "$GIT_DIR" && git clone "$GIT_URL" .
        fi
        if [ ! -f "$GIT_DIR/pkg.cnf" ] || [ ! -d "$GIT_DIR/pkg" ]; then
            echo "git clone failed: $GIT_URL"
            exit
        fi
    fi
fi

SOURCE_MODULE_DIR=${SOURCE_DIR}module/
SOURCE_COMPONENT_DIR=${SOURCE_DIR}component/

# ---- Data directories ----
DATA_WEB_DIR=${DATA_DIR}web/
DATA_DB_DIR=${DATA_DIR}db/
DATA_SCRIPT_DIR=${DATA_DIR}script/
DATA_CONF_DIR=${DATA_DIR}conf/
DATA_BAK_DIR=${DATA_DIR}bak/
DATA_LOG_DIR=${DATA_DIR}log/
DATA_DFS_DIR=${DATA_DIR}dfs/
DATA_CACHE_DIR=${DATA_DIR}cache/
DATA_INSTALL_LOG=${DATA_DIR}install.log

# ---- Module state variables ----
MOD_DIR=""
MOD_NAME=""
MOD_INSTALL_SCRIPT=""
MOD_PACKAGE_DIR=""
MOD_CONF_DIR=""

# ---- Component state variables ----
COM_DIR=""
COM_NAME=""
COM_SOURCE_FILE=""
COM_INSTALL_DIR=""
COM_INSTALL_SCRIPT=""
COM_3RD_DIR=""
COM_CONF_DIR=""
COM_DATA_CONF_DIR=""
COM_DATA_DB_DIR=""
COM_DATA_SCRIPT_DIR=""
COM_DATA_LOG_DIR=""


# ---- Logging and error handling ----
FUNC_INSTALL_FILE="${CURRENT_DIR}/func_install.sh"
if [ -f "${FUNC_INSTALL_FILE}" ]; then
    source "${FUNC_INSTALL_FILE}"
else
    echo "Error: ${FUNC_INSTALL_FILE} does not exist."
    exit 1
fi



os_init
os_install_init

create_dir $DATA_DIR $DATA_BAK_DIR
create_dir $PKG_DIR $PKG_COMPONENT_DIR $PKG_MODULE_DIR
create_dir $SOURCE_DIR $SOURCE_COMPONENT_DIR $SOURCE_MODULE_DIR
create_dir $DATA_BAK_DIR $DATA_WEB_DIR $DATA_DB_DIR $DATA_SCRIPT_DIR $DATA_CONF_DIR


if [ ${#INSTALL_COMPONENTS} == 0 ] && [  ${#INSTALL_MODULES} == 0 ];then
	INSTALL_MODULES[0]="lnmp"
fi

com_tmp_init
com_install "${INSTALL_COMPONENTS[*]}"

mod_tmp_init
mod_install "${INSTALL_MODULES[*]}"

if [ "${INSTALL_NO_CLEAR}" == '0' ]; then
	clear_tmp_dir
fi
