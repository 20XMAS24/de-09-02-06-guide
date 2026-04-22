# ❓ FAQ — Частые вопросы по демоэкзамену 09.02.06

> Здесь собраны самые популярные вопросы и их решения.
> Используй `Ctrl+F` для поиска по ключевым словам.

---

## 🔌 Сеть и IP

### Как узнать имя сетевого интерфейса в ALT Linux?
```bash
ip link show
# или
nmcli con show
```
Интерфейс может называться `ens18`, `ens19`, `eth0` — зависит от Proxmox.

### Как назначить статический IP через nmcli?
```bash
nmcli con mod "ens18" ipv4.addresses 192.168.100.2/27 ipv4.gateway 192.168.100.1 ipv4.method manual
nmcli con up "ens18"
```

### Как настроить несколько IP на одном интерфейсе (VLAN)?
```bash
nmcli con add type vlan con-name vlan100 dev ens19 id 100 ipv4.addresses 192.168.100.1/27 ipv4.method manual
nmcli con up vlan100
```

### Почему ping не работает после настройки?
1. Проверь `ip a` — есть ли IP?
2. Проверь `ip route` — есть ли маршрут по умолчанию?
3. Включён ли форвардинг: `cat /proc/sys/net/ipv4/ip_forward`?
4. Не блокирует ли iptables: `iptables -L -n`?

---

## 🏠 Hostname

### Как правильно задать hostname?
```bash
hostnamectl set-hostname hq-rtr.au-team.irpo
# Проверка:
hostname
```

### После перезагрузки hostname сбрасывается — что делать?
```bash
echo "hq-rtr.au-team.irpo" > /etc/hostname
hostnamectl set-hostname hq-rtr.au-team.irpo
```

---

## 🔐 SSH

### Где находится конфиг SSH в ALT Linux?
```bash
# Путь в ALT Linux (отличается от Debian/Ubuntu!):
/etc/openssh/sshd_config
```

### Как сменить порт SSH на 2026?
```bash
vim /etc/openssh/sshd_config
# Найти и изменить:
# Port 2026
systemctl restart sshd
```

### Как добавить баннер SSH?
```bash
echo "Authorized access only" > /etc/openssh/banner
# В sshd_config добавить:
# Banner /etc/openssh/banner
systemctl restart sshd
```

### Как ограничить пользователей SSH?
```bash
# В /etc/openssh/sshd_config:
# AllowUsers sshuser
# MaxAuthTries 2
```

---

## 👤 Пользователи

### Как создать пользователя с определённым UID?
```bash
useradd -u 2026 -m -s /bin/bash sshuser
echo "sshuser:P@ssw0rd" | chpasswd
```

### Как дать пользователю sudo без пароля?
```bash
visudo
# Добавить в конец:
# sshuser ALL=(ALL) NOPASSWD: ALL
```

---

## 🌐 GRE-туннель

### Как создать GRE-туннель через nmcli?
```bash
# На HQ-RTR:
nmcli con add type ip-tunnel con-name gre1 ifname gre1 mode gre remote 172.16.2.2 local 172.16.1.2
nmcli con mod gre1 ipv4.addresses 10.0.0.1/30 ipv4.method manual
nmcli con up gre1

# На BR-RTR:
nmcli con add type ip-tunnel con-name gre1 ifname gre1 mode gre remote 172.16.1.2 local 172.16.2.2
nmcli con mod gre1 ipv4.addresses 10.0.0.2/30 ipv4.method manual
nmcli con up gre1
```

### GRE-туннель есть, но ping не проходит?
- Включён ли форвардинг? `sysctl net.ipv4.ip_forward`
- Настроен ли OSPF или статические маршруты?
- Не блокирует ли iptables протокол GRE? `iptables -A INPUT -p gre -j ACCEPT`

---

## 🔄 OSPF (FRRouting)

### Как проверить, установлен ли FRR?
```bash
vtysh -c "show version"
systemctl status frr
```

### OSPF-сосед не устанавливается — что проверить?
```bash
vtysh -c "show ip ospf neighbor"
# Статус должен быть Full
# Если нет:
# 1. Проверь что оба роутера в одной area (area 0)
# 2. Проверь пароли MD5 (должны совпадать)
# 3. Проверь passive-interface — тоннельный интерфейс НЕ должен быть passive
```

### Как посмотреть маршруты OSPF?
```bash
vtysh -c "show ip route ospf"
```

---

## 🏢 Samba AD

### Ошибка при provisioning: файлы уже существуют
```bash
systemctl stop samba smbd nmbd winbind 2>/dev/null
mv /etc/samba/smb.conf /etc/samba/smb.conf.bak
rm -rf /var/lib/samba/private/*
# Затем снова запустить samba-tool domain provision
```

### HQ-CLI не видит домен при realm join
```bash
# Убедитесь что DNS HQ-CLI указывает на BR-SRV:
nmcli con mod "ens18" ipv4.dns "<IP-BR-SRV>"
nmcli con up "ens18"
nslookup au-team.irpo
# Только после этого: realm join
```

### Как проверить пользователей AD?
```bash
samba-tool user list
samba-tool group listmembers hq
getent passwd hquser1  # на HQ-CLI
```

---

## 💾 RAID

### Как проверить статус RAID после создания?
```bash
cat /proc/mdstat
mdadm --detail /dev/md0
```

### RAID не монтируется после перезагрузки?
```bash
# Убедиться что конфиг сохранён:
cat /etc/mdadm.conf
# Убедиться что запись в fstab:
grep md0 /etc/fstab
# Вручную активировать:
mdadm --assemble --scan
mount -a
```

---

## 🕐 NTP

### Как проверить синхронизацию времени?
```bash
chronyc sources -v
# Значок * перед источником = активный и синхронизирован
chronyc tracking
```

### chrony не синхронизируется с ISP
```bash
# Проверить доступность ISP:
ping 172.16.1.1
# Проверить firewall на ISP:
iptables -A INPUT -p udp --dport 123 -j ACCEPT
```

---

## 🐳 Docker

### Как загрузить образ из tar-файла?
```bash
docker load -i /media/cdrom/docker/site.tar
docker images  # проверить имя и тег
```

### docker-compose up выдаёт ошибку — нет образа
```bash
# Проверить точное имя образа:
docker images
# IMAGE             TAG
# site              latest
# В docker-compose.yml использовать это точное имя!
```

---

## 🔥 iptables

### Как сохранить правила iptables в ALT Linux?
```bash
service iptables save
# или:
iptables-save > /etc/sysconfig/iptables
systemctl enable iptables
```

### После перезагрузки правила NAT исчезают?
```bash
service iptables save
systemctl enable iptables
systemctl start iptables
```

---

## 🔍 Диагностика

### Быстрая диагностика сети
```bash
ip a              # IP-адреса
ip route          # таблица маршрутов
ping 8.8.8.8      # интернет
ping 10.0.0.1     # GRE-туннель
nslookup hq-srv.au-team.irpo  # DNS
```

### Быстрая диагностика служб
```bash
systemctl status sshd
systemctl status named
systemctl status dhcpd
systemctl status frr
systemctl status samba
```

---

[← Назад к README](README.md)
