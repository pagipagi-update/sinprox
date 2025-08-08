#!/usr/bin/env bash
set -euo pipefail
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  echo "[ERR] Run as root: sudo bash add_user.sh <user> <pass>"; exit 1; fi

U="${1:-}"; P="${2:-}"
if [ -z "$U" ] || [ -z "$P" ]; then
  echo "Usage: $0 <username> <password>"
  exit 1
fi

if id -u "$U" >/dev/null 2>&1; then
  echo "[i] user exists, updating password…"
else
  useradd -M -s /usr/sbin/nologin "$U"
fi
echo "$U:$P" | chpasswd
systemctl reload danted || systemctl restart danted
echo "[OK] user $U ready."
