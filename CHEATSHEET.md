# 📋 Шпаргалка — ALT Linux команды для демоэкзамена

> Все ключевые команды на одной странице. Замените значения в `< >` на свои.

---

## Hostname
```bash
hostnamectl set-hostname <узел>.au-team.irpo
hostname  # проверка
```

## Сеть (nmcli)
```bash
nmcli con show                        # список подключений
nmcli con mod "<имя>" ipv4.addresses <IP>/<маска> ipv4.gateway <GW> ipv4.method manual
nmcli con mod "<имя>" ipv4.dns <DNS>
nmcli con up "<имя>"
ip a                                  # проверка
```

## VLAN
```bash
nmcli con add type vlan con-name vlan<N> dev <интерфейс> id <N> ipv4.addresses <IP>/<маска> ipv4.method manual
nmcli con up vlan<N>
ip a show <интерфейс>.<N>             # проверка
```

## GRE-туннель
```bash
nmcli con add type ip-tunnel con-name gre1 ifname gre1 mode gre remote <IP-партнёра> local <мой-WAN-IP>
nmcli con mod gre1 ipv4.addresses <IP-туннеля>/30 ipv4.method manual
nmcli con up gre1
ping -c3 <IP-партнёра-в-туннеле>      # проверка
```

## NAT + форвардинг
```bash
echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf && sysctl -p
iptables -t nat -A POSTROUTING -o <WAN-интерфейс> -j MASQUERADE
service iptables save
systemctl enable iptables
```

## Пользователи
```bash
useradd -u 2026 -m -s /bin/bash sshuser
echo "sshuser:P@ssw0rd" | chpasswd
visudo  # добавить: sshuser ALL=(ALL) NOPASSWD: ALL
id sshuser  # проверка
```

## SSH (/etc/openssh/sshd_config)
```
Port 2026
AllowUsers sshuser
MaxAuthTries 2
Banner /etc/openssh/banner
```
```bash
echo "Authorized access only" > /etc/openssh/banner
systemctl restart sshd
```

## OSPF (FRRouting)
```bash
apt-get install -y frr
sed -i 's/ospfd=no/ospfd=yes/' /etc/frr/daemons
systemctl restart frr && systemctl enable frr
vtysh
```
```
configure terminal
router ospf
  ospf router-id 1.1.1.1
  network 10.0.0.0/30 area 0
  redistribute connected
  passive-interface default
  no passive-interface gre1
interface gre1
  ip ospf authentication message-digest
  ip ospf message-digest-key 1 md5 P@ssw0rd
end
write memory
```
```bash
vtysh -c "show ip ospf neighbor"     # проверка
```

## DHCP
```bash
apt-get install -y dhcp-server
# /etc/dhcp/dhcpd.conf:
# subnet 192.168.200.0 netmask 255.255.255.224 {
#   range 192.168.200.10 192.168.200.30;
#   option routers 192.168.200.1;
#   option domain-name-servers 192.168.100.2;
#   option domain-name "au-team.irpo";
# }
# /etc/sysconfig/dhcpd: DHCPDv4_ARGS="ens19.200"
systemctl enable dhcpd && systemctl start dhcpd
```

## DNS (BIND)
```bash
apt-get install -y bind
named-checkconf /etc/bind/named.conf
named-checkzone au-team.irpo /etc/bind/au-team.irpo.zone
systemctl enable named && systemctl restart named
nslookup hq-srv.au-team.irpo 127.0.0.1  # проверка
```

## Samba AD
```bash
apt-get install -y task-samba-dc
systemctl stop samba smbd nmbd winbind 2>/dev/null
mv /etc/samba/smb.conf /etc/samba/smb.conf.bak
samba-tool domain provision --realm=AU-TEAM.IRPO --domain=AU-TEAM --adminpass='P@ssw0rd' --dns-backend=SAMBA_INTERNAL --server-role=dc
systemctl enable samba && systemctl start samba
samba-tool user create hquser1 P@ssw0rd
samba-tool group add hq
samba-tool group addmembers hq hquser1
```

## RAID0
```bash
apt-get install -y mdadm
mdadm --create /dev/md0 --level=0 --raid-devices=2 /dev/sdb /dev/sdc
mdadm --detail --scan | tee -a /etc/mdadm.conf
mkfs.ext4 /dev/md0
mkdir -p /raid && echo "/dev/md0 /raid ext4 defaults 0 0" >> /etc/fstab
mount -a && df -h /raid  # проверка
```

## NTP (chrony)
```bash
apt-get install -y chrony
# ISP: /etc/chrony.conf добавить: allow all; local stratum 5
# Клиент: server <IP-ISP> iburst
systemctl enable chronyd && systemctl restart chronyd
chronyc sources -v  # проверка (* = ОК)
```

## NFS
```bash
# Сервер (HQ-SRV):
apt-get install -y nfs-utils
mkdir -p /raid/nfs && chmod 777 /raid/nfs
echo "/raid/nfs 192.168.200.0/27(rw,sync,no_subtree_check,no_root_squash)" >> /etc/exports
exportfs -arv && systemctl enable nfs-server && systemctl start nfs-server

# Клиент autofs (HQ-CLI):
apt-get install -y autofs
# /etc/auto.master: /mnt/nfs /etc/auto.nfs --timeout=60
# /etc/auto.nfs:    shared -fstype=nfs4,rw 192.168.100.2:/raid/nfs
systemctl enable autofs && systemctl start autofs
```

## Docker
```bash
apt-get install -y docker-ce docker-compose
systemctl enable docker && systemctl start docker
docker load -i /media/cdrom/docker/site.tar
docker images
cd /opt/docker && docker-compose up -d
docker ps  # проверка
```

## nginx reverse proxy
```bash
apt-get install -y nginx
nginx -t && systemctl enable nginx && systemctl restart nginx
# htpasswd:
echo "WEB:$(openssl passwd -apr1 'P@ssw0rd')" > /etc/nginx/.htpasswd
```

## WireGuard VPN
```bash
apt-get install -y wireguard wireguard-tools
wg genkey | tee /etc/wireguard/private.key | wg pubkey > /etc/wireguard/public.key
# Настроить /etc/wireguard/wg0.conf
systemctl enable wg-quick@wg0 && systemctl start wg-quick@wg0
wg show  # проверка
```

## fail2ban
```bash
apt-get install -y fail2ban
# /etc/fail2ban/jail.local: [sshd] enabled=true port=2026 maxretry=3 bantime=60
systemctl enable fail2ban && systemctl start fail2ban
fail2ban-client status sshd  # проверка
```

## Часовой пояс
```bash
timedatectl set-timezone Europe/Moscow   # или Asia/Vladivostok и т.д.
timedatectl status  # проверка
```

---
[← README](README.md) | [FAQ →](FAQ.md)
