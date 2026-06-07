# Supported OS version range (major version only, inclusive)
# Covers Debian 10+ and Ubuntu 20.04+
OS_VERSION_MIN=10
OS_VERSION_MAX=24

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
			apt-get install -y -qq "${pkg}"
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

	# Debian uses arch-specific headers (linux-headers-arm64/amd64),
	# Ubuntu uses the linux-headers-generic meta-package.
	if [ "${OS_ID}" = "ubuntu" ]; then
		pkg_install g++ linux-headers-generic libncurses-dev
	else
		pkg_install g++ "linux-headers-$(dpkg --print-architecture)" libncurses-dev
	fi
}
