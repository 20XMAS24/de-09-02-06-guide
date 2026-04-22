# 📗 Модуль 1 — Настройка сетевой инфраструктуры

> **Время:** 1 час | **Баллы:** 25 (ПА) / 26 (ДЭ БУ) / 27 (ДЭ ПУ)

[← Назад к README](../README.md)

---

## Задание 1 — Базовая настройка устройств: hostname + IP-адресация (VLSM)

### Почему VLSM?
Вместо одной большой сети делим пространство на подсети по фактической потребности:

| Сегмент | Требование | Маска | Пример сети | Пример шлюза |
|---|---|---|---|---|
| HQ-SRV (VLAN 100) | ≤ 32 адреса | /27 | 192.168.100.0/27 | 192.168.100.1 |
| HQ-CLI (VLAN 200) | ≥ 16 адресов | /27 или /28 | 192.168.200.0/27 | 192.168.200.1 |
| VLAN 999 (управление) | ≤ 8 адресов | /29 | 192.168.99.0/29 | 192.168.99.1 |
| BR-SRV | ≤ 16 адресов | /28 | 192.168.20.0/28 | 192.168.20.1 |

> ⚠️ **Важно:** Точные адреса на экзамене не заданы — участник сам выбирает из приватных диапазонов RFC1918 (10.x.x.x, 172.16-31.x.x, 192.168.x.x).

### Установка hostname

```bash
# Используйте FQDN (полное доменное имя)
hostnamectl set-hostname isp.au-team.irpo         # на ISP
hostnamectl set-hostname hq-rtr.au-team.irpo       # на HQ-RTR
hostnamectl set-hostname br-rtr.au-team.irpo       # на BR-RTR
hostnamectl set-hostname hq-srv.au-team.irpo       # на HQ-SRV
hostnamectl set-hostname br-srv.au-team.irpo       # на BR-SRV
hostnamectl set-hostname hq-cli.au-team.irpo       # на HQ-CLI

# Проверка
hostname
```

### Настройка IP-адресов (Альт Linux)

```bash
# Список интерфейсов
ip a

# Узнать имя интерфейса
ip link show

# Настройка через nmcli (рекомендуется для Альт)
nmcli con mod "Wired connection 1" ipv4.addresses 192.168.100.2/27 ipv4.gateway 192.168.100.1 ipv4.method manual
nmcli con up "Wired connection 1"

# Или через /etc/net (старый метод Альт)
vim /etc/net/ifaces/eth0/ipv4address
# запиши: 192.168.100.2/27
vim /etc/net/ifaces/eth0/ipv4route
# запиши: default via 192.168.100.1
service network restart
```

---

## Задание 2 — Настройка ISP: NAT, DHCP, маршруты

### Настройка интерфейсов ISP

```bash
# eth0 — внешний (получает DHCP от провайдера)
nmcli con mod "Wired connection 1" ipv4.method auto
nmcli con up "Wired connection 1"

# eth1 — в сторону HQ-RTR
nmcli con mod "Wired connection 2" ipv4.addresses 172.16.1.1/28 ipv4.method manual
nmcli con up "Wired connection 2"

# eth2 — в сторону BR-RTR
nmcli con mod "Wired connection 3" ipv4.addresses 172.16.2.1/28 ipv4.method manual
nmcli con up "Wired connection 3"
```

### Включить IP форвардинг

```bash
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p
```

### NAT (masquerade) на ISP для HQ-RTR и BR-RTR

```bash
# Через iptables
iptables -t nat -A POSTROUTING -o eth0 -s 172.16.1.0/28 -j MASQUERADE
iptables -t nat -A POSTROUTING -o eth0 -s 172.16.2.0/28 -j MASQUERADE

# Сохранить правила
iptables-save > /etc/sysconfig/iptables
apt-get install -y iptables-services
systemctl enable iptables
```

---

## Задание 3 — Создание пользователей

### Пользователь sshuser на HQ-SRV и BR-SRV

```bash
# Создать пользователя с UID=2026
useradd -u 2026 -m -s /bin/bash sshuser

# Установить пароль
echo "sshuser:P@ssw0rd" | chpasswd

# Дать sudo без пароля (NOPASSWD)
echo "sshuser ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
# Или лучше через visudo:
echo "sshuser ALL=(ALL) NOPASSWD:ALL" | sudo EDITOR='tee -a' visudo

# Проверка
id sshuser
```

### Пользователь net_admin на HQ-RTR и BR-RTR (если Linux)

