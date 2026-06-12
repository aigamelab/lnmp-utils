# ---- System detection ----
detect_system() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID="${ID}"
        # Normalize: RHEL/RedHat/CentOS → centos, AlmaLinux → rocky (for platform ID)
        # Later mapped back to "rhel" for init script selection
        case "${ID}" in
            rhel|redhat)    OS_ID="centos" ;;
            almalinux)      OS_ID="rocky" ;;   # AlmaLinux uses rocky compat path
            *)              OS_ID="${ID}" ;;
        esac
        # Major version as integer: 7, 8, 9, 22, 11, etc.
        OS_VERSION_MAJOR="${VERSION_ID%%.*}"
        OS_PLATFORM="${OS_ID}${OS_VERSION_MAJOR}"
    elif [ -f /etc/centos-release ]; then
        OS_ID="centos"
        OS_VERSION_MAJOR=$(rpm -q --qf "%{VERSION}" "$(rpm -q --whatprovides /etc/centos-release)" 2>/dev/null | cut -d. -f1)
        OS_VERSION_MAJOR="${OS_VERSION_MAJOR:-7}"
        OS_PLATFORM="centos${OS_VERSION_MAJOR}"
    elif [ -f /etc/debian_version ]; then
        OS_ID="debian"
        OS_VERSION_MAJOR=$(cut -d. -f1 /etc/debian_version)
        OS_PLATFORM="debian${OS_VERSION_MAJOR}"
    else
        OS_ID="unknown"
        OS_VERSION_MAJOR="0"
        OS_PLATFORM="unknown"
    fi
    echo "Detected system: ${OS_ID} ${OS_PLATFORM} (major: ${OS_VERSION_MAJOR})"
    # Map OS_ID to init script name; RHEL family shares a single RHEL-compatible init
    OS_SCRIPT_NAME="${OS_ID}"
    case "${OS_ID}" in
	    rhel|redhat|centos|rocky) OS_SCRIPT_NAME="rhel";;
	    ubuntu)                    OS_SCRIPT_NAME="debian";;
    esac    
}

# Check if $1 exists in the remaining arguments (proper array search)
# Returns "1" if found, "0" if not
in_array() {
    local needle="$1"
    shift
    local element
    for element in "$@"; do
        if [[ "${element}" == "${needle}" ]]; then
            echo "1"
            return
        fi
    done
    echo "0"
}

write_log(){
	local log_date=$(date +"%Y-%m-%d %H:%M:%S")
	echo "${log_date} ${1}" | tee -a "$DATA_INSTALL_LOG"
}

error() {
	echo -e "\033[0;31;1mError:\033[0m ${1}"
	write_log "${1}"
	clear_tmp_dir
	exit 1
}

# Create system group and user if they don't exist
# Usage: user_add <group> [user] — if user is omitted, same as group
user_add() {
	local g="$1"
	local u="$2"

	if [ -z "${g}" ]; then
		return
	fi

	if [ -z "${u}" ]; then
		u="${g}"
	fi

	if [ "$(grep -c "^${g}:" /etc/group)" -eq 0 ]; then
		groupadd "${g}"
	fi
	if [ "$(grep -c "^${u}:" /etc/passwd)" -eq 0 ]; then
		useradd -g "${g}" "${u}"
	fi
}

# Create directories if they don't exist (default permission: 755)
create_dir() {
	if [ -z "${1}" ]; then
		return
	fi
	for p in "$@"; do
		if [ -d "$p" ]; then
			continue
		fi
		mkdir -p -m 755 "$p"
	done
}

show_help(){
	echo "lnmp-utils — Linux NMP environment installer"
	echo "-----------------------------------------------"
	echo "Supported: Debian 10+/Ubuntu 20.04+, RHEL 8+/CentOS 8+/Rocky 8+"
	echo ""
	echo "component list:"
	echo "lnmp: openresty(nginx+lua) mysql  php"
	echo "nosql:   redis memcached"
	echo "dfs:     fastdfs"
	echo "node.js: node"
	echo "From: https://github.com/tinyphporg/lnmp-utils"
    echo "---------------------"
    echo "module list:"
    echo "lnmp"
	echo "---------------------"
	echo "-h|--help            Help"
	echo "-q|--quiet           Silent installation mode"
	echo "-c|--component=xxx   Install components"
	echo "                     ./install.sh -c mysql php redis openresty node fastdfs ..."
	echo "-m|--mode=xxx        Install modules"
	echo "-o|--option          Options for installing components"
	echo "                     ./install.sh -c openresty -o fdfs proxy"
	echo "-b|--build           Build folder for custom component development (use when github.com is inaccessible)."
	echo "--no-clear           Do not clean up the installation folder."
	echo "--docker[=distro]    Deploy via Docker instead of traditional install."
	echo "                     distro: debian|ubuntu|centos|rockylinux (omit for interactive selection)"
	echo "                     -b --docker=debian: load pre-built image from lnmp-utils-build/docker/"
	echo "                     --docker=debian:      build image locally then deploy"
	echo "                     See also: install-docker.sh for cross-platform Docker management."
	exit
}

