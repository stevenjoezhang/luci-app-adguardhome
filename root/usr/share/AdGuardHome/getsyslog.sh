#!/bin/sh
PATH="/usr/sbin:/usr/bin:/sbin:/bin"
logread -e AdGuardHome > /tmp/AdGuardHome.log
logread -e AdGuardHome -f >> /tmp/AdGuardHome.log &
pid=$!
echo "1">/var/run/AdG_syslog
while true
do
	sleep 12
	watchdog=$(cat /var/run/AdG_syslog)
	if [ "$watchdog"x == "0"x ]; then
		kill $pid
		rm /tmp/AdGuardHome.log
		rm /var/run/AdG_syslog
		exit 0
	else
		echo "0">/var/run/AdG_syslog
	fi
done