#!/bin/bash
set -e

echo "============================================"
echo "  lnmp-utils install test"
echo "  OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
echo "  Kernel: $(uname -r)"
echo "============================================"

# Run the install command passed as args
cd /opt/lnmp-utils
chmod +x install.sh

echo "[$(date '+%H:%M:%S')] Running: ./install.sh $*"
./install.sh "$@" 2>&1
exit_code=$?

echo ""
echo "[$(date '+%H:%M:%S')] Install exit code: $exit_code"

# Show verification if install succeeded
if [ $exit_code -eq 0 ]; then
    echo ""
    echo "=== Verification ==="
    echo "--- Installed packages ---"
    if command -v dnf &>/dev/null; then
        for pkg in nginx openresty php mysql mariadb redis memcached; do
            dnf list installed 2>/dev/null | grep -i "$pkg" || echo "  $pkg: not found via dnf"
        done
    elif command -v dpkg &>/dev/null; then
        for pkg in nginx openresty php mysql mariadb redis memcached; do
            dpkg -l 2>/dev/null | grep -i "$pkg" || echo "  $pkg: not found via dpkg"
        done
    fi
    echo "--- Service status ---"
    systemctl list-units --type=service 2>/dev/null | grep -iE 'nginx|openresty|php|mysql|mariadb|redis|memcached' || echo "  (no services found)"
fi

exit $exit_code
