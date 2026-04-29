#!/bin/bash
# ================================================================
# СКРИПТ АВТОНАСТРОЙКИ: HQ-RTR
# Демоэкзамен 09.02.06 | au-team.irpo
# Запуск: curl -fsSL https://raw.githubusercontent.com/20XMAS24/de-09-02-06-guide/main/scripts/hq-rtr.sh | bash
# ================================================================
set -e
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
info() { echo -e "${YELLOW}[>>]${NC} $1"; }

IFACES=($(ip -o link show | awk -F': ' '{print $2}' | grep -v lo | grep -v '@'))
ETH0=${IFACES[0]:-ens18}
ETH1=${IFACES[1]:-ens19}

echo "========================================"
echo "  НАСТРОЙКА HQ-RTR | 09.02.06"
echo "  WAN=$ETH0  LAN=$ETH1"
echo "========================================"

# Задание 1: Hostname
info "Задание 1: hostname"
hostnamectl set-hostname hq-rtr.au-team.irpo
grep -q "127.0.1.1.*hq-rtr" /etc/hosts || echo "127.0.1.1 hq-rtr.au-team.irpo hq-rtr" >> /etc/hosts
ok "hostname: $(hostname)"

# Задание 2: IP WAN
info "Задание 2: IP WAN"
nmcli con mod "$ETH0" ipv4.addresses 172.16.1.2/28 ipv4.gateway 172.16.1.1 ipv4.method manual 2>/dev/null || \
  nmcli con add type ethernet con-name "$ETH0" ifname "$ETH0" \
    ipv4.addresses 172.16.1.2/28 ipv4.gateway 172.16.1.1 ipv4.method manual
nmcli con up "$ETH0" 2>/dev/null || true
ok "WAN: 172.16.1.2/28"

# Задание 3: net_admin
info "Задание 3: net_admin (uid=1000)"
id net_admin &>/dev/null || useradd -m -s /bin/bash net_admin
echo "net_admin:P@ssw0rd" | chpasswd
grep -q "^net_admin" /etc/sudoers || echo "net_admin ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
ok "net_admin создан"

# Задание 4: VLAN 100 (HQ-SRV), 200 (HQ-CLI), 999 (Management)
info "Задание 4: VLAN 100/200/999 на $ETH1"
nmcli con add type vlan con-name vlan100 dev "$ETH1" id 100 \
  ipv4.addresses 192.168.100.1/27 ipv4.method manual 2>/dev/null || true
nmcli con mod vlan100 ipv4.addresses 192.168.100.1/27 ipv4.method manual 2>/dev/null || true
nmcli con up vlan100 2>/dev/null || true

nmcli con add type vlan con-name vlan200 dev "$ETH1" id 200 \
  ipv4.addresses 192.168.200.1/27 ipv4.method manual 2>/dev/null || true
nmcli con mod vlan200 ipv4.addresses 192.168.200.1/27 ipv4.method manual 2>/dev/null || true
nmcli con up vlan200 2>/dev/null || true

nmcli con add type vlan con-name vlan999 dev "$ETH1" id 999 \
  ipv4.addresses 192.168.99.1/27 ipv4.method manual 2>/dev/null || true
nmcli con mod vlan999 ipv4.addresses 192.168.99.1/27 ipv4.method manual 2>/dev/null || true
nmcli con up vlan999 2>/dev/null || true
ok "VLAN100=192.168.100.1/27 | VLAN200=192.168.200.1/27 | VLAN999=192.168.99.1/27"

# Задание 5: DHCP для VLAN200
info "Задание 5: DHCP (VLAN200)"
apt-get install -y dhcp-server 2>/dev/null || apt-get install -y isc-dhcp-server 2>/dev/null || true
DHCP_CONF=/etc/dhcp/dhcpd.conf
[ -f /etc/dhcpd.conf ] && DHCP_CONF=/etc/dhcpd.conf
cat > "$DHCP_CONF" << 'EOF'
default-lease-time 600;
max-lease-time 7200;
authoritative;

subnet 192.168.200.0 netmask 255.255.255.224 {
    range 192.168.200.10 192.168.200.30;
    option routers 192.168.200.1;
    option domain-name-servers 192.168.100.2;
    option domain-name "au-team.irpo";
}
EOF
systemctl enable dhcpd 2>/dev/null || systemctl enable isc-dhcp-server 2>/dev/null || true
systemctl restart dhcpd 2>/dev/null || systemctl restart isc-dhcp-server 2>/dev/null || true
ok "DHCP: 192.168.200.10-30 для VLAN200"

# Задание 6: GRE tunnel
info "Задание 6: GRE -> BR-RTR"
nmcli con show gre1 &>/dev/null || \
  nmcli con add type ip-tunnel con-name gre1 ifname gre1 mode gre \
    remote 172.16.2.2 local 172.16.1.2
nmcli con mod gre1 ipv4.addresses 10.0.0.1/30 ipv4.method manual
nmcli con up gre1 2>/dev/null || true
ok "GRE: 10.0.0.1/30"

# Задание 7: OSPF через frr
info "Задание 7: OSPF"
apt-get install -y frr
sed -i 's/^ospfd=no/ospfd=yes/' /etc/frr/daemons
systemctl enable frr && systemctl restart frr
sleep 2
vtysh << 'VTYSH'
configure terminal
router ospf
 ospf router-id 1.1.1.1
 network 10.0.0.0/30 area 0
 network 192.168.100.0/27 area 0
 network 192.168.200.0/27 area 0
 redistribute connected
 passive-interface default
 no passive-interface gre1
