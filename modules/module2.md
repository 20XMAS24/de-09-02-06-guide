# 📘 Модуль 2 — Организация сетевого администрирования

> **Время:** 1 час 30 мин | **Баллы:** 24 (ДЭ БУ) / 24 (ДЭ ПУ)

> ⚠️ ТП преднастраивает: IP-адреса, NAT, туннель, маршрутизацию, пользователей, SSH, DHCP, DNS

[← Назад к README](../README.md)

---

## Задание 1 — Samba DC на BR-SRV (AD-контроллер домена)

### Установка Samba

```bash
apt-get install -y samba
```

### Провизионирование домена

```bash
# Остановить Samba перед провизионированием
systemctl stop samba smbd nmbd winbind 2>/dev/null

# Убрать старый smb.conf
mv /etc/samba/smb.conf /etc/samba/smb.conf.bak

# Провизионировать
samba-tool domain provision \
  --realm=AU-TEAM.IRPO \
  --domain=AU-TEAM \
  --adminpass='P@ssw0rd' \
  --dns-backend=SAMBA_INTERNAL \
  --server-role=dc \
  --use-rfc2307
```

```bash
# Настроить resolv.conf
cat > /etc/resolv.conf << EOF
domain au-team.irpo
nameserver 127.0.0.1
EOF

# Запустить Samba AD
systemctl unmask samba
systemctl enable samba
systemctl start samba

# Проверка
samba-tool domain info 127.0.0.1
```

### Создание пользователей hquser1..5 и группы hq

```bash
# Создать пользователей
for i in 1 2 3 4 5; do
  samba-tool user create hquser$i P@ssw0rd
done

# Создать группу
samba-tool group add hq

# Добавить пользователей в группу
for i in 1 2 3 4 5; do
  samba-tool group addmembers hq hquser$i
done

# Проверка
samba-tool user list
samba-tool group listmembers hq
```

### Права sudo для группы hq (cat, grep, id)

На HQ-CLI после ввода в домен:

```bash
visudo
# Добавить:
%hq ALL=(ALL) NOPASSWD:/usr/bin/cat,/usr/bin/grep,/usr/bin/id
```

### Ввод HQ-CLI в домен

```bash
# На HQ-CLI:
apt-get install -y sssd samba-common-bin

# Настройть /etc/sssd/sssd.conf
cat > /etc/sssd/sssd.conf << 'EOF'
[sssd]
domains = au-team.irpo
config_file_version = 2
services = nss, pam

[domain/au-team.irpo]
ad_domain = au-team.irpo
krb5_realm = AU-TEAM.IRPO
realmd_tags = manages-system joined-with-samba
cache_credentials = True
id_provider = ad
krb5_store_password_if_offline = True
default_shell = /bin/bash
ldap_id_mapping = True
use_fully_qualified_names = False
fallback_homedir = /home/%u
access_provider = ad
EOF
chmod 600 /etc/sssd/sssd.conf

# Проверка DNS - HQ-CLI должен видеть BR-SRV как DNS
nslookup au-team.irpo <IP-BR-SRV>

# Присоединить машину к домену (net join)
net ads join -U Administrator%P@ssw0rd
# или через realm:
realm join au-team.irpo -U Administrator

systemctl enable sssd
systemctl start sssd

# Проверка
getent passwd hquser1
```

---

## Задание 2 — RAID0 + ext4 на HQ-SRV

```bash
# Проверить наличие дополнительных дисков
lsblk
# Ожидаем диски /dev/sdb и /dev/sdc (по ×1 ГБ)

apt-get install -y mdadm

# Создать RAID0 (striping, нет избыточности, максимальная скорость)
mdadm --create /dev/md0 --level=0 --raid-devices=2 /dev/sdb /dev/sdc

# Сохранить конфигурацию
mdadm --detail --scan >> /etc/mdadm.conf

# Создать раздел
mkfs.ext4 /dev/md0

# Создать точку монтирования
mkdir -p /raid

# Автомонтирование (добавить в /etc/fstab)
echo "/dev/md0  /raid  ext4  defaults  0  0" >> /etc/fstab
mount -a

# Проверка
df -h /raid
cat /proc/mdstat
```

---

## Задание 3 — NFS-сервер на HQ-SRV

```bash
apt-get install -y nfs-utils

# Создать папку общего доступа
mkdir -p /raid/nfs
chmod 777 /raid/nfs

# Настроить экспорт
vim /etc/exports
```

