#!/bin/bash
# ================================================================
# СКРИПТ АВТОНАСТРОЙКИ: HQ-CLI
# Демоэкзамен 09.02.06 | au-team.irpo (ALT Linux)
# Запуск: curl -fsSL https://raw.githubusercontent.com/20XMAS24/de-09-02-06-guide/main/scripts/hq-cli.sh | bash
# ================================================================
# set -e убран намеренно — скрипт продолжает при ошибках отдельных шагов
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
info() { echo -e "${YELLOW}[>>]${NC} $1"; }
err()  { echo -e "${RED}[ERR]${NC} $1"; }

# Определяем первый сетевой интерфейс автоматически
ETH0=$(ip -o link show | awk -F': ' '{print $2}' | grep -v lo | grep -v '@' | head -1)
ETH0=${ETH0:-ens18}

echo "========================================"
echo "  НАСТРОЙКА HQ-CLI | 09.02.06"
echo "  Интерфейс: $ETH0"
echo "========================================"

# Устанавливаем базовые пакеты (нужны до useradd)
info "Установка базовых пакетов..."
apt-get install -y shadow-utils passwd sudo 2>/dev/null || \
  apt-get install -y shadow passwd sudo 2>/dev/null || true

# Задание 1: Hostname
info "Задание 1: hostname"
hostnamectl set-hostname hq-cli.au-team.irpo 2>/dev/null || \
  echo "hq-cli.au-team.irpo" > /etc/hostname
grep -q "127.0.1.1.*hq-cli" /etc/hosts || \
  echo "127.0.1.1 hq-cli.au-team.irpo hq-cli" >> /etc/hosts
ok "hostname: $(hostname)"

# Задание 2: IP через DHCP
info "Задание 2: IP через DHCP на $ETH0"
if command -v nmcli &>/dev/null; then
  nmcli con mod "$ETH0" ipv4.method auto 2>/dev/null || \
    nmcli con add type ethernet con-name "$ETH0" ifname "$ETH0" ipv4.method auto 2>/dev/null || true
  nmcli con up "$ETH0" 2>/dev/null || true
else
  dhclient "$ETH0" 2>/dev/null || true
fi
sleep 3
MYIP=$(ip -4 a show dev "$ETH0" 2>/dev/null | awk '/inet/{print $2}' | head -1)
ok "DHCP: IP = ${MYIP:-не получен, проверьте VLAN200}"

# Задание 3: sshuser
info "Задание 3: sshuser (uid=2026)"
if id sshuser &>/dev/null; then
  ok "sshuser уже существует"
else
  useradd -u 2026 -m -s /bin/bash sshuser 2>/dev/null || \
    adduser -u 2026 -s /bin/bash sshuser 2>/dev/null || \
    useradd -m -s /bin/bash sshuser 2>/dev/null || \
    adduser sshuser 2>/dev/null || err "useradd не удалось — выполните вручную"
fi
echo "sshuser:P@ssw0rd" | chpasswd 2>/dev/null || \
  echo "sshuser:P@ssw0rd" | passwd --stdin sshuser 2>/dev/null || \
  passwd sshuser << 'PASSEOF'
P@ssw0rd
P@ssw0rd
PASSEOF
# sudo для sshuser
if [ -d /etc/sudoers.d ]; then
  echo "sshuser ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/sshuser
  chmod 440 /etc/sudoers.d/sshuser
else
  grep -q "^sshuser" /etc/sudoers || echo "sshuser ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
fi
ok "sshuser: uid=$(id -u sshuser 2>/dev/null || echo '?'), пароль P@ssw0rd"

# Задание 11: Часовой пояс
timedatectl set-timezone Europe/Moscow 2>/dev/null && ok "Часовой пояс: Europe/Moscow"

# Модуль 2: DNS -> BR-SRV для AD
if command -v nmcli &>/dev/null; then
  nmcli con mod "$ETH0" ipv4.dns "192.168.20.2" 2>/dev/null || true
  nmcli con up "$ETH0" 2>/dev/null || true
fi

