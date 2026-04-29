#!/bin/bash
# ================================================================
# СКРИПТ АВТОНАСТРОЙКИ: HQ-SRV
# Демоэкзамен 09.02.06 | au-team.irpo
# Запуск: curl -fsSL https://raw.githubusercontent.com/20XMAS24/de-09-02-06-guide/main/scripts/hq-srv.sh | bash
# ================================================================
set -e
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
info() { echo -e "${YELLOW}[>>]${NC} $1"; }

IFACES=($(ip -o link show | awk -F': ' '{print $2}' | grep -v lo | grep -v '@'))
ETH0=${IFACES[0]:-ens18}

echo "========================================"
echo "  НАСТРОЙКА HQ-SRV | 09.02.06"
echo "========================================"

# Задание 1: Hostname
hostnamectl set-hostname hq-srv.au-team.irpo
grep -q "127.0.1.1.*hq-srv" /etc/hosts || echo "127.0.1.1 hq-srv.au-team.irpo hq-srv" >> /etc/hosts
ok "hostname: $(hostname)"

# Задание 2: IP
nmcli con mod "$ETH0" ipv4.addresses 192.168.100.2/27 ipv4.gateway 192.168.100.1 \
  ipv4.dns "127.0.0.1" ipv4.method manual 2>/dev/null || \
  nmcli con add type ethernet con-name "$ETH0" ifname "$ETH0" \
    ipv4.addresses 192.168.100.2/27 ipv4.gateway 192.168.100.1 \
    ipv4.dns "127.0.0.1" ipv4.method manual
nmcli con up "$ETH0" 2>/dev/null || true
ok "IP: 192.168.100.2/27"

# Задание 3: sshuser
id sshuser &>/dev/null || useradd -u 2026 -m -s /bin/bash sshuser
echo "sshuser:P@ssw0rd" | chpasswd
grep -q "^sshuser" /etc/sudoers || echo "sshuser ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
ok "sshuser uid=$(id -u sshuser 2>/dev/null || echo '2026')"

# Задание 5: SSH
SSH_CONF=/etc/ssh/sshd_config
[ -f /etc/openssh/sshd_config ] && SSH_CONF=/etc/openssh/sshd_config
BANNER_DIR=$(dirname "$SSH_CONF")
echo "Authorized access only" > "$BANNER_DIR/banner"
sed -i 's/^#*Port .*/Port 2026/' "$SSH_CONF"
grep -q "^Port" "$SSH_CONF" || echo "Port 2026" >> "$SSH_CONF"
sed -i 's/^#*MaxAuthTries .*/MaxAuthTries 2/' "$SSH_CONF"
grep -q "^MaxAuthTries" "$SSH_CONF" || echo "MaxAuthTries 2" >> "$SSH_CONF"
grep -q "^Banner" "$SSH_CONF" || echo "Banner $BANNER_DIR/banner" >> "$SSH_CONF"
grep -q "^AllowUsers sshuser" "$SSH_CONF" || echo "AllowUsers sshuser" >> "$SSH_CONF"
systemctl enable sshd && systemctl restart sshd
ok "SSH: порт 2026, баннер, MaxAuthTries 2"

# Задание 10: BIND DNS
info "Задание 10: BIND DNS"
apt-get install -y bind
systemctl enable named
mkdir -p /var/bind

cat > /etc/bind/named.conf << 'EOF'
options {
    directory "/var/bind";
    listen-on { any; };
    allow-query { any; };
    recursion yes;
    forwarders { 77.88.8.7; 77.88.8.3; };
    forward first;
};
zone "au-team.irpo" IN {
    type master;
    file "/etc/bind/au-team.irpo.zone";
};
zone "100.168.192.in-addr.arpa" IN {
    type master;
    file "/etc/bind/100.168.192.rev";
};
EOF

cat > /etc/bind/au-team.irpo.zone << 'EOF'
$TTL 86400
@   IN SOA hq-srv.au-team.irpo. admin.au-team.irpo. (
        2026042901 3600 1800 604800 86400 )