```
/raid/nfs  192.168.200.0/27(rw,sync,no_subtree_check,no_root_squash)
# используйте сеть VLAN200 (HQ-CLI)
```

```bash
# Применить экспорт
exportfs -arv
systemctl enable nfs-server
systemctl start nfs-server

# Проверка экспортов
showmount -e localhost
```

### Автомонтирование на HQ-CLI

```bash
apt-get install -y nfs-utils autofs

# Настроить autofs
vim /etc/auto.master
# добавить: /mnt/nfs  /etc/auto.nfs

vim /etc/auto.nfs
# добавить: nfs  -fstype=nfs4,rw  <IP-HQ-SRV>:/raid/nfs

mkdir -p /mnt/nfs
systemctl enable autofs
systemctl start autofs

# Проверка
ls /mnt/nfs
df -h
```

---

## Задание 4 — NTP chrony на ISP

```bash
apt-get install -y chrony

vim /etc/chrony.conf
```

Содержимое `/etc/chrony.conf` на ISP:

```
# Вышестоящий NTP-сервер (на выбор участника)
pool ntp.ru iburst

# Стратум
# Chrony автоматически становится stratum+1 от вышестоящего
# Чтобы задать stratum 5 - используйте local stratum:
local stratum 5

# Разрешить обслуживание клиентов
allow all
```

```bash
systemctl enable chronyd
systemctl restart chronyd

# Проверка
chronyc sources
chronyc tracking
```

### Настройка NTP-клиентов (HQ-SRV, HQ-CLI, BR-RTR, BR-SRV)

```bash
# На каждом клиенте:
vim /etc/chrony.conf
# заменить/добавить:
server <IP-ISP> iburst

systemctl restart chronyd

# Проверка
chronyc sources -v
```

---

## Задание 5 — Ansible на BR-SRV

```bash
apt-get install -y ansible

# Создать рабочий каталог
mkdir -p /etc/ansible
vim /etc/ansible/ansible.cfg
```

```ini
[defaults]
inventory = /etc/ansible/hosts
host_key_checking = False
remote_user = sshuser
private_key_file = ~/.ssh/id_rsa
```

```bash
vim /etc/ansible/hosts
```

```ini
[all]
hq-srv.au-team.irpo ansible_user=sshuser
hq-cli.au-team.irpo ansible_user=sshuser
hq-rtr.au-team.irpo ansible_user=net_admin
br-rtr.au-team.irpo ansible_user=net_admin

[hq]
hq-srv.au-team.irpo
hq-cli.au-team.irpo
hq-rtr.au-team.irpo

[br]
br-rtr.au-team.irpo
```

```bash
# Сгенерировать SSH-ключ
 ssh-keygen -t rsa -b 4096 -N "" -f ~/.ssh/id_rsa

# Разослать ключ на все узлы
ssh-copy-id -p 2026 sshuser@<IP-HQ-SRV>
ssh-copy-id -p 2026 sshuser@<IP-HQ-CLI>
ssh-copy-id net_admin@<IP-HQ-RTR>
ssh-copy-id net_admin@<IP-BR-RTR>

# Проверка ping
ansible all -m ping
```

---

## Задание 6 — Docker + веб-приложение на BR-SRV

```bash
apt-get install -y docker docker-compose
systemctl enable docker
systemctl start docker

# Импортировать образы из Additional.iso
# (проверить путь docker/-директории)
ls /media/cdrom/docker/
docker load -i /media/cdrom/docker/site_latest
docker load -i /media/cdrom/docker/mariadb_latest

# Проверить имя загруженных образов
docker images
```

Файл `docker-compose.yml`:

```yaml
version: '3'
services:
  testapp:
    image: site_latest
    container_name: testapp
    ports:
      - "8080:8080"
    environment:
      - DB_HOST=db
      - DB_NAME=testdb
      - DB_USER=test
      - DB_PASS=P@ssw0rd
    depends_on:
      - db

  db:
    image: mariadb_latest
    container_name: db
    environment:
      - MYSQL_ROOT_PASSWORD=P@ssw0rd
      - MYSQL_DATABASE=testdb
      - MYSQL_USER=test
      - MYSQL_PASSWORD=P@ssw0rd
```

```bash
cd /opt/docker
docker-compose up -d

# Проверка
docker ps
curl http://localhost:8080
```

---

## Задание 7 — Apache + MariaDB (веб-приложение) на HQ-SRV

