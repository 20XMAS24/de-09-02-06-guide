# 📙 Модуль 3 — Эксплуатация объектов сетевой инфраструктуры

> **Время:** 1 час 30 мин | **Баллы:** 24 (только ДЭ ПУ)

[← Назад к README](../README.md)

---

## Задание 1 — IPSec / WireGuard VPN между офисами (site-to-site)

> Примечание: в Модуле 3 может быть задание на VPN. Используем WireGuard как типовое VPN-решение.

### WireGuard на HQ-RTR

```bash
apt-get install -y wireguard

# Генерировать ключи
wg genkey | tee /etc/wireguard/private.key | wg pubkey > /etc/wireguard/public.key
cat /etc/wireguard/private.key  # сохранить

vim /etc/wireguard/wg0.conf
```

```ini
[Interface]
PrivateKey = <приватный-ключ-HQ>
Address = 10.10.0.1/30
ListenPort = 51820

[Peer]
PublicKey = <публичный-ключ-BR>
AllowedIPs = 192.168.20.0/28  # сеть BR-SRV
Endpoint = 172.16.2.2:51820
```

```bash
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0

# Проверка
wg show
```

---

## Задание 2 — Межсетевой экран (firewall) на HQ-RTR и BR-RTR

```bash
# Правила iptables для защиты сети

# Запретить всё по умолчанию
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# Разрешить established/related
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT

# Разрешить loopback
iptables -A INPUT -i lo -j ACCEPT

# Разрешить SSH на порт 2026
iptables -A INPUT -p tcp --dport 2026 -j ACCEPT

# Разрешить веб (443, 80)
iptables -A INPUT -p tcp --dport 443 -j ACCEPT
iptables -A INPUT -p tcp --dport 80 -j ACCEPT

# Разрешить форвардинг для локальных сетей
iptables -A FORWARD -i eth1 -o eth0 -j ACCEPT   # из LAN в WAN

# Сохранить
iptables-save > /etc/sysconfig/iptables
```

---

## Задание 3 — Мониторинг (задание 7 Модуля 2 ПУ)

### Установка Zabbix (Open Source мониторинг)

```bash
# На HQ-SRV:
apt-get install -y zabbix-server-mysql zabbix-frontend-php zabbix-agent

# Создать БД Zabbix
mysql -u root << 'EOF'
CREATE DATABASE zabbix CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER 'zabbix'@'localhost' IDENTIFIED BY 'P@ssw0rd';
GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'localhost';
FLUSH PRIVILEGES;
EOF

# Импорт схемы
zcat /usr/share/zabbix-sql-scripts/mysql/server.sql.gz | mysql -uzabbix -pP@ssw0rd zabbix

# Настроить /etc/zabbix/zabbix_server.conf
vim /etc/zabbix/zabbix_server.conf
# DBHost=localhost
# DBName=zabbix
# DBUser=zabbix
# DBPassword=P@ssw0rd

systemctl enable zabbix-server zabbix-agent httpd
systemctl start zabbix-server zabbix-agent httpd
```

### DNS-запись для mon.au-team.irpo

```bash
# На HQ-SRV добавить в /etc/bind/au-team.irpo.zone:
# mon  IN  A  192.168.100.2

# Перезапустить DNS
systemctl restart named
```

### Доступ по URL
После настройки открыть `http://mon.au-team.irpo/zabbix` (admin / P@ssw0rd)

---

## Задание 4 — rsyslog (централизованные логи)

### Сервер логов (HQ-SRV)

```bash
apt-get install -y rsyslog
vim /etc/rsyslog.conf
```

Добавить/разрешить:

```
# Принимать логи по UDP/TCP
module(load="imudp")
input(type="imudp" port="514")
module(load="imtcp")
input(type="imtcp" port="514")

# Сохранять логи по имени хоста
$template RemoteLogs,"/opt/%HOSTNAME%/%PROGRAMNAME%.log"
*.warn ?RemoteLogs
& ~
```

```bash
mkdir -p /opt
systemctl restart rsyslog

# Убедиться, что HQ-SRV не отправляет себе же логи
# в /etc/rsyslog.conf - нет строки *.* @127.0.0.1:514
```

