#!/bin/bash
# ================================================================
# СКРИПТ АВТОНАСТРОЙКИ: ISP
# Демоэкзамен 09.02.06 | au-team.irpo
# Запуск: curl -fsSL https://raw.githubusercontent.com/20XMAS24/de-09-02-06-guide/main/scripts/isp.sh | bash
# ================================================================
set -e
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
info() { echo -e "${YELLOW}[>>]${NC} $1"; }

IFACES=($(ip -o link show | awk -F': ' '{print $2}' | grep -v lo | grep -v '@'))
ETH0=${IFACES[0]:-ens18}
ETH1=${IFACES[1]:-ens19}
ETH2=${IFACES[2]:-ens20}

echo "========================================"
echo "  НАСТРОЙКА ISP | 09.02.06"
echo "  IF0=$ETH0  IF1=$ETH1  IF2=$ETH2"
echo "========================================"

# Задание 1: Hostname
info "Задание 1: hostname"
hostnamectl set-hostname isp.au-team.irpo
grep -q "127.0.1.1.*isp" /etc/hosts || echo "127.0.1.1 isp.au-team.irpo isp" >> /etc/hosts
ok "hostname: $(hostname)"

# Задание 2: IP-адресация
info "Задание 2: IP-адресация"
# ETH0 — внешний (интернет), ETH1 — к HQ-RTR, ETH2 — к BR-RTR
nmcli con mod "$ETH0" ipv4.addresses 10.10.10.1/24 ipv4.method manual 2>/dev/null || \
  nmcli con add type ethernet con-name "$ETH0" ifname "$ETH0" \
    ipv4.addresses 10.10.10.1/24 ipv4.method manual
nmcli con up "$ETH0" 2>/dev/null || true

nmcli con mod "$ETH1" ipv4.addresses 172.16.1.1/28 ipv4.method manual 2>/dev/null || \
  nmcli con add type ethernet con-name "$ETH1" ifname "$ETH1" \
    ipv4.addresses 172.16.1.1/28 ipv4.method manual
nmcli con up "$ETH1" 2>/dev/null || true

nmcli con mod "$ETH2" ipv4.addresses 172.16.2.1/28 ipv4.method manual 2>/dev/null || \
  nmcli con add type ethernet con-name "$ETH2" ifname "$ETH2" \
    ipv4.addresses 172.16.2.1/28 ipv4.method manual
nmcli con up "$ETH2" 2>/dev/null || true
ok "IPs: $ETH0=10.10.10.1/24  $ETH1=172.16.1.1/28  $ETH2=172.16.2.1/28"

# Задание 8: NAT
info "Задание 8: NAT"
echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/99-forward.conf
sysctl -p /etc/sysctl.d/99-forward.conf
iptables -t nat -C POSTROUTING -o "$ETH0" -j MASQUERADE 2>/dev/null || \
  iptables -t nat -A POSTROUTING -o "$ETH0" -j MASQUERADE
aptables_save=/etc/sysconfig/iptables
iptables-save > "$aptables_save" 2>/dev/null || true
ok "NAT: MASQUERADE через $ETH0"

# Задание 11: Часовой пояс
timedatectl set-timezone Europe/Moscow && ok "Часовой пояс: Europe/Moscow"

# Модуль 2: NTP-сервер
info "Модуль 2: NTP-сервер chrony"
apt-get install -y chrony
cat > /etc/chrony.conf << 'EOF'
pool 2.altlinux.pool.ntp.org iburst
allow 172.16.1.0/28
allow 172.16.2.0/28
local stratum 4
driftfile /var/lib/chrony/drift
rtcsync
EOF
systemctl enable chronyd && systemctl restart chronyd
ok "NTP-сервер: chrony, разрешена сеть 172.16.x.x"

# Модуль 2: nginx reverse proxy + htpasswd
info "Модуль 2: nginx reverse proxy"
apt-get install -y nginx apache2-utils 2>/dev/null || \
  apt-get install -y nginx httpd-tools 2>/dev/null || true
if command -v nginx &>/dev/null; then
  mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled
  htpasswd -bc /etc/nginx/.htpasswd admin P@ssw0rd
  cat > /etc/nginx/sites-available/proxy.conf << 'NGINXEOF'
server {
    listen 80;
    server_name web.au-team.irpo mon.au-team.irpo docker.au-team.irpo;

    auth_basic "Restricted";
    auth_basic_user_file /etc/nginx/.htpasswd;

    location / {
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        if ($host = web.au-team.irpo)   { proxy_pass http://172.16.2.1:8080; }
        if ($host = mon.au-team.irpo)   { proxy_pass http://192.168.100.2; }
        if ($host = docker.au-team.irpo){ proxy_pass http://172.16.1.1:8080; }
    }
}
NGINXEOF
  ln -sf /etc/nginx/sites-available/proxy.conf /etc/nginx/sites-enabled/proxy.conf 2>/dev/null || true
  nginx -t && systemctl enable nginx && systemctl restart nginx
  ok "nginx proxy: web/mon/docker -> backend (admin:P@ssw0rd)"
fi

echo ""
echo "========================================"
echo "  ISP ГОТОВ"
echo "========================================"
echo "$ETH0=10.10.10.1/24 | $ETH1=172.16.1.1/28 | $ETH2=172.16.2.1/28"
echo "NAT, NTP-сервер, nginx reverse proxy"
