# 🔑 Учётные записи и пароли

> ⚠️ Только для экзамена. Не используйте в продакшне.

[← Назад к README](../README.md)

| Устройство | Пользователь | Пароль | Примечание |
|---|---|---|---|
| HQ-SRV, BR-SRV | `sshuser` | `P@ssw0rd` | UID=2026, sudo NOPASSWD |
| HQ-RTR, BR-RTR | `net_admin` | `P@ssw0rd` | sudo NOPASSWD (Linux) |
| Samba AD | `Administrator` | `P@ssw0rd` | админ домена |
| Samba AD | `hquser1..5` | `P@ssw0rd` | группа hq |
| MariaDB (web) | `web` | `P@ssw0rd` | БД webdb |
| MariaDB (docker) | `test` | `P@ssw0rd` | БД testdb |
| Zabbix | `admin` | `P@ssw0rd` | веб-интерфейс |
| nginx basic auth | `WEB` | `P@ssw0rd` | web.au-team.irpo |
| Кибер Бэкап | `irpoadmin` | `P@ssw0rd` | админ сервера |

## SSH

```bash
# Подключение к HQ-SRV
ssh -p 2026 sshuser@<IP-HQ-SRV>

# Подключение к BR-SRV
ssh -p 2026 sshuser@<IP-BR-SRV>
```

## Домен

| Параметр | Значение |
|---|---|
| Имя домена | `au-team.irpo` |
| NetBIOS | `AU-TEAM` |
| realm | `AU-TEAM.IRPO` |
