#!/bin/bash
# lnmp-utils deployment entrypoint
#
# Reads LNMP_COMPONENTS env var to selectively enable/start services.
# All components are pre-compiled in the image — no build happens at runtime.
#
# Presets: lnmp | full | minimal | nosql
# Custom:   php,mariadb,openresty,redis,memcached,mongodb,node,fastdfs
#
# Default (no LNMP_COMPONENTS set): lnmp

set -e

echo "=== lnmp-utils deployment ==="
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
    echo "[entrypoint] Preset '${COMPONENTS}' -> ${PRESETS[$COMPONENTS]}"
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

# ---- Service startup ----
echo "[entrypoint] Enabling services: ${COMPONENTS}"

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
echo "[entrypoint] Starting systemd..."
exec /sbin/init
