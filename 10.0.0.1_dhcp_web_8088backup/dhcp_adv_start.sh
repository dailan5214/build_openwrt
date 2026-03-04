#!/bin/sh

WEB_ROOT="/data/dhcp_adv/www"
DATA_DIR="/data/dhcp_adv"
PID_FILE="/data/dhcp_adv/uhttpd.pid"

[ -f "$DATA_DIR/dhcp_adv.sh" ] || exit 1
[ -f "$DATA_DIR/index.html" ] || exit 1

mkdir -p "$WEB_ROOT/cgi-bin"
cp -f "$DATA_DIR/dhcp_adv.sh" "$WEB_ROOT/cgi-bin/dhcp_adv.sh"
cp -f "$DATA_DIR/index.html" "$WEB_ROOT/index.html"
chmod +x "$WEB_ROOT/cgi-bin/dhcp_adv.sh"

[ -f "$PID_FILE" ] && start-stop-daemon -K -p "$PID_FILE" >/dev/null 2>&1 || true
ps w | grep '[u]httpd' | grep '10.0.0.1:8088' >/dev/null 2>&1 && ps w | grep '[u]httpd' | grep '10.0.0.1:8088' | awk '{print $1}' | xargs -r kill >/dev/null 2>&1 || true

start-stop-daemon -S -b -m -p "$PID_FILE" -x /usr/sbin/uhttpd -- \
  -f -p 10.0.0.1:8088 \
  -h "$WEB_ROOT" \
  -x /cgi-bin \
  -i .sh=/bin/sh \
  -t 60 -T 30
