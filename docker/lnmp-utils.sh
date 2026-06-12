#!/bin/bash
# lnmp-utils Docker entrypoint
#
# Reads LNMP_COMPONENTS env var to selectively enable/start services.
# All components are pre-compiled in the image — no build happens at runtime.
#
# Presets: lnmp | full | minimal | nosql
# Custom:   php,mariadb,openresty,redis,memcached,mongodb,node,fastdfs
#
# Default (no LNMP_COMPONENTS set): lnmp

set -e

echo "=== lnmp-utils ==="
echo "OS: $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'"' -f2 || echo 'unknown')"

# ---- Preset resolution ----
declare -A PRESETS=(
    ["lnmp"]="openresty mariadb php"
    ["full"]="openresty mariadb php redis memcached mongodb node fastdfs"
    ["minimal"]="openresty php"
    ["nosql"]="redis memcached mongodb"
)

COMPONENTS="${LNMP_COMPONENTS:-lnmp}"
if [[ -n "${PRESETS[$COMPONENTS]:-}" ]]; then
    echo "[lnmp-utils] Preset '${COMPONENTS}' -> ${PRESETS[$COMPONENTS]}"
    COMPONENTS="${PRESETS[$COMPONENTS]}"
fi

# ---- Component -> systemd unit mapping ----
declare -A UNIT_MAP=(
    ["php"]="php-fpm"
    ["mariadb"]="mariadb"
    ["openresty"]="openresty"
    ["redis"]="redis"
    ["memcached"]="memcached"
    ["mongodb"]="mongod"
)

# ---- Seed default data on first run (volumes may shadow image contents) ----
DEFAULTS="/opt/lnmp-utils/data-defaults"
if [[ -d "${DEFAULTS}" ]]; then
    for _dir in conf log db web pkg cache script bak; do
        _target="/data/${_dir}"
        _source="${DEFAULTS}/${_dir}"
        if [[ -d "${_source}" ]]; then
            if [[ ! -d "${_target}" ]] || [[ -z "$(ls -A "${_target}" 2>/dev/null)" ]]; then
                echo "[lnmp-utils] Seeding default: /data/${_dir}"
                mkdir -p "${_target}"
                cp -a "${_source}/." "${_target}/"
            fi
        fi
    done
fi

# ---- Service startup ----
echo "[lnmp-utils] Enabling services: ${COMPONENTS}"

# Ensure /run directory exists (tmpfs may not be mounted yet)
mkdir -p /run /var/run

for comp in ${COMPONENTS}; do
    unit="${UNIT_MAP[$comp]:-$comp}"
    if [ -f "/etc/systemd/system/${unit}.service" ] || [ -f "/lib/systemd/system/${unit}.service" ]; then
        echo "  [enable] ${unit}"
        systemctl enable "${unit}" 2>/dev/null || true
    else
        echo "  [skip] ${unit} — no systemd unit found"
    fi
done

# ---- Launch systemd ----
echo "[lnmp-utils] Starting systemd..."
for _init in /sbin/init /lib/systemd/systemd; do
    if [[ -x "${_init}" ]]; then
        exec "${_init}"
    fi
done
echo "[lnmp-utils] ERROR: no systemd init found" >&2
exit 1