check_dir(){
	local dirs=('.' './' '../' '..' '/')
	if [ "${1}" = "" ] || [ "$(in_array "${1}" "${dirs[@]}")" = "1" ] || [ -f "${1}" ]; then
		echo "Invalid dirname: ${1}"
		exit
	fi
}

opt_init(){
	local tmpopt=$(getopt -o "qo:c:m:h" -l "component:,option:,mode:,quiet,help" -n "$0" -- "$@")
	set -- $tmpopt
}

# Public API: kill the process listening on a given port
killport() {
	if [ -z "${1}" ]; then
		return
	fi

	if ! command -v killall &>/dev/null; then
		pkg_install psmisc
	fi

	_killport_pn=""
	if command -v ss &>/dev/null; then
		_killport_pn=$(ss -tlnp | grep ":${1}\s" | awk '{print $6}' | awk -F',' '{print $2}' | awk -F'=' '{print $2}')
	fi
	if [ -n "${_killport_pn}" ]; then
		killall -9 "${_killport_pn}"
	fi
}

pkg_install() {
	echo "Warning: pkg_install is not implemented for ${OS_ID}"
}

pkg_uninstall() {
	echo "Warning: pkg_uninstall is not implemented for ${OS_ID}"
}

# OS-specific package wrappers (no-op when called on wrong OS)
rhel_pkg_install()   { [ "${OS_SCRIPT_NAME}" = "rhel"   ] || return 0; pkg_install "$@"; }
rhel_pkg_uninstall() { [ "${OS_SCRIPT_NAME}" = "rhel"   ] || return 0; pkg_uninstall "$@"; }
debian_pkg_install()   { [ "${OS_SCRIPT_NAME}" = "debian" ] || return 0; pkg_install "$@"; }
debian_pkg_uninstall() { [ "${OS_SCRIPT_NAME}" = "debian" ] || return 0; pkg_uninstall "$@"; }


# One-time OS initialization (shared across all distros)
os_init() {
	if [ "$INSTALL_IS_QUIET" = "1" ]; then
		return
	fi

	if [ ! -f /etc/ld.so.conf.d/lnmp-utils.conf ]; then
		rm -f /etc/localtime
		cp -f /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
		pkg_install chrony libtool
		systemctl enable --now chronyd 2>/dev/null || true
		chronyd -q 'server cn.pool.ntp.org iburst' 2>/dev/null || true
		hwclock --systohc 2>/dev/null || true

		cat >> /etc/ld.so.conf.d/lnmp-utils.conf <<EOT
/usr/local/lib
/usr/local/lib64
EOT
		ldconfig
	fi

	local sysctl_file="/etc/sysctl.d/99-lnmp-utils.conf"
	# Fall back to /etc/sysctl.conf on older systems
	if [ ! -d /etc/sysctl.d ]; then
		sysctl_file="/etc/sysctl.conf"
	fi
	if ! grep -q "^#patch by tinyphporg/lnmp-utils$" "$sysctl_file"; then

		cat >> "$sysctl_file" <<EOF
#patch by tinyphporg/lnmp-utils
net.ipv4.ip_forward = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.default.accept_source_route = 0
kernel.sysrq = 0
kernel.core_uses_pid = 1
net.ipv4.tcp_syncookies = 1
kernel.msgmnb = 65536
kernel.msgmax = 65536
kernel.shmmax = 68719476736
kernel.shmall = 4294967296
net.ipv4.tcp_max_tw_buckets = 6000
net.ipv4.tcp_sack = 1
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_wmem = 8192 4336600 873200
net.ipv4.tcp_rmem = 32768 4336600 873200
net.core.wmem_default = 8388608
net.core.rmem_default = 8388608
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.core.netdev_max_backlog = 262144
net.core.somaxconn = 262144
net.ipv4.tcp_max_orphans = 3276800
net.ipv4.tcp_max_syn_backlog = 262144
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_synack_retries = 1
net.ipv4.tcp_syn_retries = 1
# NOTE: tcp_tw_recycle was removed in Linux 4.12+ and is a no-op on modern kernels
net.ipv4.tcp_tw_recycle = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_mem = 786432 1048576 1572864
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 300
net.ipv4.ip_local_port_range = 1024 65000
vm.zone_reclaim_mode = 1
EOF
		sysctl -p "$sysctl_file" &>/dev/null
	fi

	local limits_file="/etc/security/limits.d/99-lnmp-utils.conf"
	if [ ! -d /etc/security/limits.d ]; then
		limits_file="/etc/security/limits.conf"
	fi
	if ! grep -q "^#patch by tinyphporg/lnmp-utils$" "$limits_file"; then
		cat >> "$limits_file" <<EOF
#patch by tinyphporg/lnmp-utils
*               soft     nproc         65536
*               hard     nproc         65536

*               soft     nofile         102400
*               hard     nofile         102400
EOF
		ulimit -n 102400
	fi

	user_add www www
	# Essential build tools (compile from source)
	pkg_install make autoconf automake gcc cmake pkg-config

	# Download, archive and patch utilities
	pkg_install wget curl unzip zip patch pigz

	if [ ! -f /etc/profile.d/lnmp-utils.sh ]; then
		cat > /etc/profile.d/lnmp-utils.sh <<'EOF'
PATH="/usr/local/bin:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/sbin:$HOME/bin"
export PATH
EOF
	fi
}