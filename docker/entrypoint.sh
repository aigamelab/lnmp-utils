#!/bin/bash
# CI test entrypoint — runs install.sh from the mounted source
set -e

echo "============================================"
echo "  lnmp-utils install test"
echo "  OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
echo "  Kernel: $(uname -r)"
echo "  Build dir: ${BUILD_DIR:-none}"
echo "============================================"

# Run install command passed as args
cd /opt/lnmp-utils
chmod +x install.sh 2>/dev/null || true

echo "[$(date '+%H:%M:%S')] Running: ./install.sh $*"
./install.sh "$@" 2>&1
exit_code=$?

echo ""
echo "[$(date '+%H:%M:%S')] Install exit code: $exit_code"

if [ $exit_code -eq 0 ]; then
    echo ""
    echo "=== Verification ==="
    echo "Installed packages:"
    if command -v dnf &>/dev/null; then
        for pkg in nginx openresty php mysql mariadb redis memcached; do
            dnf list installed 2>/dev/null | grep -qi "$pkg" && echo "  [OK] $pkg" || echo "  [--] $pkg: not found"
        done
    elif command -v dpkg &>/dev/null; then
        for pkg in nginx openresty php mysql mariadb redis memcached; do
            dpkg -l 2>/dev/null | grep -qi "$pkg" && echo "  [OK] $pkg" || echo "  [--] $pkg: not found"
        done
    fi
    echo ""
    echo "Services:"
    systemctl list-units --type=service 2>/dev/null | grep -iE 'nginx|openresty|php|mysql|mariadb|redis|memcached' || echo "  (none)"
fi

exit $exit_code
