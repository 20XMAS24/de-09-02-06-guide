#!/bin/bash
# ================================================================
# СКРИПТ АВТОНАСТРОЙКИ: BR-RTR
# Демоэкзамен 09.02.06 | au-team.irpo
# Запуск: curl -fsSL https://raw.githubusercontent.com/20XMAS24/de-09-02-06-guide/main/scripts/br-rtr.sh | bash
# ================================================================
set -e
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
info() { echo -e "${YELLOW}[>>]${NC} $1"; }

IFACES=($(ip -o link show | awk -F': ' '{print $2}' | grep -v lo | grep -v '@'))
ETH0=${IFACES[0]:-ens18}
ETH1=${IFACES[1]:-ens19}

echo "========================================"
echo "  НАСТРОЙКА BR-RTR | 09.02.06"
echo "  WAN=$ETH0  LAN=$ETH1"
echo "========================================"

# Задание 1: Hostname
hostnamectl set-hostname br-rtr.au-team.irpo
grep -q "127.0.1.1.*br-rtr" /etc/hosts || echo "127.0.1.1 br-rtr.au-team.irpo br-rtr" >> /etc/hosts
ok "hostname: $(hostname)"

# Задание 2: IP
nmcli con mod "$ETH0" ipv4.addresses 172.16.2.2/28 ipv4.gateway 172.16.2.1 ipv4.method manual 2>/dev/null || \
  nmcli con add type ethernet con-name "$ETH0" ifname "$ETH0" \
    ipv4.addresses 172.16.2.2/28 ipv4.gateway 172.16.2.1 ipv4.method manual
nmcli con up "$ETH0" 2>/dev/null || true
nmcli con mod "$ETH1" ipv4.addresses 192.168.20.1/28 ipv4.method manual 2>/dev/null || \
  nmcli con add type ethernet con-name "$ETH1" ifname "$ETH1" \
    ipv4.addresses 192.168.20.1/28 ipv4.method manual
nmcli con up "$ETH1" 2>/dev/null || true
ok "WAN: 172.16.2.2/28 | LAN: 192.168.20.1/28"

# Задание 3: net_admin
id net_admin &>/dev/null || useradd -m -s /bin/bash net_admin
echo "net_admin:P@ssw0rd" | chpasswd
grep -q "^net_admin" /etc/sudoers || echo "net_admin ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
ok "net_admin создан"

# Задание 6: GRE
nmcli con show gre1 &>/dev/null || \
  nmcli con add type ip-tunnel con-name gre1 ifname gre1 mode gre \
    remote 172.16.1.2 local 172.16.2.2
nmcli con mod gre1 ipv4.addresses 10.0.0.2/30 ipv4.method manual
nmcli con up gre1 2>/dev/null || true
ok "GRE: 10.0.0.2/30"

# Задание 7: OSPF
apt-get install -y frr
sed -i 's/^ospfd=no/ospfd=yes/' /etc/frr/daemons
systemctl enable frr && systemctl restart frr
sleep 2
vtysh << 'VTYSH'
configure terminal
router ospf
 ospf router-id 2.2.2.2
 network 10.0.0.0/30 area 0
 redistribute connected
 passive-interface default
 no passive-interface gre1
interface gre1
 ip ospf authentication message-digest
 ip ospf message-digest-key 1 md5 P@ssw0rd
end
write memory
VTYSH
ok "OSPF: router-id 2.2.2.2"

# Задание 8: NAT
echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/99-forward.conf
sysctl -p /etc/sysctl.d/99-forward.conf
iptables -t nat -C POSTROUTING -o "$ETH0" -j MASQUERADE 2>/dev/null || \
  iptables -t nat -A POSTROUTING -o "$ETH0" -j MASQUERADE
iptables-save > /etc/sysconfig/iptables 2>/dev/null || true
ok "NAT настроен"

# Задание 11: Часовой пояс
timedatectl set-timezone Europe/Moscow && ok "Часовой пояс: Europe/Moscow"

# Модуль 2: NTP-клиент
apt-get install -y chrony
echo "server 172.16.1.1 iburst" > /etc/chrony.conf
systemctl enable chronyd && systemctl restart chronyd
ok "NTP-клиент: 172.16.1.1"

# Модуль 2: Port forwarding
iptables -t nat -C PREROUTING -i "$ETH0" -p tcp --dport 8080 -j DNAT --to-destination 192.168.20.2:8080 2>/dev/null || \
  iptables -t nat -A PREROUTING -i "$ETH0" -p tcp --dport 8080 -j DNAT --to-destination 192.168.20.2:8080
iptables -C FORWARD -d 192.168.20.2 -p tcp --dport 8080 -j ACCEPT 2>/dev/null || \
  iptables -A FORWARD -d 192.168.20.2 -p tcp --dport 8080 -j ACCEPT
iptables -t nat -C PREROUTING -i "$ETH0" -p tcp --dport 2026 -j DNAT --to-destination 192.168.20.2:2026 2>/dev/null || \
  iptables -t nat -A PREROUTING -i "$ETH0" -p tcp --dport 2026 -j DNAT --to-destination 192.168.20.2:2026
iptables -C FORWARD -d 192.168.20.2 -p tcp --dport 2026 -j ACCEPT 2>/dev/null || \
  iptables -A FORWARD -d 192.168.20.2 -p tcp --dport 2026 -j ACCEPT
iptables-save > /etc/sysconfig/iptables 2>/dev/null || true
ok "Port forwarding: 8080->BR-SRV, 2026->BR-SRV"

# Модуль 3: WireGuard
apt-get install -y wireguard wireguard-tools
mkdir -p /etc/wireguard && chmod 700 /etc/wireguard
if [ ! -f /etc/wireguard/br-private.key ]; then
  wg genkey | tee /etc/wireguard/br-private.key | wg pubkey > /etc/wireguard/br-public.key
  chmod 600 /etc/wireguard/br-private.key
fi
BR_PRIVATE=$(cat /etc/wireguard/br-private.key)
BR_PUBLIC=$(cat /etc/wireguard/br-public.key)
if [ ! -f /etc/wireguard/wg0.conf ]; then
  cat > /etc/wireguard/wg0.conf << WGEOF
[Interface]
PrivateKey = ${BR_PRIVATE}
Address = 10.10.0.2/30
ListenPort = 51820
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT

# Заполните после получения HQ_PUBLIC с HQ-RTR:
# [Peer]
# PublicKey = <HQ_PUBLIC>
# AllowedIPs = 192.168.100.0/27, 192.168.200.0/27, 10.10.0.1/32
# Endpoint = 172.16.1.2:51820
# PersistentKeepalive = 25
WGEOF
fi
systemctl enable wg-quick@wg0 2>/dev/null || true
ok "WireGuard готов | BR PUBLIC KEY: $BR_PUBLIC"
echo "  !! Вставьте на HQ-RTR в [Peer] -> PublicKey = $BR_PUBLIC"

# rsyslog клиент
apt-get install -y rsyslog
grep -q "192.168.100.2:514" /etc/rsyslog.conf || echo "*.warn   @@192.168.100.2:514" >> /etc/rsyslog.conf
systemctl enable rsyslog && systemctl restart rsyslog
ok "rsyslog клиент"

echo ""
echo "========================================"
echo "  BR-RTR ГОТОВ"
echo "========================================"
echo "WAN: 172.16.2.2/28 | LAN: 192.168.20.1/28 | GRE: 10.0.0.2/30"
echo "WireGuard pubkey: $BR_PUBLIC"
