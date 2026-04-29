#!/bin/bash
# ================================================================
# СКРИПТ АВТОНАСТРОЙКИ: BR-SRV
# Демоэкзамен 09.02.06 | au-team.irpo
# Запуск: curl -fsSL https://raw.githubusercontent.com/20XMAS24/de-09-02-06-guide/main/scripts/br-srv.sh | bash
# ================================================================
set -e
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
info() { echo -e "${YELLOW}[>>]${NC} $1"; }

IFACES=($(ip -o link show | awk -F': ' '{print $2}' | grep -v lo | grep -v '@'))
ETH0=${IFACES[0]:-ens18}

echo "========================================"
echo "  НАСТРОЙКА BR-SRV | 09.02.06"
echo "========================================"

# Задание 1: Hostname
hostnamectl set-hostname br-srv.au-team.irpo
grep -q "127.0.1.1.*br-srv" /etc/hosts || echo "127.0.1.1 br-srv.au-team.irpo br-srv" >> /etc/hosts
ok "hostname: $(hostname)"

# Задание 2: IP
nmcli con mod "$ETH0" ipv4.addresses 192.168.20.2/28 ipv4.gateway 192.168.20.1 ipv4.method manual 2>/dev/null || \
  nmcli con add type ethernet con-name "$ETH0" ifname "$ETH0" \
    ipv4.addresses 192.168.20.2/28 ipv4.gateway 192.168.20.1 ipv4.method manual
nmcli con up "$ETH0" 2>/dev/null || true
ok "IP: 192.168.20.2/28"

# Задание 3: sshuser
id sshuser &>/dev/null || useradd -u 2026 -m -s /bin/bash sshuser
echo "sshuser:P@ssw0rd" | chpasswd
grep -q "^sshuser" /etc/sudoers || echo "sshuser ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
ok "sshuser создан"

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
ok "SSH: порт 2026"

# Задание 11: Часовой пояс
timedatectl set-timezone Europe/Moscow && ok "Часовой пояс: Europe/Moscow"

# Модуль 2: Samba AD DC
info "Модуль 2: Samba AD DC"
apt-get install -y task-samba-dc 2>/dev/null || \
  apt-get install -y samba samba-dc winbind krb5-workstation 2>/dev/null || true
systemctl stop samba smbd nmbd winbind 2>/dev/null || true
[ -f /etc/samba/smb.conf ] && mv /etc/samba/smb.conf /etc/samba/smb.conf.bak 2>/dev/null || true
rm -rf /var/lib/samba/private/* 2>/dev/null || true

samba-tool domain provision \
  --realm=AU-TEAM.IRPO \
  --domain=AU-TEAM \
  --adminpass='P@ssw0rd' \
  --dns-backend=SAMBA_INTERNAL \
  --server-role=dc \
  --use-rfc2307

cat > /etc/resolv.conf << 'EOF'
domain au-team.irpo
search au-team.irpo
nameserver 127.0.0.1
EOF
chattr +i /etc/resolv.conf 2>/dev/null || true

systemctl unmask samba 2>/dev/null || true
systemctl enable samba && systemctl start samba
ok "Samba AD DC: au-team.irpo"

# Пользователи hquser1-5
for i in 1 2 3 4 5; do
  samba-tool user create "hquser$i" 'P@ssw0rd' \
    --given-name="HQ User $i" --surname="$i" 2>/dev/null || true
done
samba-tool group add hq 2>/dev/null || true
for i in 1 2 3 4 5; do
  samba-tool group addmembers hq "hquser$i" 2>/dev/null || true
done
ok "hquser1..5 в группе hq (P@ssw0rd)"

# Модуль 2: NTP-клиент
apt-get install -y chrony
echo "server 172.16.1.1 iburst" > /etc/chrony.conf
systemctl enable chronyd && systemctl restart chronyd
ok "NTP-клиент: 172.16.1.1"

# Модуль 2: Ansible
info "Модуль 2: Ansible"
apt-get install -y ansible
mkdir -p /etc/ansible/PC-INFO

cat > /etc/ansible/ansible.cfg << 'EOF'
[defaults]
inventory         = /etc/ansible/hosts
host_key_checking = False
remote_user       = sshuser
private_key_file  = /root/.ssh/id_rsa
EOF

cat > /etc/ansible/hosts << 'EOF'
[all]
hq-rtr.au-team.irpo  ansible_user=net_admin  ansible_port=22
hq-srv.au-team.irpo  ansible_user=sshuser    ansible_port=2026
hq-cli.au-team.irpo  ansible_user=sshuser    ansible_port=2026
br-rtr.au-team.irpo  ansible_user=net_admin  ansible_port=22
EOF

[ -f /root/.ssh/id_rsa ] || ssh-keygen -t rsa -b 4096 -N "" -f /root/.ssh/id_rsa
ok "Ansible настроен (выполните ssh-copy-id на все узлы)"

# Playbook инвентаризации
cat > /etc/ansible/playbook.yml << 'EOF'
---
- name: Inventory nodes
  hosts: all
  gather_facts: yes
  tasks:
    - name: Collect system info
      shell: |
        echo "hostname: $(hostname -f)"
        echo "ip: $(hostname -I | tr -s ' ')"
        echo "cpu_count: $(nproc)"
        echo "ram_mb: $(free -m | awk '/^Mem/{print $2}')"
      register: info

    - name: Save to PC-INFO directory
      copy:
        content: "{{ info.stdout }}\n"
        dest: "/etc/ansible/PC-INFO/{{ inventory_hostname }}.yml"
      delegate_to: localhost
EOF
ok "Playbook: /etc/ansible/playbook.yml"

# Модуль 2: Docker
info "Модуль 2: Docker"
apt-get install -y docker-ce docker-ce-cli containerd.io 2>/dev/null || \
  apt-get install -y docker docker-compose 2>/dev/null || true
systemctl enable docker 2>/dev/null && systemctl start docker 2>/dev/null || true

mkdir -p /opt/docker
cat > /opt/docker/docker-compose.yml << 'EOF'
version: '3'
services:
  site:
    image: site:latest
    container_name: site
    restart: always
    ports:
      - "8080:8080"
    environment:
      DB_HOST: db
      DB_NAME: testdb
      DB_USER: test
      DB_PASSWORD: P@ssw0rd
    depends_on:
      - db
  db:
    image: mariadb:latest
    container_name: db
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: P@ssw0rd
      MYSQL_DATABASE: testdb
      MYSQL_USER: test
      MYSQL_PASSWORD: P@ssw0rd
EOF
ok "Docker: /opt/docker/docker-compose.yml"
echo "  Загрузка образов: mount /dev/sr0 /media && for f in /media/docker/*.tar; do docker load -i \$f; done"
echo "  Запуск: cd /opt/docker && docker-compose up -d"

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
  sed -i 's/^Hostname=.*/Hostname=br-srv.au-team.irpo/' /etc/zabbix/zabbix_agentd.conf
  systemctl enable zabbix-agent && systemctl start zabbix-agent
  ok "Zabbix агент"
fi

echo ""
echo "========================================"
echo "  BR-SRV ГОТОВ"
echo "========================================"
echo "IP: 192.168.20.2/28 | SSH: :2026 (sshuser:P@ssw0rd)"
echo "Samba AD: au-team.irpo | hquser1..5 / P@ssw0rd"
echo "Ansible: /etc/ansible/ | Docker: /opt/docker/"