```bash
apt-get install -y apache2 php mariadb-server
systemctl enable httpd mariadb
systemctl start httpd mariadb

# Получить файлы из образа Additional.iso
ls /media/cdrom/web/

# Скопировать файлы веб-приложения
cp /media/cdrom/web/index.php /var/www/html/
cp -r /media/cdrom/web/images /var/www/html/

# Создать БД и пользователя
mysql -u root << 'EOF'
CREATE DATABASE webdb;
CREATE USER 'web'@'localhost' IDENTIFIED BY 'P@ssw0rd';
GRANT ALL PRIVILEGES ON webdb.* TO 'web'@'localhost';
FLUSH PRIVILEGES;
EOF

# Импорт дампа
mysql -u root webdb < /media/cdrom/web/dump.sql

# Отредактировать index.php (указать подключение к БД)
vim /var/www/html/index.php
# Найти и изменить строки подключения к БД:
# $db_host = 'localhost';
# $db_name = 'webdb';
# $db_user = 'web';
# $db_pass = 'P@ssw0rd';

systemctl restart httpd

# Проверка
curl http://localhost/index.php
```

---

## Задание 8 — Port forwarding (проброс портов) на HQ-RTR и BR-RTR

```bash
# На HQ-RTR:
# Проброс порта 8080 на HQ-SRV
iptables -t nat -A PREROUTING -i eth0 -p tcp --dport 8080 -j DNAT --to-destination <IP-HQ-SRV>:8080
iptables -A FORWARD -p tcp -d <IP-HQ-SRV> --dport 8080 -j ACCEPT

# Проброс порта 2026 на HQ-SRV
iptables -t nat -A PREROUTING -i eth0 -p tcp --dport 2026 -j DNAT --to-destination <IP-HQ-SRV>:2026
iptables -A FORWARD -p tcp -d <IP-HQ-SRV> --dport 2026 -j ACCEPT

# На BR-RTR:
# Проброс порта 8080 на BR-SRV (testapp)
iptables -t nat -A PREROUTING -i eth0 -p tcp --dport 8080 -j DNAT --to-destination <IP-BR-SRV>:8080
iptables -A FORWARD -p tcp -d <IP-BR-SRV> --dport 8080 -j ACCEPT

# Проброс порта 2026 на BR-SRV
iptables -t nat -A PREROUTING -i eth0 -p tcp --dport 2026 -j DNAT --to-destination <IP-BR-SRV>:2026
iptables -A FORWARD -p tcp -d <IP-BR-SRV> --dport 2026 -j ACCEPT

# Сохранить
iptables-save > /etc/sysconfig/iptables
```

---

## Задание 9 — nginx обратный прокси на ISP

```bash
apt-get install -y nginx

vim /etc/nginx/nginx.conf
```

Добавить virtual hosts:

```nginx
server {
    listen 80;
    server_name web.au-team.irpo;

    auth_basic "Restricted";
    auth_basic_user_file /etc/nginx/.htpasswd;

    location / {
        proxy_pass http://172.16.1.2:8080;   # IP HQ-RTR (port forwarding)
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}

server {
    listen 80;
    server_name docker.au-team.irpo;

    location / {
        proxy_pass http://172.16.2.2:8080;   # IP BR-RTR (port forwarding)
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

---

## Задание 10 — HTTP аутентификация для web.au-team.irpo

```bash
# Установить htpasswd
apt-get install -y apache2-utils

# Создать файл паролей (логин: WEB, пароль: P@ssw0rd)
htpasswd -c /etc/nginx/.htpasswd WEB
# Введите P@ssw0rd при запросе

# Или неинтерактивно:
echo 'WEB:'$(openssl passwd -apr1 'P@ssw0rd') > /etc/nginx/.htpasswd

# Пример nginx.conf с auth_basic (см. задание 9)
# auth_basic уже добавлен в server web.au-team.irpo

nginx -t
systemctl enable nginx
systemctl restart nginx
```

---

## Задание 11 — Установка Яндекс Браузера на HQ-CLI

```bash
# Скачать RPM-пакет
# Опция 1: через браузер или curl
curl -LO https://repo.yandex.ru/yandex-browser/rpm/stable/x86_64/yandex-browser-stable.rpm

# Установка через apt
apt-get install -y yandex-browser-stable

# Или через rpm/dnf
rpm -i yandex-browser-stable.rpm

# Проверка
yandex-browser --version
```

---

[← Модуль 1](module1.md) | [Далее: Модуль 3 →](module3.md)
