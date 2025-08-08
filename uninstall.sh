#!/usr/bin/env bash
set -euo pipefail

if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  echo "[ERR] Run as root: sudo bash uninstall.sh"; exit 1; fi

PORT="${PORT:-1080}"

systemctl stop danted || true
systemctl disable danted || true

ufw delete allow ${PORT}/tcp || true
ufw delete allow ${PORT}/udp || true

rm -f /etc/danted.conf /var/log/danted.log /etc/sysctl.d/99-socks5-tune.conf
sysctl --system >/dev/null 2>&1 || true

apt purge -y dante-server || true
apt autoremove -y || true

echo "[OK] Dante removed."