interface gre1
 ip ospf authentication message-digest
 ip ospf message-digest-key 1 md5 P@ssw0rd
end
write memory
VTYSH
ok "OSPF: router-id 1.1.1.1, area 0"

# Задание 8: NAT
info "Задание 8: NAT"
echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/99-forward.conf
sysctl -p /etc/sysctl.d/99-forward.conf
for IFACE in "$ETH0"; do
  iptables -t nat -C POSTROUTING -o "$IFACE" -j MASQUERADE 2>/dev/null || \
    iptables -t nat -A POSTROUTING -o "$IFACE" -j MASQUERADE
done
iptables-save > /etc/sysconfig/iptables 2>/dev/null || true
ok "NAT настроен"

# Задание 11: Часовой пояс
timedatectl set-timezone Europe/Moscow && ok "Часовой пояс: Europe/Moscow"

# Модуль 2, Задание 4: NTP-клиент
apt-get install -y chrony
echo "server 172.16.1.1 iburst" > /etc/chrony.conf
systemctl enable chronyd && systemctl restart chronyd
ok "NTP-клиент: 172.16.1.1 (ISP)"

# Модуль 2, Задание 8: Port forwarding 8080 -> HQ-SRV
info "Модуль 2, Задание 8: port forwarding"
iptables -t nat -C PREROUTING -i "$ETH0" -p tcp --dport 8080 -j DNAT --to-destination 192.168.100.2:8080 2>/dev/null || \
  iptables -t nat -A PREROUTING -i "$ETH0" -p tcp --dport 8080 -j DNAT --to-destination 192.168.100.2:8080
iptables -C FORWARD -d 192.168.100.2 -p tcp --dport 8080 -j ACCEPT 2>/dev/null || \
  iptables -A FORWARD -d 192.168.100.2 -p tcp --dport 8080 -j ACCEPT
iptables -t nat -C PREROUTING -i "$ETH0" -p tcp --dport 2026 -j DNAT --to-destination 192.168.100.2:2026 2>/dev/null || \
  iptables -t nat -A PREROUTING -i "$ETH0" -p tcp --dport 2026 -j DNAT --to-destination 192.168.100.2:2026
iptables -C FORWARD -d 192.168.100.2 -p tcp --dport 2026 -j ACCEPT 2>/dev/null || \
  iptables -A FORWARD -d 192.168.100.2 -p tcp --dport 2026 -j ACCEPT
iptables-save > /etc/sysconfig/iptables 2>/dev/null || true
ok "Port forwarding: 8080->HQ-SRV:8080, 2026->HQ-SRV:2026"

# Модуль 3, Задание 1: WireGuard
info "Модуль 3, Задание 1: WireGuard"
apt-get install -y wireguard wireguard-tools
mkdir -p /etc/wireguard && chmod 700 /etc/wireguard
if [ ! -f /etc/wireguard/hq-private.key ]; then
  wg genkey | tee /etc/wireguard/hq-private.key | wg pubkey > /etc/wireguard/hq-public.key
  chmod 600 /etc/wireguard/hq-private.key
fi
HQ_PRIVATE=$(cat /etc/wireguard/hq-private.key)
HQ_PUBLIC=$(cat /etc/wireguard/hq-public.key)
if [ ! -f /etc/wireguard/wg0.conf ]; then
  cat > /etc/wireguard/wg0.conf << WGEOF
[Interface]
PrivateKey = ${HQ_PRIVATE}
Address = 10.10.0.1/30
ListenPort = 51820
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT

# Заполните после получения BR_PUBLIC с BR-RTR:
# [Peer]
# PublicKey = <BR_PUBLIC>
# AllowedIPs = 192.168.20.0/28, 10.10.0.2/32
# Endpoint = 172.16.2.2:51820
# PersistentKeepalive = 25
WGEOF
fi
systemctl enable wg-quick@wg0 2>/dev/null || true
ok "WireGuard готов"
echo "  !! HQ PUBLIC KEY: $HQ_PUBLIC"
echo "  !! Вставьте его на BR-RTR в секцию [Peer] -> PublicKey"

# Модуль 3, Задание 2: firewall
info "Модуль 3, Задание 2: firewall DROP"
iptables -P FORWARD DROP
iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -i vlan100 -j ACCEPT
iptables -A FORWARD -i vlan200 -j ACCEPT
iptables -A FORWARD -i gre1   -j ACCEPT
iptables -A FORWARD -i wg0    -j ACCEPT
iptables-save > /etc/sysconfig/iptables 2>/dev/null || true
ok "Firewall: FORWARD DROP (разрешены VLAN100/200/GRE/WG)"

# rsyslog клиент
apt-get install -y rsyslog
grep -q "192.168.100.2:514" /etc/rsyslog.conf || echo "*.warn   @@192.168.100.2:514" >> /etc/rsyslog.conf
systemctl enable rsyslog && systemctl restart rsyslog
ok "rsyslog клиент -> HQ-SRV:514"

echo ""
echo "========================================"
echo "  HQ-RTR ГОТОВ"
echo "========================================"
echo "WAN: 172.16.1.2/28 | VLAN100: 192.168.100.1/27 | VLAN200: 192.168.200.1/27"
echo "GRE: 10.0.0.1/30 | WireGuard pubkey: $HQ_PUBLIC"
echo "DHCP: 192.168.200.10-30 | OSPF: router-id 1.1.1.1"