```bash
useradd -m -s /bin/bash net_admin
echo "net_admin:P@ssw0rd" | chpasswd
echo "net_admin ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
```

---

## Задание 4 — Настройка VLAN и router-on-a-stick на HQ-RTR

### Концепция

Один физический порт HQ-RTR разделяется на подинтерфейсы (trunk). HQ-SW настраивается в режиме trunk на порту к HQ-RTR.

### На HQ-RTR (Linux: Альт JeOS)

```bash
# Создаём VLAN-интерфейсы на eth0
# VLAN 100 - HQ-SRV
nmcli con add type vlan con-name vlan100 dev eth0 id 100
nmcli con mod vlan100 ipv4.addresses 192.168.100.1/27 ipv4.method manual
nmcli con up vlan100

# VLAN 200 - HQ-CLI
nmcli con add type vlan con-name vlan200 dev eth0 id 200
nmcli con mod vlan200 ipv4.addresses 192.168.200.1/27 ipv4.method manual
nmcli con up vlan200

# VLAN 999 - management
nmcli con add type vlan con-name vlan999 dev eth0 id 999
nmcli con mod vlan999 ipv4.addresses 192.168.99.1/29 ipv4.method manual
nmcli con up vlan999

# Проверка
ip a show eth0.100
ip a show eth0.200
ip a show eth0.999
```

### На HQ-SW (если EcoRouter/Linux)

```bash
# Если используется Linux-коммутатор (bridge)
# Создаём бриджи для каждого VLAN
ip link add name br100 type bridge
ip link set eth1 master br100         # порт к HQ-SRV - access VLAN100
ip link set br100 up
ip link set eth1 up

# На trunk-порту (к HQ-RTR) помечаем tagged-траффик
# Создаём VLAN-подинтерфейсы на trunk-порте (eth0 = порт к HQ-RTR)
ip link add link eth0 name eth0.100 type vlan id 100
ip link add link eth0 name eth0.200 type vlan id 200
ip link add link eth0 name eth0.999 type vlan id 999
ip link set eth0.100 master br100
```

---

## Задание 5 — Настройка SSH на HQ-SRV и BR-SRV

```bash
# Открыть конфиг SSH
vim /etc/ssh/sshd_config
```

Изменить или добавить следующие строки:

```
Port 2026
AllowUsers sshuser
MaxAuthTries 2
Banner /etc/ssh/banner
```

```bash
# Создать файл баннера
echo "Authorized access only" > /etc/ssh/banner

# Перезапустить SSH
systemctl restart sshd

# Проверка с другой машины:
ssh -p 2026 sshuser@<ip-hq-srv>
```

---

## Задание 6 — IP-туннель HQ-RTR ↔ BR-RTR (GRE или IP-in-IP)

### Вариант GRE (рекомендуется)

```bash
# На HQ-RTR
ip tunnel add gre1 mode gre remote 172.16.2.2 local 172.16.1.2 ttl 255
ip addr add 10.0.0.1/30 dev gre1
ip link set gre1 up

# Чтобы туннель переживал перезагрузку, добавить в /etc/network/interfaces или nmcli:
nmcli con add type ip-tunnel con-name gre1 mode gre remote 172.16.2.2 local 172.16.1.2
nmcli con mod gre1 ipv4.addresses 10.0.0.1/30 ipv4.method manual
nmcli con up gre1
```

```bash
# На BR-RTR
nmcli con add type ip-tunnel con-name gre1 mode gre remote 172.16.1.2 local 172.16.2.2
nmcli con mod gre1 ipv4.addresses 10.0.0.2/30 ipv4.method manual
nmcli con up gre1

# Проверка
ping 10.0.0.1   # с BR-RTR до HQ-RTR через туннель
```

### IP-in-IP (альтернатива)

```bash
# На HQ-RTR
ip tunnel add ipip1 mode ipip remote 172.16.2.2 local 172.16.1.2
ip addr add 10.0.0.1/30 dev ipip1
ip link set ipip1 up

# На BR-RTR
ip tunnel add ipip1 mode ipip remote 172.16.1.2 local 172.16.2.2
ip addr add 10.0.0.2/30 dev ipip1
ip link set ipip1 up
```

---

## Задание 7 — Динамическая маршрутизация (OSPF)

### Установка FRRouting

```bash
apt-get install -y frr

# Включить OSPF
sed -i 's/ospfd=no/ospfd=yes/' /etc/frr/daemons
systemctl restart frr
```

### Настройка OSPF на HQ-RTR

