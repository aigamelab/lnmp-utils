# Supported OS version range (major version only, inclusive)
# Covers CentOS 8+, Rocky 8+, RHEL 8+, AlmaLinux 8+
OS_VERSION_MIN=8
OS_VERSION_MAX=10

# Add aliyun mirror as primary dnf/yum source, keeping official source as fallback.
os_mirror_setup() {
    local mirror_url="https://mirrors.aliyun.com"

    # CentOS Stream / RHEL: comment out metalink, replace baseurl with aliyun + official
    # Works on the existing .repo files in place — no template overwrite.
    for f in /etc/yum.repos.d/*.repo; do
        [ -f "$f" ] || continue
        if grep -q '^metalink=' "$f" 2>/dev/null; then
            sed -i \
                -e 's|^metalink=|#metalink=|g' \
                -e "s|^#baseurl=https\?://mirror.stream.centos.org|baseurl=${mirror_url}/centos-stream https://mirror.stream.centos.org|g" \
                "$f"
        fi
    done

    # Rocky Linux: comment out mirrorlist, add aliyun as primary baseurl with official as fallback
    for f in /etc/yum.repos.d/*.repo; do
        [ -f "$f" ] || continue
        if grep -q '^mirrorlist=' "$f" 2>/dev/null; then
            sed -i 's|^mirrorlist=|#mirrorlist=|g' "$f"
            sed -i "s|^#baseurl=http://dl.rockylinux.org/\$contentdir/\(.*\)|baseurl=${mirror_url}/rockylinux/\\1 http://dl.rockylinux.org/\$contentdir/\\1|g" "$f"
        fi
    done
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
    systemctl restart sshd 2>/dev/null || true
}

# Verify the current system is supported for installation
# Exits the script if OS or version is out of range
os_install_check() {
	if [ "${OS_SCRIPT_NAME}" != "rhel" ]; then
		echo "Error: ${OS_ID} is not supported."
		exit 1
	fi
	if [ "${OS_VERSION_MAJOR}" -lt "${OS_VERSION_MIN}" ] || [ "${OS_VERSION_MAJOR}" -gt "${OS_VERSION_MAX}" ]; then
		echo "Error: ${OS_PLATFORM} is not supported. Supported versions: ${OS_VERSION_MIN} ~ ${OS_VERSION_MAX}"
		exit 1
	fi

	# Minimal images may lack dnf; try microdnf first, then yum as fallback
	if ! command -v dnf &>/dev/null; then
		if command -v microdnf &>/dev/null; then
			microdnf install -y dnf
		elif command -v yum &>/dev/null; then
			yum install -y dnf
		else
			echo "Error: no package manager found (dnf, microdnf, or yum required)"
			exit 1
		fi
	fi

	# Add aliyun mirror as primary, keep official source as fallback
	os_mirror_setup

	# Enable PowerTools (RHEL 8) / CRB (RHEL 9+) / devel (Rocky 10+)
	# for build dependencies. Uses sed directly on repo files to avoid
	# dependency on dnf-plugins-core (chicken-and-egg with disabled repos).
	# Section-aware: only toggles enabled=0 → enabled=1 within the matching
	# [section] block, not the entire file.
	for _repo in /etc/yum.repos.d/*.repo; do
		if [ ! -f "${_repo}" ]; then
			continue
		fi
		# Find section headers matching powertools/crb/codeready/devel and enable
		# only within that section (until the next section or EOF).
		grep -niE '^\[(powertools|crb|codeready|devel)\]' "${_repo}" 2>/dev/null | while IFS=: read -r _lineno _section; do
			# Extract just the section name for the range pattern
			_section_name="${_section#[}"
			_section_name="${_section_name%]}"
			# Use sed range: from matching line to next '[' line (or EOF), toggle enabled=0
			sed -i "${_lineno},/^\[/ { s/^enabled=0/enabled=1/g }" "${_repo}"
		done
	done

	# Refresh package metadata before any pkg_install calls
	dnf makecache -q

	# Ensure getopt is present (part of util-linux, may be missing in minimal images)
	if ! command -v getopt &>/dev/null; then
		dnf install -y util-linux
	fi
}

# Install packages if not already present (RHEL/CentOS/Rocky)
# Captures installed list once for efficiency when installing many packages
pkg_install() {
	local installed_packages
	installed_packages=$(dnf list installed)
	for pkg in "$@"; do
		if ! echo "${installed_packages}" | grep -q "^${pkg}\."; then
			echo -n "  Installing ${pkg}... "
			if dnf -y -q install "${pkg}" 2>/dev/null; then
				echo "OK"
			else
				echo "FAILED"
				echo "  [WARN] Package '${pkg}' not found in repos, continuing"
			fi
		fi
	done
}

# Remove packages if present (RHEL/CentOS/Rocky)
pkg_uninstall() {
	local installed_packages
	installed_packages=$(dnf list installed)
	for pkg in "$@"; do
		if echo "${installed_packages}" | grep -q "^${pkg}"; then
			dnf -y -q remove "${pkg}"
		fi
	done
}

os_install_init(){
	if [ "$INSTALL_IS_QUIET" = "1" ]; then
		return
	fi

	if [ -s /etc/selinux/config ]; then
		sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
	fi

	os_ssh_port_setup
}