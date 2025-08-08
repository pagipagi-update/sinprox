#!/usr/bin/env bash
set -euo pipefail

# === CONFIG DEFAULT ===
PORT="${PORT:-1080}"
USER_DEFAULT="${USER_DEFAULT:-adminkd}"
PASS_DEFAULT="${PASS_DEFAULT:-@Jkliop890}"
ALLOW_IPS="${ALLOW_IPS:-0.0.0.0/0}"  # 0.0.0.0/0 = semua IP boleh

echo "=== SOCKS5 Proxy Installer (Dante) ==="
echo "Port        : $PORT"
echo "User/Pass   : $USER_DEFAULT / $PASS_DEFAULT"
echo "Allow IPs   : $ALLOW_IPS"

# Detect interface VPS
IFACE="$(ip -o route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
IFACE="${IFACE:-eth0}"
echo "Interface   : $IFACE"

# 1) Update & install Dante
apt update -y
DEBIAN_FRONTEND=noninteractive apt install -y dante-server ufw

# 2) Buat user system untuk auth
if id -u "$USER_DEFAULT" >/dev/null 2>&1; then
  echo "[i] User $USER_DEFAULT sudah ada, update password…"
else
  useradd -M -s /usr/sbin/nologin "$USER_DEFAULT"
fi
echo "$USER_DEFAULT:$PASS_DEFAULT" | chpasswd

# 3) Generate config danted
ALLOW_BLOCKS=""
IFS=',' read -ra CIDRS <<< "$ALLOW_IPS"
for C in "${CIDRS[@]}"; do
  ALLOW_BLOCKS+="client pass { from: $(echo "$C" | xargs) to: 0.0.0.0/0 log: connect disconnect error }\n"
done

cat >/etc/danted.conf <<EOF
logoutput: /var/log/danted.log
internal: 0.0.0.0 port = ${PORT}
external: ${IFACE}

clientmethod: none
socksmethod: username

user.notprivileged: nobody

${ALLOW_BLOCKS}

socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    protocol: tcp udp
    command: bind connect udpassociate
    log: connect disconnect error
}

client block { from: 0.0.0.0/0 to: 0.0.0.0/0 }
socks block { from: 0.0.0.0/0 to: 0.0.0.0/0 }
EOF

# 4) Open firewall port
ufw allow ${PORT}/tcp || true
ufw allow ${PORT}/udp || true

# 5) Enable & restart service
systemctl enable danted
systemctl restart danted

# 6) Output info
IPVPS=$(curl -s https://api.ipify.org || hostname -I | awk '{print $1}')
echo
echo "=== DONE ==="
echo "SOCKS5 VPS Proxy siap!"
echo "Host : $IPVPS"
echo "Port : $PORT"
echo "User : $USER_DEFAULT"
echo "Pass : $PASS_DEFAULT"
echo
echo "Cek dari lokal:"
echo "  curl -U ${USER_DEFAULT}:${PASS_DEFAULT} --socks5-hostname ${IPVPS}:${PORT} https://api.ipify.org"