# Модуль 2: Ввод в домен AD
info "Модуль 2: ввод в домен au-team.irpo"
apt-get install -y sssd sssd-ad adcli realmd samba-winbind-clients 2>/dev/null || \
  apt-get install -y sssd adcli realmd 2>/dev/null || true
if host au-team.irpo 192.168.20.2 &>/dev/null; then
  echo 'P@ssw0rd' | realm join --user=Administrator au-team.irpo 2>/dev/null && \
    systemctl enable sssd 2>/dev/null && systemctl start sssd 2>/dev/null || true
  if [ -d /etc/sudoers.d ]; then
    echo "%hq ALL=(ALL) NOPASSWD:/usr/bin/cat,/usr/bin/grep,/usr/bin/id" > /etc/sudoers.d/hq-group
    chmod 440 /etc/sudoers.d/hq-group
  fi
  ok "Введён в домен au-team.irpo"
else
  err "BR-SRV (192.168.20.2) недоступен!"
  echo "  После настройки сети выполните вручную:"
  echo "  realm join --user=Administrator au-team.irpo"
fi

# Модуль 2: autofs NFS
info "Модуль 2: autofs NFS"
apt-get install -y nfs-utils autofs 2>/dev/null || \
  apt-get install -y nfs-client autofs 2>/dev/null || true
grep -q "/mnt/nfs" /etc/auto.master 2>/dev/null || \
  echo "/mnt/nfs  /etc/auto.nfs  --timeout=60" >> /etc/auto.master
cat > /etc/auto.nfs << 'EOF'
shared   -fstype=nfs4,rw   192.168.100.2:/raid/nfs
EOF
mkdir -p /mnt/nfs
systemctl enable autofs 2>/dev/null && systemctl restart autofs 2>/dev/null || true
ok "autofs: /mnt/nfs/shared -> 192.168.100.2:/raid/nfs"

# Модуль 2: NTP-клиент
apt-get install -y chrony 2>/dev/null || true
cat > /etc/chrony.conf << 'EOF'
server 172.16.1.1 iburst
driftfile /var/lib/chrony/drift
rtcsync
EOF
systemctl enable chronyd 2>/dev/null && systemctl restart chronyd 2>/dev/null || true
ok "NTP-клиент: 172.16.1.1"

# Модуль 2: Яндекс Браузер
info "Модуль 2: Яндекс Браузер"
if apt-cache search yandex-browser 2>/dev/null | grep -q "yandex"; then
  apt-get install -y yandex-browser-stable 2>/dev/null && ok "Яндекс Браузер установлен" || \
    err "Яндекс Браузер — ошибка установки"
else
  echo "[INFO] Не найден в репо. Установите с ISO или вручную:"
  echo "  apt-get install -y yandex-browser-stable"
fi

# rsyslog клиент
apt-get install -y rsyslog 2>/dev/null || true
grep -q "192.168.100.2:514" /etc/rsyslog.conf 2>/dev/null || \
  echo "*.warn   @@192.168.100.2:514" >> /etc/rsyslog.conf
systemctl enable rsyslog 2>/dev/null && systemctl restart rsyslog 2>/dev/null || true
ok "rsyslog клиент -> HQ-SRV:514"

# Zabbix агент
apt-get install -y zabbix-agent 2>/dev/null || true
if [ -f /etc/zabbix/zabbix_agentd.conf ]; then
  sed -i 's/^Server=.*/Server=192.168.100.2/' /etc/zabbix/zabbix_agentd.conf
  sed -i 's/^ServerActive=.*/ServerActive=192.168.100.2/' /etc/zabbix/zabbix_agentd.conf
  sed -i 's/^Hostname=.*/Hostname=hq-cli.au-team.irpo/' /etc/zabbix/zabbix_agentd.conf
  systemctl enable zabbix-agent 2>/dev/null && systemctl start zabbix-agent 2>/dev/null || true
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
echo "Интерфейс: $ETH0"
ip -4 a show dev "$ETH0" 2>/dev/null | grep inet || echo "IP: DHCP (проверьте VLAN200)"
echo "sshuser / P@ssw0rd"
echo "autofs: /mnt/nfs/shared"
echo ""
echo "Если домен не подключён — выполните:"
echo "  realm join --user=Administrator au-team.irpo"
