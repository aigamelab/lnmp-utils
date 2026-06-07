# Package configuration & downloading

# Fetch the remote package configuration file (cached after first call)
pkg_conf_get() {
	if [[ "${PKG_SOURCE_CONF}" == "" ]]; then
		if [[ "${INSTALL_IS_BUILD}" == "1" ]] && [[ -f "${GIT_DIR}/pkg.cnf" ]]; then
			PKG_SOURCE_CONF=$(tr "\n" " " < "${GIT_DIR}/pkg.cnf")
		else
			local http_status
			http_status=$(curl -s -o /dev/null -w "%{http_code}" "${SOURCE_URL}pkg.cnf")
			if [[ "${http_status}" != "200" ]]; then
				error "Curl connect timeout: ${SOURCE_URL}"
			fi
			PKG_SOURCE_CONF=$(curl -s "${SOURCE_URL}pkg.cnf" | tr "\n" " ")
		fi
	fi
	# Output one package entry per line
	echo "${PKG_SOURCE_CONF}" | tr " " "\n"
}

# Component installation

# Initialize/reset the component temp directory
com_tmp_init() {
	if [[ "${TMP_COMPONENT_DIR}" != "" ]]; then
		if [ -e "${TMP_COMPONENT_DIR}" ]; then
			rm -rf "${TMP_COMPONENT_DIR}"/*
		else
			create_dir "${TMP_COMPONENT_DIR}"
		fi
	fi
}

# Download and extract a component's source package
com_source_get() {
	local cname="$1"
	local cdir="$2"
	local com_name="linux-component-${cname}"
	local pkg_file="${PKG_COMPONENT_DIR}${com_name}.zip"
	local pkg_tmp_dir=""
	local pkg_url=""
	local pkg_cnf=""
	local fzip=""
	local pkg_list=""

	if [ -f "${pkg_file}" ]; then
		unzip "${pkg_file}" -d "${cdir}"
		return
	fi

	if [ "$(pkg_conf_get | grep -c "${com_name}")" -eq 0 ]; then
		return
	fi

	pkg_tmp_dir="${TMP_PKG_DIR}${com_name}/"
	if [ -n "${pkg_tmp_dir}" ] && [ -e "${pkg_tmp_dir}" ]; then
		rm -rf "${pkg_tmp_dir}"
	else
		mkdir -m 755 -p "${pkg_tmp_dir}"
	fi

	cd "${pkg_tmp_dir}" || return
	pkg_cnf="${GIT_DIR}/pkg/${com_name}.cnf"
	if [[ "${INSTALL_IS_BUILD}" == "1" ]] && [[ -f "${pkg_cnf}" ]]; then
		pkg_list=($(tr "\n" " " < "${pkg_cnf}"))
		for fname in "${pkg_list[@]}"; do
			fzip="${GIT_DIR}/pkg/${fname}"
			if [ -f "${fzip}" ]; then
				\cp -f "${fzip}" "${fname}"
			fi
		done
	else
		pkg_url="${SOURCE_URL}pkg/${com_name}.cnf"
		pkg_list=($(curl -s "${pkg_url}" | tr "\n" " "))
		echo "" > "${com_name}.cnf"
		for fname in "${pkg_list[@]}"; do
			furl="${SOURCE_URL}pkg/${fname}"
			echo "${furl}" >> "${com_name}.cnf"
		done
		wget -i "${com_name}.cnf"
	fi
	zip "${com_name}.zip" -s=0 --out "${pkg_file}"
	unzip "${pkg_file}" -d "${cdir}"
}

# Set up component state variables for a given component name
com_install_init() {
	if [ -z "$1" ]; then
		return
	fi

	COM_NAME="$1"
	COM_DIR="${SOURCE_COMPONENT_DIR}${COM_NAME}/"
	COM_3RD_DIR="${COM_DIR}3rd/"
	COM_SOURCE_FILE=""
	COM_CONF_DIR="${COM_DIR}conf/"
	COM_INSTALL_SCRIPT="${COM_DIR}install_${OS_PLATFORM}.sh"
	COM_INSTALL_DEFAULT_SCRIPT="${COM_DIR}install.sh"
	COM_INSTALL_DIR="${INSTALL_DIR}${COM_NAME}/"
	COM_DATA_CONF_DIR="${DATA_CONF_DIR}${COM_NAME}/"
	COM_DATA_DB_DIR="${DATA_DB_DIR}${COM_NAME}/"
	COM_DATA_SCRIPT_DIR="${DATA_SCRIPT_DIR}${COM_NAME}/"
	COM_DATA_LOG_DIR="${DATA_LOG_DIR}${COM_NAME}/"
	COM_DATA_CACHE_DIR="${DATA_CACHE_DIR}${COM_NAME}/"
}

# Clear all component state variables
com_install_clear() {
	COM_NAME=""
	COM_DIR=""
	COM_3RD_DIR=""
	COM_SOURCE_FILE=""
	COM_CONF_DIR=""
	COM_INSTALL_SCRIPT=""
	COM_INSTALL_DIR=""
	COM_DATA_CONF_DIR=""
	COM_DATA_DB_DIR=""
	COM_DATA_SCRIPT_DIR=""
	COM_DATA_LOG_DIR=""
	COM_DATA_CACHE_DIR=""
}

# Install one or more components (source + execute install script)
com_install() {
	if [ -z "${1}" ]; then
		return
	fi

	local com
	for com in $1; do
		com_install_init "${com}"
		if [ ! -d "${COM_DIR}" ]; then
			com_source_get "${COM_NAME}" "${SOURCE_COMPONENT_DIR}"
			if [ ! -d "${COM_DIR}" ]; then
				error "Component: ${com} failed to download!"
			fi
		fi

		if [ ! -f "${COM_INSTALL_SCRIPT}" ] && [ ! -f "${COM_INSTALL_DEFAULT_SCRIPT}" ]; then
			error "Failed to install component ${com}: no install script found!"
		fi

		echo "Component ${com} installation started."
		cd "${CURRENT_DIR}" || return
		if [ -f "${COM_INSTALL_SCRIPT}" ]; then
			echo "${COM_INSTALL_SCRIPT}"
			source "${COM_INSTALL_SCRIPT}"
		elif [ -f "${COM_INSTALL_DEFAULT_SCRIPT}" ]; then
			echo "${COM_INSTALL_DEFAULT_SCRIPT}"
			source "${COM_INSTALL_DEFAULT_SCRIPT}"
		fi
		sleep 2
		echo "Component ${com} installation stopped."
		com_install_clear
	done
}

# Extract component archive helpers (called by component install scripts)
com_untar()   { tar zxvf "$1" -C "${TMP_COMPONENT_DIR}" >/dev/null; }
com_untarxz() { tar xvf  "$1" -C "${TMP_COMPONENT_DIR}" >/dev/null; }
com_unzip()   { unzip -u "$1" -d "${TMP_COMPONENT_DIR}" >/dev/null; }
com_unbz2()   { tar jxvf "$1" -C "${TMP_COMPONENT_DIR}" >/dev/null; }

# Initialize a component source file and confirm overwrite if already installed
com_init() {
	local is_cover=""
	COM_SOURCE_FILE="${COM_3RD_DIR}${1}"

	if [ ! -f "${COM_SOURCE_FILE}" ]; then
		error "Component ${COM_NAME}: source file ${COM_SOURCE_FILE} does not exist!"
	fi

	if [ -d "${COM_INSTALL_DIR}" ]; then
		echo -n "Component ${COM_NAME} is already installed. Overwrite? (y/n): "
		read -r is_cover
		if [ "${is_cover}" != "y" ] && [ "${is_cover}" != "Y" ]; then
			error "Component ${COM_NAME}: installation cancelled."
		fi
	fi
}

# Verify required package files exist for the current component
com_pkg_check() {
	for pkg in "$@"; do
		if [ ! -f "${pkg}" ]; then
			error "Component ${COM_NAME}: package ${pkg} does not exist!"
		fi
	done
}

# Replace a placeholder in a file (sed-based, escapes forward slashes in replacement)
com_file_replace() {
	local s="$1"
	local t="$2"
	local path="$3"
	# Escape / as \/ for sed: /usr/local/mysql → \/usr\/local\/mysql
	t="${t//\//\\\/}"
	sed -i "s/${s}/${t}/g" "${path}"
}

# Replace placeholders in one or more config files (runs com_file_replace for each)
com_replace() {
	for path in "$@"; do
		if [ ! -f "${path}" ]; then
			error "Component ${COM_NAME}: config file ${path} does not exist!"
		fi
		com_file_replace '{COM_DATA_CONF_DIR}'  "${COM_DATA_CONF_DIR}"  "${path}"
		com_file_replace '{COM_DATA_DB_DIR}'     "${COM_DATA_DB_DIR}"     "${path}"
		com_file_replace '{COM_INSTALL_DIR}'     "${COM_INSTALL_DIR}"     "${path}"
		com_file_replace '{COM_DATA_CACHE_DIR}'  "${COM_DATA_CACHE_DIR}"  "${path}"
		com_file_replace '{COM_DATA_SCRIPT_DIR}' "${COM_DATA_SCRIPT_DIR}" "${path}"
		com_file_replace '{COM_DATA_LOG_DIR}'    "${COM_DATA_LOG_DIR}"    "${path}"
		com_file_replace '{CPU_NUM}'             "${CPU_NUM}"             "${path}"
	done
}

# Verify component installation succeeded (check paths exist)
com_install_test() {
	if [ ! -e "${COM_INSTALL_DIR}" ]; then
		error "Component ${COM_NAME}: install dir ${COM_INSTALL_DIR} does not exist!"
	fi

	for path in "$@"; do
		if [ ! -e "${path}" ]; then
			error "Component ${COM_NAME}: path ${path} does not exist!"
		fi
	done
}

# Install dependencies on-demand (called from component install scripts)
require() {
	local com_current_name="${COM_NAME}"
	com_install "$*"
	if [ -n "${com_current_name}" ]; then
		com_install_init "${com_current_name}"
	fi
}

# Module installation

# Initialize/reset the module temp directory
mod_tmp_init() {
	if [[ "${TMP_MODULE_DIR}" != "" ]]; then
		if [ -e "${TMP_MODULE_DIR}" ]; then
			rm -rf "${TMP_MODULE_DIR}"/*
		else
			create_dir "${TMP_MODULE_DIR}"
		fi
	fi
}

# Download and extract a module's source package
mod_source_get() {
	local mname="$1"
	local mdir="$2"
	local mod_name="linux-module-${mname}"
	local pkg_file="${PKG_COMPONENT_DIR}${mod_name}.zip"
	local pkg_tmp_dir=""
	local pkg_url=""
	local pkg_list=""

	if [ -f "${pkg_file}" ]; then
		unzip "${pkg_file}" -d "${mdir}"
		return
	fi

	if [ "$(pkg_conf_get | grep -c "${mod_name}")" -eq 0 ]; then
		return
	fi

	pkg_tmp_dir="${TMP_PKG_DIR}${mod_name}/"
	if [ -n "${pkg_tmp_dir}" ] && [ -e "${pkg_tmp_dir}" ]; then
		rm -rf "${pkg_tmp_dir}"
	else
		mkdir -m 755 -p "${pkg_tmp_dir}"
	fi

	cd "${pkg_tmp_dir}" || return
	pkg_url="${SOURCE_URL}pkg/${mod_name}.cnf"
	pkg_list=($(curl -s "${pkg_url}" | tr "\n" " "))

	echo "" > "${mod_name}.cnf"
	for fname in "${pkg_list[@]}"; do
		furl="${SOURCE_URL}pkg/${fname}"
		echo "${furl}" >> "${mod_name}.cnf"
	done

	wget -i "${mod_name}.cnf"
	zip "${mod_name}.zip" -s=0 --out "${pkg_file}"
	unzip "${pkg_file}" -d "${mdir}"
}

# Set up module state variables for a given module name
mod_install_init() {
	if [ -z "$1" ]; then
		return
	fi
	MOD_DIR="${SOURCE_MODULE_DIR}${1}/"
	MOD_NAME="$1"
	MOD_PACKAGE_DIR="${MOD_DIR}package/"
	MOD_CONF_DIR="${MOD_DIR}conf/"
	MOD_INSTALL_SCRIPT="${SOURCE_MODULE_DIR}${MOD_NAME}/install.sh"
}

# Clear all module state variables
mod_install_clear() {
	MOD_DIR=""
	MOD_NAME=""
	MOD_PACKAGE_DIR=""
	MOD_CONF_DIR=""
	MOD_INSTALL_SCRIPT=""
}

# Install one or more modules (source + execute install script)
mod_install() {
	if [ -z "${1}" ]; then
		return
	fi

	local mod
	for mod in $1; do
		mod_install_init "${mod}"
		if [ ! -d "${MOD_DIR}" ]; then
			mod_source_get "${MOD_NAME}" "${SOURCE_MODULE_DIR}"
			if [ ! -d "${MOD_DIR}" ]; then
				error "Module: ${mod} failed to download!"
			fi
		fi

		if [ ! -f "${MOD_INSTALL_SCRIPT}" ]; then
			error "Failed to install module ${mod}: ${MOD_INSTALL_SCRIPT} does not exist!"
		fi

		echo "Module ${mod} installation started."
		cd "${CURRENT_DIR}" || return
		source "${MOD_INSTALL_SCRIPT}"
		echo "Module ${mod} installed successfully!"
		sleep 2
		mod_install_clear
	done
}

# Extract module archive helpers (called by module install scripts)
mod_untar() { tar zxvf "$1" -C "${TMP_MODULE_DIR}" >/dev/null; }
mod_unzip() { unzip -f "$1" -d "${TMP_MODULE_DIR}" >/dev/null; }
mod_unbz2() { tar jxvf "$1" -C "${TMP_MODULE_DIR}" >/dev/null; }

# Utilities

# Public API: check if an option was passed via -o
hasoption() {
	in_array "${1}" "${INSTALL_OPTIONS[@]}"
}

# Clean up the temporary working directory
clear_tmp_dir() {
	if [ -n "${TMP_DIR}" ] && [ -d "${TMP_DIR}" ]; then
		rm -rf "${TMP_DIR}"
	fi
}
