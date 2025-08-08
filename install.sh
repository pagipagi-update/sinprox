#!/usr/bin/env bash
set -euo pipefail

# =========================
#   Dante SOCKS5 Installer
#   by sinprox
# =========================

# --- must run as root
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  echo "[ERR] Please run as root. Example:"
  echo "sudo bash install.sh"
  exit 1
fi

# --- defaults (can be overridden by ENV)
PORT="${PORT:-1080}"
USER_DEFAULT="${USER_DEFAULT:-adminkd}"
PASS_DEFAULT="${PASS_DEFAULT:-@Jkliop890}"
ALLOW_IPS="${ALLOW_IPS:-0.0.0.0/0}"   # comma-separated CIDRs. 0.0.0.0/0 = open
LOGFILE="/var/log/danted.log"

echo "=== SOCKS5 Proxy Installer (Dante) ==="
echo "Port        : $PORT"
echo "User/Pass   : $USER_DEFAULT / $PASS_DEFAULT"
echo "Allow IPs   : $ALLOW_IPS"

# --- wait for apt locks (max ~60s)
for i in {1..30}; do
  if fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
     fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || \
     fuser /var/cache/apt/archives/lock >/dev/null 2>&1; then
    echo "[i] apt is busy, waiting... ($((i*2))s)"
    sleep 2
  else
    break
  fi
done

# --- install deps
export DEBIAN_FRONTEND=noninteractive
apt update -y
apt install -y dante-server ufw curl

# --- detect interface for 'external'
IFACE="$(ip -o route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
IFACE="${IFACE:-eth0}"
echo "Interface   : $IFACE"

# --- create auth user (no shell, no home)
if id -u "$USER_DEFAULT" >/dev/null 2>&1; then
  echo "[i] User $USER_DEFAULT already exists, updating password…"
else
  useradd -M -s /usr/sbin/nologin "$USER_DEFAULT"
fi
echo "$USER_DEFAULT:$PASS_DEFAULT" | chpasswd

# --- build danted.conf
ALLOW_BLOCKS=""
IFS=',' read -ra CIDRS <<< "$ALLOW_IPS"
for C in "${CIDRS[@]}"; do
  C_TRIM="$(echo "$C" | xargs)"
  ALLOW_BLOCKS+="client pass { from: $C_TRIM to: 0.0.0.0/0 log: connect disconnect error }"$'\n'
done

cat > /etc/danted.conf <<EOF
logoutput: ${LOGFILE}
internal: 0.0.0.0 port = ${PORT}
external: ${IFACE}

# clients may reach daemon w/o auth…
clientmethod: none
# …but SOCKS must authenticate
socksmethod: username

user.notprivileged: nobody

# who may connect to the daemon
${ALLOW_BLOCKS}

# what traffic is allowed
socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    protocol: tcp udp
    command: bind connect udpassociate
    log: connect disconnect error
}

# sane default drops
client block { from: 0.0.0.0/0 to: 0.0.0.0/0 }
socks block  { from: 0.0.0.0/0 to: 0.0.0.0/0 }
EOF

# --- firewall
ufw allow ${PORT}/tcp || true
ufw allow ${PORT}/udp || true

# --- light kernel tuning (optional but handy)
cat > /etc/sysctl.d/99-socks5-tune.conf <<'EOF'
net.core.somaxconn=4096
net.ipv4.ip_local_port_range=10240 65535
net.ipv4.tcp_fin_timeout=15
EOF
sysctl --system >/dev/null 2>&1 || true

# --- enable + restart
systemctl enable danted
systemctl restart danted

# --- verify
sleep 1
if ! systemctl is-active --quiet danted; then
  echo "[ERR] danted failed to start. Check: journalctl -u danted -n 100 --no-pager"
  exit 2
fi

IPVPS="$(curl -s https://api.ipify.org || hostname -I | awk '{print $1}')"

echo
echo "=== DONE ==="
echo "SOCKS5 VPS Proxy siap!"
echo "Proxy : socks5://$USER_DEFAULT:$PASS_DEFAULT@$IPVPS:$PORT"
echo
echo "Cek cepat (DNS via proxy):"
ENC_PASS="\$(python3 - <<'PY' 2>/dev/null || echo $PASS_DEFAULT
import urllib.parse,os
print(urllib.parse.quote(os.environ.get('PASS','${PASS_DEFAULT}'), safe=''))
PY
)"
echo "  curl -U ${USER_DEFAULT}:\$ENC_PASS --socks5-hostname ${IPVPS}:${PORT} https://api.ipify.org && echo"
echo
echo "Log    : tail -f ${LOGFILE}"
echo "Service: systemctl status danted"