```bash
vtysh
# Далее в режиме vtysh:
configure terminal
router ospf
  ospf router-id 1.1.1.1
  network 10.0.0.0/30 area 0    ! Только интерфейс туннеля
  passive-interface default      ! запретить на всех
  no passive-interface gre1      ! разрешить только на туннель
  redistribute connected         ! анонсировать подключённые сети
exchange
!
# Парольная защита OSPF
interface gre1
  ip ospf authentication message-digest
  ip ospf message-digest-key 1 md5 P@ssw0rd
end
write
```

```bash
# Проверка
show ip ospf neighbor
show ip route
```

---

## Задание 8 — NAT на HQ-RTR и BR-RTR (доступ в Интернет)

```bash
# включить форвардинг
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf && sysctl -p

# NAT на интерфейс в сторону ISP (eth0)
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

# Сохранить
iptables-save > /etc/sysconfig/iptables
systemctl enable iptables
systemctl start iptables

# Проверка (с HQ-CLI)
ping 8.8.8.8
```

---

## Задание 9 — DHCP для HQ-CLI на HQ-RTR

```bash
apt-get install -y dhcp-server
vim /etc/dhcp/dhcpd.conf
```

```
subnet 192.168.200.0 netmask 255.255.255.224 {
    range 192.168.200.2 192.168.200.30;    # исключаем .1 (шлюз)
    option routers 192.168.200.1;
    option domain-name-servers 192.168.100.2;   # IP HQ-SRV
    option domain-name "au-team.irpo";
    default-lease-time 600;
    max-lease-time 7200;
}
```

```bash
# Указать интерфейс для DHCP-сервера
vim /etc/sysconfig/dhcpd
# DHCPDv4_ARGS="eth0.200"   <- интерфейс VLAN200

systemctl enable dhcpd
systemctl start dhcpd

# Проверка на HQ-CLI
dhclient eth0
ip a
```

---

## Задание 10 — DNS-сервер на HQ-SRV (BIND)

```bash
apt-get install -y bind

vim /etc/bind/named.conf
```

Добавить зоны:

```
zone "au-team.irpo" {
    type master;
    file "/etc/bind/au-team.irpo.zone";
};

zone "100.168.192.in-addr.arpa" {
    type master;
    file "/etc/bind/100.168.192.rev";
};

zone "." {
    type forward;
    forwarders { 77.88.8.7; 77.88.8.3; };
};
```

Файл зоны (`/etc/bind/au-team.irpo.zone`):

```
$TTL 86400
@   IN SOA hq-srv.au-team.irpo. admin.au-team.irpo. (
            2026042201 ; serial
            3600       ; refresh
            1800       ; retry
            604800     ; expire
            86400 )    ; minimum

@           IN  NS  hq-srv.au-team.irpo.
hq-rtr      IN  A   192.168.100.1    ; IP HQ-RTR в VLAN100
br-rtr      IN  A   192.168.20.1     ; IP BR-RTR
hq-srv      IN  A   192.168.100.2    ; IP HQ-SRV
hq-cli      IN  A   192.168.200.2    ; IP HQ-CLI
br-srv      IN  A   192.168.20.2     ; IP BR-SRV
docker      IN  A   172.16.1.1       ; IP ISP в сторону HQ
web         IN  A   172.16.2.1       ; IP ISP в сторону BR
```

Обратная зона (`/etc/bind/100.168.192.rev`):

```
$TTL 86400
@   IN SOA hq-srv.au-team.irpo. admin.au-team.irpo. (
            2026042201 3600 1800 604800 86400 )

@   IN  NS  hq-srv.au-team.irpo.
1   IN  PTR hq-rtr.au-team.irpo.
2   IN  PTR hq-srv.au-team.irpo.
```

```bash
# Настроить прослушивание на всех интерфейсах
vim /etc/bind/named.conf
# listen-on { any; };
# allow-query { any; };

systemctl enable named
systemctl start named

# Проверка
nslookup hq-srv.au-team.irpo 127.0.0.1
dig hq-rtr.au-team.irpo @127.0.0.1
```

---

## Задание 11 — Часовой пояс на всех устройствах

```bash
# Установить часовой пояс (выберите нужный по месту проведения экзамена)
timedatectl set-timezone Europe/Moscow    # Москва
# или
timedatectl set-timezone Asia/Vladivostok # Владивосток
# или
timedatectl set-timezone Asia/Yekaterinburg # Екатеринбург

# Проверка
timedatectl
date
```

---

[← Назад](../README.md) | [Далее: Модуль 2 →](module2.md)
