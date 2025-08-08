#!/usr/bin/env bash
set -euo pipefail

# === CONFIG DEFAULT ===
PORT="${PORT:-3128}"
USER_DEFAULT="${USER_DEFAULT:-adminkd}"
PASS_DEFAULT="${PASS_DEFAULT:-@Jkliop890}"
ALLOW_IPS="${ALLOW_IPS:-0.0.0.0/0}" # semua IP boleh default

echo "=== HTTP/HTTPS Proxy Installer (Squid) ==="
echo "Port        : $PORT"
echo "User/Pass   : $USER_DEFAULT / $PASS_DEFAULT"
echo "Allow IPs   : $ALLOW_IPS"

# --- must run as root
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "[ERR] Please run as root (sudo bash install.sh)"
    exit 1
fi

# --- wait for apt lock
for i in {1..30}; do
    if fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
       fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || \
       fuser /var/cache/apt/archives/lock >/dev/null 2>&1; then
        echo "[i] apt busy, waiting... ($((i*2))s)"
        sleep 2
    else
        break
    fi
done

# --- install squid + apache-utils
export DEBIAN_FRONTEND=noninteractive
apt update -y
apt install -y squid apache2-utils curl ufw

# --- setup user auth
htpasswd -b -c /etc/squid/passwd "$USER_DEFAULT" "$PASS_DEFAULT"

# --- convert ALLOW_IPS to squid ACL format
ACL_RULES=""
IFS=',' read -ra CIDRS <<< "$ALLOW_IPS"
for ip in "${CIDRS[@]}"; do
    ACL_RULES+="acl allowed_ips src ${ip}"$'\n'
done

# --- backup config
mv /etc/squid/squid.conf /etc/squid/squid.conf.bak

# --- write new squid config
cat >/etc/squid/squid.conf <<EOF
# Squid HTTP/HTTPS Proxy Config
http_port ${PORT}

auth_param basic program /usr/lib/squid/basic_ncsa_auth /etc/squid/passwd
auth_param basic realm ProxyAuth
acl authenticated proxy_auth REQUIRED

${ACL_RULES}
http_access allow authenticated allowed_ips
http_access deny all

# Optional performance tweaks
cache_mem 64 MB
maximum_object_size_in_memory 8 MB
maximum_object_size 128 MB
cache_dir ufs /var/spool/squid 512 16 256
access_log /var/log/squid/access.log
EOF

# --- firewall
ufw allow ${PORT}/tcp || true

# --- enable & restart squid
systemctl enable squid
systemctl restart squid

# --- output info
IPVPS=$(curl -s https://api.ipify.org || hostname -I | awk '{print $1}')
echo
echo "=== DONE ==="
echo "HTTP/HTTPS Proxy siap!"
echo "Proxy : http://$USER_DEFAULT:$PASS_DEFAULT@$IPVPS:$PORT"
echo
echo "Test cepat:"
echo "  curl -U $USER_DEFAULT:$PASS_DEFAULT -x http://$IPVPS:$PORT https://api.ipify.org && echo"
