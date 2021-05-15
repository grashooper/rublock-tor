#!/bin/sh

echo Download Lists 
wget -q -O /opt/etc/rublock/rublock.dnsmasq https://raw.githubusercontent.com/grashooper/rublock-tor/master/opt/bin/urlblock.txt
wget -q -O /opt/etc/rublock/rublock.ips https://raw.githubusercontent.com/grashooper/rublock-tor/master/opt/bin/ipblock.txt

echo Generation Block List
cd /opt/etc/runblock
sed -i 's/.*/ipset=\/&\/rublack-dns/' runblock.dnsmasq

echo Add ip
ipset flush rublack-dns

for IP in $(cat /opt/etc/runblock/runblock.ipset) ; do
ipset -A rublack-dns $IP
done

echo Restart dnsmasq
killall -q dnsmasq
/usr/sbin/dnsmasq