### Клиенты rsyslog (HQ-RTR, BR-RTR, BR-SRV)

```bash
# На каждом клиенте:
apt-get install -y rsyslog
vim /etc/rsyslog.conf

# Добавить:
*.warn @<IP-HQ-SRV>:514   # UDP
# или
*.warn @@<IP-HQ-SRV>:514  # TCP

systemctl restart rsyslog
```

### logrotate на HQ-SRV

```bash
vim /etc/logrotate.d/remote-logs
```

```
/opt/*/*.log /opt/*/*/*.log {
    weekly
    compress
    minsize 10M
    missingok
    notifempty
    sharedscripts
    postrotate
        systemctl reload rsyslog
    endscript
}
```

```bash
# Проверка
logrotate -d /etc/logrotate.d/remote-logs
```

---

## Задание 5 — Печать (CUPS) на HQ-SRV

```bash
apt-get install -y cups cups-pdf

# Разрешить удалённый доступ
vim /etc/cups/cupsd.conf
# Port 631
# Listen <IP-HQ-SRV>:631
# BrowseLocalProtocols dnssd
# Allow all - для сети HQ

systemctl enable cups
systemctl start cups

# Добавить PDF-принтер через веб-интерфейс CUPS:
# http://<IP-HQ-SRV>:631 -> Administration -> Add Printer
# Выбрать CUPS-PDF (Virtual PDF Printer)

# На HQ-CLI - подключить принтер
System Settings -> Printers -> Add Printer -> Network Printer -> IPP
# URI: ipp://<IP-HQ-SRV>:631/printers/PDF

# Проверка:
lpstat -p -d
```

---

## Задание 6 — Ansible инвентаризация через Playbook

Файл плейбука (\u0438з Additional.iso):

```yaml
---
- name: Inventory PC Info
  hosts: hq
  tasks:
    - name: Get hostname
      command: hostname
      register: pc_hostname

    - name: Get IP address
      command: hostname -I
      register: pc_ip

    - name: Save report
      copy:
        content: |
          hostname: {{ pc_hostname.stdout }}
          ip: {{ pc_ip.stdout }}
        dest: /etc/ansible/PC-INFO/{{ inventory_hostname }}.yml
      delegate_to: localhost
```

```bash
# Запустить
mkdir -p /etc/ansible/PC-INFO
# Положить playbook.yml из Additional.iso
cp /media/cdrom/playbook/playbook.yml /etc/ansible/

cd /etc/ansible
ansible-playbook playbook.yml

# Проверка
ls /etc/ansible/PC-INFO/
cat /etc/ansible/PC-INFO/hq-srv.au-team.irpo.yml
```

---

## Задание 7 — fail2ban на HQ-SRV

```bash
apt-get install -y fail2ban

vim /etc/fail2ban/jail.local
```

```ini
[DEFAULT]
bantime = 60
maxretry = 3

[sshd]
enabled = true
port = 2026
logpath = /var/log/auth.log
maxretry = 3
bantime = 60
```

```bash
systemctl enable fail2ban
systemctl start fail2ban

# Проверка
fail2ban-client status
fail2ban-client status sshd
```

---

## Задание 8 — Резервное копирование (Кибер Бэкап)

> Используется Кибер Бэкап 17.4 (рркомендации) или аналог.

```bash
# На HQ-SRV (сервер управления):
# 1. Установить Кибер Бэкап (RPM/DEB-пакет)
# 2. Настроить организацию: irpo
# 3. Создать администратора: irpoadmin / P@ssw0rd

# На HQ-CLI (узел хранилища):
# 1. Установить агент + функции узла хранилища
# 2. Подключить к серверу управления
# 3. Создать /backup и выбрать как Storage

# На HQ-SRV - создать планы резервного копирования:
# - План 1: директория /etc (все поддиректории) → узел хранилища HQ-CLI
# - План 2: БД webdb (MySQL-бэкап) → узел хранилища HQ-CLI

# Запустить резервное копирование (EXECUTE NOW)
```

---

[← Модуль 2](module2.md) | [Начало: README →](../README.md)
