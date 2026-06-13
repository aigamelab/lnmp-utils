# Supported OS version range (major version only, inclusive)
# Covers Debian 10+ and Ubuntu 20.04+
OS_VERSION_MIN=10
OS_VERSION_MAX=24

# Add aliyun mirror as primary apt source, keeping official source as fallback.
# Works with DEB822 .sources format (Debian 12+/Ubuntu 24.04+) and legacy .list format.
os_mirror_setup() {
    local mirror_url="https://mirrors.aliyun.com"
    local os_id
    os_id=$(. /etc/os-release && echo "${ID}")
    local src
    case "${os_id}" in
        debian) src="${mirror_url}/debian" ;;
        ubuntu) src="${mirror_url}/ubuntu" ;;
        *) return ;;
    esac

    # DEB822 format: prepend aliyun URL to the first URIs: line
    for f in /etc/apt/sources.list.d/*.sources; do
        [ -f "$f" ] && grep -q '^URIs:' "$f" && sed -i "s|^URIs:\s*|URIs: ${src} |" "$f"
    done

    # Legacy one-line format: add aliyun entry before the first deb line
    if [ -f /etc/apt/sources.list ]; then
        local codename
        codename=$(grep '^URIs:' /etc/apt/sources.list.d/*.sources 2>/dev/null | head -1 | grep -oP 'ubuntu-\K\w+' || true)
        if [ -z "$codename" ]; then
            codename=$(dpkg --status tzdata 2>/dev/null | grep -oP 'ubuntu\K[0-9]+\.[0-9]+' | head -1 || true)
        fi
        [ -z "$codename" ] && codename="$(. /etc/os-release && echo "${UBUNTU_CODENAME:-${VERSION_CODENAME}}")"
        if [ -n "$codename" ] && ! grep -q "^deb ${src}" /etc/apt/sources.list 2>/dev/null; then
            sed -i "0,/^deb /s||deb ${src}/ ${codename} main restricted universe multiverse\n&|" /etc/apt/sources.list
        fi
    fi
}

# Change SSH port to 10022
os_ssh_port_setup() {
    if grep -q '^Port 10022' /etc/ssh/sshd_config 2>/dev/null; then
        return
    fi
    sed -i 's/^#Port 22/Port 10022/' /etc/ssh/sshd_config 2>/dev/null || true
    if ! grep -q '^Port 10022' /etc/ssh/sshd_config 2>/dev/null; then
        echo 'Port 10022' >> /etc/ssh/sshd_config
    fi
    open_port 10022
    systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null || true
}

# Verify the current system is supported for installation
# Exits the script if OS or version is out of range
os_install_check() {
	if [ "${OS_SCRIPT_NAME}" != "debian" ]; then
		echo "Error: ${OS_ID} is not supported."
		exit 1
	fi
	if [ "${OS_VERSION_MAJOR}" -lt "${OS_VERSION_MIN}" ] || [ "${OS_VERSION_MAJOR}" -gt "${OS_VERSION_MAX}" ]; then
		echo "Error: ${OS_PLATFORM} is not supported. Supported versions: ${OS_VERSION_MIN} ~ ${OS_VERSION_MAX}"
		exit 1
	fi

	# Ensure apt-get is available (present even in minimal images)
	if ! command -v apt-get &>/dev/null; then
		echo "Error: apt-get is required but not found"
		exit 1
	fi

	# Add aliyun mirror as primary, keep official source as fallback
	os_mirror_setup

	# Refresh package index before any pkg_install calls
	apt-get update -qq

	# Ensure getopt is present (part of util-linux, may be missing in minimal images)
	if ! command -v getopt &>/dev/null; then
		apt-get install -y util-linux
	fi
}

# Install packages if not already present (Debian/Ubuntu)
pkg_install() {
	for pkg in "$@"; do
		if ! dpkg -s "${pkg}" &>/dev/null; then
			echo -n "  Installing ${pkg}... "
			if apt-get install -y -qq "${pkg}" 2>/dev/null; then
				echo "OK"
			else
				echo "FAILED"
				echo "  [WARN] Package '${pkg}' not found in repos, continuing"
			fi
		fi
	done
}

# Remove packages if present (Debian/Ubuntu)
pkg_uninstall() {
	for pkg in "$@"; do
		if dpkg -s "${pkg}" &>/dev/null; then
			apt-get remove -y -qq "${pkg}"
		fi
	done
}

os_install_init(){
	if [ "$INSTALL_IS_QUIET" = "1" ]; then
		return
	fi

	# AppArmor: no equivalent of SELinux disable needed
	# Debian/Ubuntu use AppArmor by default, which is less intrusive

	os_ssh_port_setup
}
