# 🖥️ Настройка Proxmox VE для демоэкзамена

> Пошаговый гайд: как правильно создать ВМ и сети в Proxmox перед началом экзамена.

---

## Шаг 1 — Создание Linux Bridges

В Proxmox каждая «сеть» — это отдельный bridge. Перейдите:
**Datacenter → Node → System → Network → Create → Linux Bridge**

| Bridge | Назначение | IP Proxmox | CIDR |
|--------|-----------|------------|------|
| `vmbr0` | WAN (интернет) | уже есть | — |
| `vmbr1` | ISP ↔ HQ-RTR | нет | 172.16.1.0/28 |
| `vmbr2` | ISP ↔ BR-RTR | нет | 172.16.2.0/28 |
| `vmbr3` | HQ внутренняя (trunk) | нет | — |
| `vmbr4` | BR внутренняя | нет | — |

> ⚠️ У `vmbr1`–`vmbr4` НЕ нужно назначать IP на хосте Proxmox — они только для ВМ.

```bash
# На хосте Proxmox (через Shell):
# Добавить в /etc/network/interfaces:
auto vmbr1
iface vmbr1 inet manual
    bridge-ports none
    bridge-stp off
    bridge-fd 0

auto vmbr2
iface vmbr2 inet manual
    bridge-ports none
    bridge-stp off
    bridge-fd 0

auto vmbr3
iface vmbr3 inet manual
    bridge-ports none
    bridge-stp off
    bridge-fd 0

auto vmbr4
iface vmbr4 inet manual
    bridge-ports none
    bridge-stp off
    bridge-fd 0

# Применить:
ifreload -a
# или перезагрузить сеть:
systemctl restart networking
```

---

## Шаг 2 — Создание ВМ

### ISP
- **ОС:** ALT JeOS
- **RAM:** 1 ГБ, **CPU:** 1, **Disk:** 10 ГБ
- **Сетевые адаптеры:**
  - eth0 → `vmbr0` (WAN)
  - eth1 → `vmbr1` (к HQ-RTR)
  - eth2 → `vmbr2` (к BR-RTR)

### HQ-RTR
- **ОС:** ALT JeOS
- **RAM:** 1 ГБ, **CPU:** 2, **Disk:** 10 ГБ
- **Сетевые адаптеры:**
  - eth0 → `vmbr1` (WAN к ISP)
  - eth1 → `vmbr3` (LAN trunk, без VLAN-тега в Proxmox!)

### BR-RTR
- **ОС:** ALT JeOS
- **RAM:** 1 ГБ, **CPU:** 2, **Disk:** 10 ГБ
- **Сетевые адаптеры:**
  - eth0 → `vmbr2` (WAN к ISP)
  - eth1 → `vmbr4` (LAN к BR-SRV)

### HQ-SRV
- **ОС:** ALT Server
- **RAM:** 2 ГБ, **CPU:** 2, **Disk:** 10 ГБ + 2x5 ГБ (для RAID)
- **Сетевые адаптеры:**
  - eth0 → `vmbr3`, **VLAN Tag: 100**

### HQ-CLI
- **ОС:** ALT Рабочая Станция
- **RAM:** 2 ГБ, **CPU:** 2, **Disk:** 15 ГБ
- **Сетевые адаптеры:**
  - eth0 → `vmbr3`, **VLAN Tag: 200**

### BR-SRV
- **ОС:** ALT Server
- **RAM:** 2 ГБ, **CPU:** 2, **Disk:** 10 ГБ
- **Сетевые адаптеры:**
  - eth0 → `vmbr4`

---

## Шаг 3 — Загрузка ISO

1. **Datacenter → Node → local → ISO Images → Upload**
2. Загрузить ISO для каждого типа ALT Linux
3. При создании ВМ выбрать нужный ISO

---

## Шаг 4 — Добавление дисков для RAID (HQ-SRV)

1. Выбрать ВМ HQ-SRV → **Hardware → Add → Hard Disk**
2. Добавить 2 диска по 5 ГБ (или по условию задания)
3. Убедиться что они видны как `sdb` и `sdc` внутри ВМ:
```bash
lsblk
```

---

## Шаг 5 — Подключение Additional.iso (Docker/Kиберbackup)

1. Выбрать нужную ВМ → **Hardware → CD/DVD Drive → Edit**
2. Выбрать Additional.iso из хранилища
3. Внутри ВМ:
```bash
mkdir -p /media/cdrom
mount /dev/sr0 /media/cdrom
ls /media/cdrom/
```

---

## Шаг 6 — Настройка VLAN на vmbr3

В Proxmox есть два подхода:

**Вариант A (рекомендуется):** HQ-RTR получает все VLANы через один trunk-порт без тега в Proxmox. VLAN-тегирование делает сам ALT Linux через `nmcli con add type vlan`.
- HQ-RTR: eth1 → vmbr3, **VLAN Tag: пусто (0/none)**
- HQ-SRV: eth0 → vmbr3, **VLAN Tag: 100**
- HQ-CLI: eth0 → vmbr3, **VLAN Tag: 200**

**Вариант Б:** Отдельный bridge для каждого VLAN (vmbr3=VLAN100, vmbr4=VLAN200, vmbr5=VLAN999). Проще, но нужно больше bridges.

---

## Быстрая проверка топологии

```bash
# На каждой ВМ после загрузки:
ip link show  # видны все интерфейсы?
hostname      # правильный?
ping <IP-шлюза>  # связь с соседом?
```

---

[← README](README.md)
