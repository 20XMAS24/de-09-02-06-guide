#!/bin/bash
# ================================================================
# СКРИПТ АВТОНАСТРОЙКИ: HQ-CLI
# Демоэкзамен 09.02.06 | au-team.irpo
# Запуск: curl -fsSL https://raw.githubusercontent.com/20XMAS24/de-09-02-06-guide/main/scripts/hq-cli.sh | bash
# ================================================================
set -e
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
info() { echo -e "${YELLOW}[>>]${NC} $1"; }

IFACES=($(ip -o link show | awk -F': ' '{print $2}' | grep -v lo | grep -v '@'))
ETH0=${IFACES[0]:-ens18}

echo "========================================"
echo "  НАСТРОЙКА HQ-CLI | 09.02.06"
echo "========================================"

# Задание 1: Hostname
hostnamectl set-hostname hq-cli.au-team.irpo
grep -q "127.0.1.1.*hq-cli" /etc/hosts || echo "127.0.1.1 hq-cli.au-team.irpo hq-cli" >> /etc/hosts
ok "hostname: $(hostname)"

# Задание 2: IP через DHCP
nmcli con mod "$ETH0" ipv4.method auto 2>/dev/null || \
  nmcli con add type ethernet con-name "$ETH0" ifname "$ETH0" ipv4.method auto
nmcli con up "$ETH0" 2>/dev/null || true
ok "DHCP запрошен. IP: $(ip -4 a show dev $ETH0 | awk '/inet/{print $2}' | head -1)"

# Задание 3: sshuser
id sshuser &>/dev/null || useradd -u 2026 -m -s /bin/bash sshuser
echo "sshuser:P@ssw0rd" | chpasswd
grep -q "^sshuser" /etc/sudoers || echo "sshuser ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
ok "sshuser создан"

# Задание 11: Часовой пояс
timedatectl set-timezone Europe/Moscow && ok "Часовой пояс: Europe/Moscow"

# Модуль 2: DNS -> BR-SRV (AD)
nmcli con mod "$ETH0" ipv4.dns "192.168.20.2" 2>/dev/null || true
nmcli con up "$ETH0" 2>/dev/null || true

# Модуль 2: Ввод в домен AD
info "Модуль 2: ввод в домен au-team.irpo"
apt-get install -y sssd sssd-ad adcli realmd samba-common-tools 2>/dev/null || true
if host au-team.irpo 192.168.20.2 &>/dev/null; then
  echo 'P@ssw0rd' | realm join --user=Administrator au-team.irpo
  systemctl enable sssd && systemctl start sssd
  grep -q "^%hq" /etc/sudoers || \
    echo "%hq ALL=(ALL) NOPASSWD:/usr/bin/cat,/usr/bin/grep,/usr/bin/id" >> /etc/sudoers
  ok "Введён в домен au-team.irpo"
else
  echo "[WARN] BR-SRV недоступен. Выполните вручную:"
  echo "  realm join --user=Administrator au-team.irpo"
fi

# Модуль 2: autofs NFS
info "Модуль 2: autofs NFS"
apt-get install -y nfs-utils autofs
grep -q "/mnt/nfs" /etc/auto.master || \
  echo "/mnt/nfs  /etc/auto.nfs  --timeout=60" >> /etc/auto.master
cat > /etc/auto.nfs << 'EOF'
shared   -fstype=nfs4,rw   192.168.100.2:/raid/nfs
EOF
mkdir -p /mnt/nfs
systemctl enable autofs && systemctl restart autofs
ok "autofs: /mnt/nfs/shared -> 192.168.100.2:/raid/nfs"

# Модуль 2: NTP-клиент
apt-get install -y chrony
echo "server 172.16.1.1 iburst" > /etc/chrony.conf
systemctl enable chronyd && systemctl restart chronyd
ok "NTP-клиент: 172.16.1.1"

# Модуль 2: Яндекс Браузер
info "Модуль 2: Яндекс Браузер"
if apt-cache search yandex 2>/dev/null | grep -q "yandex-browser"; then
  apt-get install -y yandex-browser-stable 2>/dev/null && ok "Яндекс Браузер установлен" || true
else
  echo "[INFO] Яндекс Браузер: apt-get install -y yandex-browser-stable"
fi

# rsyslog клиент
apt-get install -y rsyslog
grep -q "192.168.100.2:514" /etc/rsyslog.conf || \
  echo "*.warn   @@192.168.100.2:514" >> /etc/rsyslog.conf
systemctl enable rsyslog && systemctl restart rsyslog
ok "rsyslog клиент"

# Zabbix агент
apt-get install -y zabbix-agent 2>/dev/null || true
if [ -f /etc/zabbix/zabbix_agentd.conf ]; then
  sed -i 's/^Server=.*/Server=192.168.100.2/' /etc/zabbix/zabbix_agentd.conf
  sed -i 's/^ServerActive=.*/ServerActive=192.168.100.2/' /etc/zabbix/zabbix_agentd.conf
  sed -i 's/^Hostname=.*/Hostname=hq-cli.au-team.irpo/' /etc/zabbix/zabbix_agentd.conf
  systemctl enable zabbix-agent && systemctl start zabbix-agent
  ok "Zabbix агент"
fi

# CUPS клиент
apt-get install -y cups cups-client 2>/dev/null || true
if command -v lpadmin &>/dev/null; then
  lpadmin -p HQ-PDF -v ipp://192.168.100.2:631/printers/PDF -m everywhere -E 2>/dev/null || true
  ok "CUPS принтер: HQ-PDF"
fi

echo ""
echo "========================================"
echo "  HQ-CLI ГОТОВ"
echo "========================================"
ip -4 a | grep inet | grep -v 127 || echo "IP не получен — проверьте DHCP"
echo "autofs: /mnt/nfs/shared | rsyslog клиент"
echo "Войти в систему: hquser1 / P@ssw0rd"
