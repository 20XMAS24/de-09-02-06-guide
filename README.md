# 📘 Демоэкзамен 09.02.06 — Полный гайд (ALT Linux + Proxmox)

> **Специальность:** 09.02.06 Сетевое и системное администрирование | КОД 09.02.06-1-2026
> **ОС:** Альт Linux (JeOS / Server / Рабочая Станция) | **Виртуализация:** Proxmox VE

![ALT Linux](https://img.shields.io/badge/OS-ALT%20Linux-blue)
![Proxmox](https://img.shields.io/badge/Platform-Proxmox%20VE-orange)
![License](https://img.shields.io/badge/exam-09.02.06-green)

Гайд по демонстрационному экзамену (демоэкзамену) по специальности **09.02.06 Сетевое и системное администрирование**. Подробные пошаговые инструкции с командами для каждого задания: настройка VLAN, GRE-туннеля, OSPF, NAT, DHCP, DNS, Samba AD, RAID, NFS, Docker, nginx, WireGuard VPN, fail2ban, Zabbix, rsyslog, NTP, Ansible на **Альт Linux** в **Proxmox VE**.

---

## 📌 Ключевые навыки и темы

`демоэкзамен 09.02.06` `ALT Linux` `Proxmox` `сетевое администрирование` `VLAN` `GRE туннель` `OSPF` `FRRouting` `Samba AD` `RAID0` `NFS autofs` `Docker` `nginx reverse proxy` `WireGuard VPN` `fail2ban` `Zabbix` `rsyslog` `chrony NTP` `Ansible` `DHCP` `BIND DNS` `iptables NAT` `nmcli` `КИРПО` `ИРПО` `сетевой администратор`

---

## 📦 Навигация

| Файл | Описание |
|---|---|
| 📗 [modules/module1.md](modules/module1.md) | Модуль 1: hostname, IP, VLAN, GRE, OSPF, NAT, DHCP, DNS, SSH |
| 📘 [modules/module2.md](modules/module2.md) | Модуль 2: Samba AD, RAID, NFS, NTP, Ansible, Docker, Apache, nginx |
| 📙 [modules/module3.md](modules/module3.md) | Модуль 3: WireGuard, firewall, Zabbix, rsyslog, CUPS, fail2ban, бэкап |
| 🖥️ [PROXMOX-SETUP.md](PROXMOX-SETUP.md) | Настройка Proxmox: bridges, ВМ, VLAN, диски |
| 📋 [CHEATSHEET.md](CHEATSHEET.md) | Шпаргалка: все команды на одной странице |
| ❓ [FAQ.md](FAQ.md) | Частые вопросы и проблемы с решениями |
| 📊 [modules/ip-table.md](modules/ip-table.md) | Таблица IP-адресации |
| 🔑 [modules/credentials.md](modules/credentials.md) | Учётные записи |

---

## 📊 Структура экзамена

| Модуль | Название | ПА | ДЭ БУ | ДЭ ПУ | Время |
|--------|----------|----|-------|-------|-------|
| [Модуль 1](modules/module1.md) | Настройка сетевой инфраструктуры | ✅ | ✅ | ✅ | 1 ч. |
| [Модуль 2](modules/module2.md) | Организация сетевого администрирования | ❌ | ✅ | ✅ | 1 ч. 30 мин. |
| [Модуль 3](modules/module3.md) | Эксплуатация объектов сетевой инфраструктуры | ❌ | ❌ | ✅ | 1 ч. 30 мин. |

**Максимальные баллы:** ПА: 25 | ГИА БУ: 50 | ГИА ПУ: 75

---

## 🖥️ Настройка Proxmox VE

### Linux Bridges (сети в Proxmox)

```
Proxmox хост:
  vmbr0  — WAN (внешняя сеть, на ISP)
  vmbr1  — сеть ISP ↔ HQ-RTR (172.16.1.0/28)
  vmbr2  — сеть ISP ↔ BR-RTR (172.16.2.0/28)
  vmbr3  — сеть HQ (транк между HQ-RTR и HQ-SRV/HQ-CLI)
  vmbr4  — сеть BR (BR-RTR ↔ BR-SRV)
```

### Адаптеры ВМ

| ВМ | eth0 | eth1 | VLAN Tag |
|---|---|---|---|
| ISP | vmbr0 | vmbr1, vmbr2 | нет |
| HQ-RTR | vmbr1 | vmbr3 | **без тега** (VLAN делает ALT) |
| BR-RTR | vmbr2 | vmbr4 | нет |
| HQ-SRV | vmbr3 | — | **100** |
| HQ-CLI | vmbr3 | — | **200** |
| BR-SRV | vmbr4 | — | нет |

→ Подробнее: [PROXMOX-SETUP.md](PROXMOX-SETUP.md)

---

## 📺 Топология сети

```
          [Internet]
               |
       [ISP - Альт JeOS]
        /              \
  172.16.1.0/28    172.16.2.0/28
       /                  \
  [HQ-RTR]             [BR-RTR]
  Альт JeOS            Альт JeOS
  /    |    \                 |
 VLAN  VLAN  VLAN99       192.168.20.0/28
  100  200  (mgmt)             |
   |    |                  [BR-SRV]
[HQ-SRV] [HQ-CLI]         Альт Server

     GRE-туннель: 10.0.0.0/30
     HQ-RTR (10.0.0.1) ↔ BR-RTR (10.0.0.2)
```

---

## 📌 Ключевые параметры

| Параметр | Значение |
|---|---|
| Домен | `au-team.irpo` |
| SSH-порт | `2026` |
| SSH-баннер | `Authorized access only` |
| Пароль | `P@ssw0rd` |
| UID sshuser | `2026` |
| ISP → HQ | `172.16.1.0/28` |
| ISP → BR | `172.16.2.0/28` |
| GRE-туннель | `10.0.0.0/30` |

---

## ⚡ Быстрый старт (шпаргалка)

```bash
# 1. Установить hostname (на каждой ВМ)
hostnamectl set-hostname hq-rtr.au-team.irpo

# 2. Назначить IP-адрес
nmcli con mod "ens18" ipv4.addresses 172.16.1.2/28 ipv4.gateway 172.16.1.1 ipv4.method manual
nmcli con up "ens18"

# 3. Часовой пояс
timedatectl set-timezone Europe/Moscow

# 4. Включить форвардинг
echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf && sysctl -p
```

→ См. полную шпаргалку: [CHEATSHEET.md](CHEATSHEET.md)

---

## 🛠️ Технологии в экзамене

| Категория | Инструмент | Где используется |
|---|---|---|
| Сеть | nmcli, VLAN, GRE, iptables | все узлы |
| Маршрутизация | OSPF через FRRouting (vtysh) | HQ-RTR, BR-RTR |
| AD | Samba Domain Controller | BR-SRV |
| Хранение | RAID0 (mdadm) + NFS + autofs | HQ-SRV, HQ-CLI |
| Время | chrony NTP | ISP, клиенты |
| Автоматизация | Ansible playbook | BR-SRV |
| Контейнеры | Docker + docker-compose | BR-SRV |
| Веб | Apache + MariaDB, nginx proxy | HQ-SRV, ISP |
| VPN | WireGuard site-to-site | HQ-RTR ↔ BR-RTR |
| Безопасность | fail2ban, iptables firewall | HQ-SRV, роутеры |
| Мониторинг | Zabbix + rsyslog + logrotate | HQ-SRV |
| Бэкап | Кибер Бэкап | HQ-SRV → HQ-CLI |

---

*Документ: КОД 09.02.06-1-2026 · ФГБОУ ДПО ИРПО · 29.09.2025*
