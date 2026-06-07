# Supported OS version range (major version only, inclusive)
# Covers CentOS 8+, Rocky 8+, RHEL 8+, AlmaLinux 8+
OS_VERSION_MIN=8
OS_VERSION_MAX=10

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

	# CentOS Stream uses metalink (mirrors.centos.org/metalink) which returns
	# unreliable third-party mirrors — especially for aarch64 and new releases.
	# Timeouts and checksum mismatches are common. Replace with a static baseurl
	# pointing directly to the official mirror, bypassing the metalink redirect.
	if [ -f /etc/yum.repos.d/centos.repo ] && grep -q '^metalink=' /etc/yum.repos.d/centos.repo 2>/dev/null; then
		cat > /etc/yum.repos.d/centos.repo <<'REPOEOF'
[baseos]
name=CentOS Stream $releasever - BaseOS
baseurl=https://mirror.stream.centos.org/$releasever-stream/BaseOS/$basearch/os/
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-centosofficial-SHA256
gpgcheck=1
repo_gpgcheck=0
metadata_expire=6h
countme=1
enabled=1

[appstream]
name=CentOS Stream $releasever - AppStream
baseurl=https://mirror.stream.centos.org/$releasever-stream/AppStream/$basearch/os/
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-centosofficial-SHA256
gpgcheck=1
repo_gpgcheck=0
metadata_expire=6h
countme=1
enabled=1

[crb]
name=CentOS Stream $releasever - CRB
baseurl=https://mirror.stream.centos.org/$releasever-stream/CRB/$basearch/os/
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-centosofficial-SHA256
gpgcheck=1
repo_gpgcheck=0
metadata_expire=6h
countme=1
enabled=0
REPOEOF
	fi

	# Enable PowerTools (RHEL 8) / CRB (RHEL 9+) for build dependencies like pcre-devel.
	# Uses sed directly on repo files to avoid dependency on dnf-plugins-core
	# (which may itself live in the disabled repo — chicken-and-egg).
	for _repo in /etc/yum.repos.d/*.repo; do
		if [ -f "${_repo}" ] && grep -qiE 'powertools|crb|codeready' "${_repo}" 2>/dev/null; then
			sed -i 's/enabled=0/enabled=1/g' "${_repo}"
		fi
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
		if ! echo "${installed_packages}" | grep -q "^${pkg}"; then
			dnf -y -q install "${pkg}"
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

	pkg_install ncurses-devel gcc-c++ kernel-devel
}