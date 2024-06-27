#!/bin/bash
sudo apt update
sudo apt -y upgrade
sudo apt -y install dnscrypt-proxy wireguard wireguard-tools net-tools git python3-pip gunicorn fail2ban
sysctl -w net.ipv6.conf.all.disable_ipv6=1
sudo sed -i '/IPV6=/c\IPV6=no' /etc/default/ufw
sudo ufw allow 22/tcp
sudo ufw allow 443/udp
sudo ufw allow in on wg0 from 192.168.17.0/24
sudo ufw --force enable
jail="[DEFAULT]
ignoreip = 127.0.0.1/8
banaction = ufw
bantime = 48h
findtime = 24h

[ssh]
enabled  = true
port     = ssh
filter   = sshd
logpath  = /var/log/auth.log
maxretry = 2"
echo "$jail" > /etc/fail2ban/jail.local
mkdir /etc/wireguard
cd /etc/wireguard
wg genkey | tee privatekey | wg pubkey > publickey
read -r privatekey < privatekey
echo $privatekey
wg="[Interface]
Address = 192.168.17.254/24
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -t nat -A POSTROUTING -o ens3 -j MASQUERADE; iptables -A PREROUTING -t nat -i %i -p udp --dport 53 -j DNAT --to-destination 127.0.2.1:53
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -t nat -D POSTROUTING -o ens3 -j MASQUERADE; iptables -D PREROUTING -t nat -i %i -p udp --dport 53 -j DNAT --to-destination 127.0.2.1:53
ListenPort = 443
PrivateKey = $privatekey"
echo "$wg" > /etc/wireguard/wg0.conf
sudo systemctl enable wg-quick@wg0
sudo wg-quick up wg0
git clone -b v3.0.6.2 https://github.com/donaldzou/WGDashboard.git wgdashboard
sudo chmod +x /etc/wireguard/wgdashboard/src/wgd.sh
pip install --ignore-installed -r /etc/wireguard/wgdashboard/src/requirements.txt
cd /etc/wireguard/wgdashboard/src/
./wgd.sh install
./wgd.sh start
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
echo "net.ipv4.conf.wg0.route_localnet=1" >> /etc/sysctl.conf
rm /etc/resolv.conf
echo "nameserver 127.0.2.1" > /etc/resolv.conf
sed -i 's/dns-nameservers.*/dns-nameservers 127.0.2.1/g' /etc/network/interfaces
sed -i 's/peer_global_dns.*/peer_global_dns = 192.168.17.254/g' /etc/wireguard/wgdashboard/src/wg-dashboard.ini
service="[Unit]
After=netword.service

[Service]
WorkingDirectory=/etc/wireguard/wgdashboard/src
ExecStart=/usr/bin/python3 /etc/wireguard/wgdashboard/src/dashboard.py
Restart=always


[Install]
WantedBy=default.target"
echo "$service" > /etc/systemd/system/wg-dashboard.service
sudo chmod 664 /etc/systemd/system/wg-dashboard.service
sudo systemctl daemon-reload
sudo systemctl enable wg-dashboard.service
sudo systemctl start wg-dashboard.service
reboot now
