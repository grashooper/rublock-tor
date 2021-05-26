#!/bin/sh

echo Check update
opkg update && opkg upgrade

# Если используется TOR с флэшки
echo Install packages
opkg install tor tor-geoip lua

echo Make directories
mkdir -p /opt/lib/lua /opt/etc/runblock

echo Download scripts
wget -O /opt/lib/lua/ltn12.lua https://raw.githubusercontent.com/grashooper/rublock-tor/master/opt/lib/lua/ltn12.lua
wget -O /opt/bin/rublupdate.lua https://raw.githubusercontent.com/grashooper/rublock-tor/master/opt/bin/rublupdate.lua
wget -O /opt/bin/rublock.sh https://raw.githubusercontent.com/grashooper/rublock-tor/master/opt/bin/rublock.sh

echo Load ipset modules
modprobe ip_set_hash_net
modprobe xt_set
ipset -N rublack-dns nethash

echo Execute scripts
chmod +x /opt/bin/rublupdate.lua /opt/bin/rublock.sh
rublock.sh

echo Make config tor
cat /dev/null > /opt/etc/tor/torrc

cat >> /opt/etc/tor/torrc << 'EOF'
User admin
PidFile /opt/var/run/tor.pid
DataDirectory /opt/var/lib/tor
ExcludeExitNodes {RU},{UA},{AM},{KG}
StrictNodes 1
SocksPort 127.0.0.1:9050 # Локальный Socks прокси
VirtualAddrNetwork 10.254.0.0/16 # Виртуальные адреса для .onion ресурсов
AutomapHostsOnResolve 1
TransPort 192.168.1.1:9040 # Адрес LAN интерфейса
TransPort 127.0.0.1:9040
DNSPort 127.0.0.1:9053
EOF

echo Parse lan ip
sed -i 's/192.168.1.1/'"$(nvram get lan_ipaddr)"'/g' /opt/etc/tor/torrc

echo Parse user
sed -i 's/admin/'"$USER"'/g' /opt/etc/tor/torrc

echo Add ipset module
cd /etc/storage/
sed -i '$a' start_script.sh
sed -i '$a### Example - load ipset modules' start_script.sh
sed -i '$amodprobe ip_set_hash_net' start_script.sh
sed -i '$amodprobe xt_set' start_script.sh

echo Make config iptables
cat /dev/null > /opt/bin/update_iptables.sh

cat >> /opt/bin/update_iptables.sh << 'EOF'
#!/bin/sh

case "$1" in
start|update)
        # add iptables custom rules
        echo "firewall started"
        [ -d '/opt/etc/runblock' ] || exit 0
        # Create new rublack-dns ipset and fill it with IPs from list
        if [ ! -z "$(ipset --swap rublack-dns rublack-dns 2>&1 | grep 'given name does not exist')" ] ; then
                ipset -N rublack-dns nethash
                for IP in $(cat /opt/etc/runblock/runblock.ipset) ; do
                        ipset -A rublack-dns $IP
                done
        fi
        iptables -t nat -I PREROUTING -i br0 -p tcp -m set --match-set rublack-dns dst -j REDIRECT --to-ports 9040
                ;;
stop)
        # delete iptables custom rules
        echo "firewall stopped"
        ;;
*)
        echo "Usage: $0 {start|stop|update}"
        exit 1
        ;;
esac
EOF

echo Add entries to dnsmasq
cd /etc/storage/dnsmasq/
sed -i '$a' dnsmasq.conf
sed -i '$a### Tor' dnsmasq.conf
sed -i '$aserver=/onion/127.0.0.1#9053' dnsmasq.conf
sed -i '$aipset=/onion/rublack-dns' dnsmasq.conf
sed -i '$aconf-file=/opt/etc/runblock/runblock.dnsmasq' dnsmasq.conf

echo Add crontab tasks
cat >> /etc/storage/cron/crontabs/$USER << 'EOF'
0 5 * * * /opt/bin/rublock.sh
EOF

echo Reboot
reboot
