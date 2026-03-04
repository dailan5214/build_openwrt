#!/bin/sh
ps w | grep '[u]httpd' | grep '10.0.0.1:8088' >/dev/null 2>&1 || /data/dhcp_adv/start.sh
