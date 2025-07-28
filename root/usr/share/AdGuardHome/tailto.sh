#!/bin/sh
tail -n $1 "$2" > /var/run/AdG_tailtmp
cat /var/run/AdG_tailtmp > "$2"
rm /var/run/AdG_tailtmp