@       IN  NS  hq-srv.au-team.irpo.
hq-rtr  IN  A   192.168.100.1
br-rtr  IN  A   192.168.20.1
hq-srv  IN  A   192.168.100.2
hq-cli  IN  A   192.168.200.10
br-srv  IN  A   192.168.20.2
docker  IN  A   172.16.1.1
web     IN  A   172.16.2.1
mon     IN  A   192.168.100.2
EOF

cat > /etc/bind/100.168.192.rev << 'EOF'
$TTL 86400
@   IN SOA hq-srv.au-team.irpo. admin.au-team.irpo. (
        2026042901 3600 1800 604800 86400 )
@   IN  NS   hq-srv.au-team.irpo.
1   IN  PTR  hq-rtr.au-team.irpo.
2   IN  PTR  hq-srv.au-team.irpo.
EOF

named-checkconf /etc/bind/named.conf 2>/dev/null && \
  named-checkzone au-team.irpo /etc/bind/au-team.irpo.zone 2>/dev/null || true
systemctl restart named
ok "BIND DNS: au-team.irpo"

# Задание 11: Часовой пояс
timedatectl set-timezone Europe/Moscow && ok "Часовой пояс: Europe/Moscow"

# Модуль 2: RAID0
info "Модуль 2: RAID0"
apt-get install -y mdadm
DISKS=($(lsblk -nd -o NAME,TYPE | awk '$2=="disk"{print "/dev/"$1}' | grep -v sda | grep -v vda | head -2))
if [ ${#DISKS[@]} -ge 2 ]; then
  [ -b /dev/md0 ] || echo "yes" | mdadm --create /dev/md0 --level=0 --raid-devices=2 "${DISKS[@]}"
  mdadm --detail --scan >> /etc/mdadm.conf 2>/dev/null || true
  mkfs.ext4 -F /dev/md0
  mkdir -p /raid
  grep -q "/dev/md0" /etc/fstab || echo "/dev/md0   /raid   ext4   defaults   0 0" >> /etc/fstab
  mount -a
  ok "RAID0: /dev/md0 -> /raid"
else
  echo "[WARN] Нет доп. дисков — добавьте 2 диска в Proxmox!"
  mkdir -p /raid
fi

# Модуль 2: NFS
info "Модуль 2: NFS-сервер"
apt-get install -y nfs-utils
mkdir -p /raid/nfs && chmod 777 /raid/nfs
grep -q "/raid/nfs" /etc/exports || \
  echo "/raid/nfs  192.168.200.0/27(rw,sync,no_subtree_check,no_root_squash)" >> /etc/exports
exportfs -arv
systemctl enable nfs-server && systemctl restart nfs-server
ok "NFS: /raid/nfs -> 192.168.200.0/27"

# Модуль 2: NTP-клиент
apt-get install -y chrony
echo "server 172.16.1.1 iburst" > /etc/chrony.conf
systemctl enable chronyd && systemctl restart chronyd
ok "NTP-клиент: 172.16.1.1"

# Модуль 2: Apache + MariaDB
info "Модуль 2: Apache + MariaDB"
apt-get install -y httpd mariadb-server php 2>/dev/null || \
  apt-get install -y apache2 mariadb-server php 2>/dev/null || true
systemctl enable mariadb && systemctl start mariadb
systemctl enable httpd 2>/dev/null && systemctl start httpd 2>/dev/null || \
  systemctl enable apache2 2>/dev/null && systemctl start apache2 2>/dev/null || true
mysql -u root 2>/dev/null << 'SQL'
CREATE DATABASE IF NOT EXISTS webdb;
CREATE USER IF NOT EXISTS 'web'@'localhost' IDENTIFIED BY 'P@ssw0rd';
GRANT ALL PRIVILEGES ON webdb.* TO 'web'@'localhost';
FLUSH PRIVILEGES;
SQL
ok "Apache + MariaDB (добавьте веб-файлы с ISO)"

# Модуль 3: rsyslog-сервер
info "Модуль 3: rsyslog сервер"
apt-get install -y rsyslog
grep -q "imudp" /etc/rsyslog.conf || cat >> /etc/rsyslog.conf << 'RSYSEOF'

module(load="imudp")
input(type="imudp" port="514")
module(load="imtcp")
input(type="imtcp" port="514")

$template RemoteLogs,"/opt/logs/%HOSTNAME%/%PROGRAMNAME%.log"
*.warn ?RemoteLogs
& stop
RSYSEOF
mkdir -p /opt/logs && chmod 755 /opt/logs
iptables -C INPUT -p udp --dport 514 -j ACCEPT 2>/dev/null || iptables -A INPUT -p udp --dport 514 -j ACCEPT
iptables -C INPUT -p tcp --dport 514 -j ACCEPT 2>/dev/null || iptables -A INPUT -p tcp --dport 514 -j ACCEPT
systemctl enable rsyslog && systemctl restart rsyslog
ok "rsyslog: слушает :514"

cat > /etc/logrotate.d/remote-logs << 'EOF'
/opt/logs/*/*.log {
    weekly
    rotate 4
    compress
    missingok
    notifempty
    postrotate
        systemctl reload rsyslog 2>/dev/null || true
    endscript
}
EOF
ok "logrotate настроен"

# Модуль 3: fail2ban
info "Модуль 3: fail2ban"
apt-get install -y fail2ban
LOGPATH=/var/log/auth.log
[ -f /var/log/secure ] && LOGPATH=/var/log/secure
cat > /etc/fail2ban/jail.local << JAILEOF
[DEFAULT]
bantime  = 60
findtime = 60
maxretry = 3

[sshd]
enabled  = true
port     = 2026
logpath  = $LOGPATH
maxretry = 3
bantime  = 60
JAILEOF
systemctl enable fail2ban && systemctl restart fail2ban
ok "fail2ban: порт 2026, max 3 попытки, ban 60s"

# Модуль 3: Zabbix
info "Модуль 3: Zabbix"
apt-get install -y zabbix-server-mysql zabbix-agent zabbix-web-mysql 2>/dev/null || true
if command -v zabbix_server &>/dev/null; then
  mysql -u root 2>/dev/null << 'SQL'
CREATE DATABASE IF NOT EXISTS zabbix CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER IF NOT EXISTS 'zabbix'@'localhost' IDENTIFIED BY 'P@ssw0rd';
GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'localhost';
FLUSH PRIVILEGES;
SQL
  SQL_GZ=$(find /usr/share -name "*.sql.gz" 2>/dev/null | grep zabbix | head -1)
  [ -n "$SQL_GZ" ] && zcat "$SQL_GZ" | mysql -uzabbix -pP@ssw0rd zabbix 2>/dev/null || true
  for KEY in DBHost DBName DBUser DBPassword; do
    VAL=$(echo "localhost zabbix zabbix P@ssw0rd" | awk "{print \$$(echo $KEY | awk '{if($1=="DBHost")print 1;if($1=="DBName")print 2;if($1=="DBUser")print 3;if($1=="DBPassword")print 4}')}")
    sed -i "s|^#*${KEY}=.*|${KEY}=${VAL}|" /etc/zabbix/zabbix_server.conf 2>/dev/null || true
  done
  sed -i 's|^.*DBPassword=.*|DBPassword=P@ssw0rd|' /etc/zabbix/zabbix_server.conf 2>/dev/null || true
  systemctl enable zabbix-server zabbix-agent 2>/dev/null && \
    systemctl restart zabbix-server zabbix-agent 2>/dev/null || true
  ok "Zabbix: http://mon.au-team.irpo/zabbix (Admin/zabbix)"
else
  echo "[INFO] Zabbix не найден — проверьте репозиторий"
fi

# Модуль 3: CUPS
apt-get install -y cups cups-pdf 2>/dev/null || true
if command -v lpadmin &>/dev/null; then
  sed -i 's/^Listen localhost.*/Port 631/' /etc/cups/cupsd.conf 2>/dev/null || true
  systemctl enable cups && systemctl restart cups
  lpadmin -p PDF -v cups-pdf:/ -m CUPS-PDF.ppd -E 2>/dev/null || true
  lpadmin -d PDF 2>/dev/null || true
  ok "CUPS: PDF принтер"
fi

echo ""
echo "========================================"
echo "  HQ-SRV ГОТОВ"
echo "========================================"
echo "IP: 192.168.100.2/27 | SSH: :2026 (sshuser:P@ssw0rd)"
echo "DNS: BIND9 au-team.irpo | NFS: /raid/nfs"
echo "rsyslog :514 | fail2ban | Zabbix | CUPS"
