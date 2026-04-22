# 📘 Демонстрационный Экзамен — КОД 09.02.06-1-2026

> **Специальность:** 09.02.06 Сетевое и системное администрирование
> **ОС на всех ВМ:** Альт Linux (JeOS / Server / Рабочая Станция)
> **Платформа виртуализации:** Proxmox VE

---

## 🗒️ Структура экзамена

| Модуль | Название | ПА | ДЭ БУ | ДЭ ПУ | Время |
|--------|----------|----|-------|-------|-------|
| [Модуль 1](modules/module1.md) | Настройка сетевой инфраструктуры | ✅ | ✅ | ✅ | 1 ч. |
| [Модуль 2](modules/module2.md) | Организация сетевого администрирования | ❌ | ✅ | ✅ | 1 ч. 30 мин. |
| [Модуль 3](modules/module3.md) | Эксплуатация объектов сетевой инфраструктуры | ❌ | ❌ | ✅ | 1 ч. 30 мин. |

**Баллы:** ПА: 25 | ГИА БУ: 50 | ГИА ПУ: 75

---

## 🖥️ Настройка Proxmox VE перед экзаменом

### Топология сетей Proxmox (Linux Bridges)

В Proxmox все сети ВМ настраиваются через **Linux Bridge**. Каждая сеть — это отдельный bridge:

```
Proxmox хост:
  vmbr0  — WAN (внешняя сеть, на ISP)
  vmbr1  — сеть ISP ↔ HQ-RTR
  vmbr2  — сеть ISP ↔ BR-RTR
  vmbr3  — сеть HQ (trunk между HQ-RTR и HQ-SRV/HQ-CLI)
  vmbr4  — сеть BR (BR-RTR ↔ BR-SRV)
```

### Настройка bridges в `/etc/network/interfaces` Proxmox

```bash
# На Proxmox хосте:
auto vmbr1
iface vmbr1 inet manual
    bridge-ports none
    bridge-stp off
    bridge-fd 0
    # Коммент: сеть ISP-HQ, 172.16.1.0/28

auto vmbr2
iface vmbr2 inet manual
    bridge-ports none
    bridge-stp off
    bridge-fd 0
    # Коммент: сеть ISP-BR, 172.16.2.0/28

auto vmbr3
iface vmbr3 inet manual
    bridge-ports none
    bridge-stp off
    bridge-fd 0
    # Коммент: HQ внутренняя сеть (транк)

auto vmbr4
iface vmbr4 inet manual
    bridge-ports none
    bridge-stp off
    bridge-fd 0
    # Коммент: BR внутренняя сеть
```

### Назначение сетевых адаптеров ВМ

| ВМ | eth0 (bridge) | eth1 (bridge) | eth2 (bridge) |
|---|---|---|---|
| ISP | vmbr0 (WAN) | vmbr1 (HQ) | vmbr2 (BR) |
| HQ-RTR | vmbr1 (WAN→ISP) | vmbr3 (LAN trunk) | — |
| BR-RTR | vmbr2 (WAN→ISP) | vmbr4 (LAN) | — |
| HQ-SRV | vmbr3 | — | — |
| HQ-CLI | vmbr3 | — | — |
| BR-SRV | vmbr4 | — | — |

> ⚠️ Для работы VLAN (транкинга) на vmbr3 в настройках сетевого адаптера ВМ HQ-RTR оставляйте VLAN Tag = **0** (без тэга), остальная маркировка делается на уровне ОС.

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
Альт Server Альт WS

          GRE туннель: 10.0.0.0/30
          HQ-RTR 10.0.0.1 ↔ BR-RTR 10.0.0.2
```

---

## 📹 Устройства и ресурсы

| Устройство | ОС (Альт) | vCPU | RAM | Disk | Setu |
|---|---|---|---|---|---|
| ISP | JeOS / Server | 1 | 1 ГБ | 10 ГБ | 3 сеть (WAN, HQ, BR) |
| HQ-RTR | JeOS | 2 | 1 ГБ | 10 ГБ | 2 сети (WAN+LAN) |
| BR-RTR | JeOS | 2 | 1 ГБ | 10 ГБ | 2 сети |
| HQ-SRV | Альт Server | 2 | 2 ГБ | 20 ГБ (+2x5ГБ для RAID) |
| BR-SRV | Альт Server | 2 | 2 ГБ | 10 ГБ | 1 сеть |
| HQ-CLI | Альт WS | 2 | 2 ГБ | 15 ГБ | 1 сеть |

---

## 📌 Ключевые данные экзамена

| Параметр | Значение |
|---|---|
| Домен | `au-team.irpo` |
| SSH-порт | `2026` |
| SSH-баннер | `Authorized access only` |
| Пароль всех польз. | `P@ssw0rd` |
| UID sshuser | `2026` |
| ISP → HQ | `172.16.1.0/28` |
| ISP → BR | `172.16.2.0/28` |

---

## 📁 Навигация

- 📗 [Модуль 1 — Настройка сетевой инфраструктуры](modules/module1.md)
- 📘 [Модуль 2 — Организация сетевого администрирования](modules/module2.md)
- 📙 [Модуль 3 — Эксплуатация объектов сетевой инфраструктуры](modules/module3.md)
- 📊 [Таблица IP-адресации](modules/ip-table.md)
- 🔑 [Учётные записи](modules/credentials.md)

---
*Документация: КОД 09.02.06-1-2026, ФГБОУ ДПО ИРПО, 29.09.2025*
