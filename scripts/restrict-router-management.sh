#!/bin/sh
# Device-specific LAN management binding with a ten-minute recovery window.
set -eu
B=${1:?new root-only backup directory required}
case "$B" in /root/campuslink-lan-management-*) ;; *) exit 2 ;; esac
[ ! -e "$B" ]
[ "$(uci -q get network.lan.ipaddr)" = '192.168.0.1' ]
[ "$(uci -q get uhttpd.main)" = 'uhttpd' ]
[ "$(uci -q get dropbear.main)" = 'dropbear' ]
[ "$(uci show uhttpd | grep -c '=uhttpd$')" -eq 1 ]
[ "$(uci show dropbear | grep -c '=dropbear$')" -eq 1 ]
[ -z "$(uci changes uhttpd)" ] && [ -z "$(uci changes dropbear)" ]
[ -z "$(uci -q get dropbear.main.DirectInterface || true)" ]
umask 077
mkdir -m 700 "$B"
cp -p /etc/config/uhttpd "$B/uhttpd.before"
cp -p /etc/config/dropbear "$B/dropbear.before"
cat /proc/sys/kernel/random/boot_id > "$B/boot-id"
sha256sum /etc/config/network /etc/config/firewall /etc/config/wireless \
    /etc/config/dhcp /etc/config/mwan3 /etc/config/nikki \
    /etc/campuslink/config.json > "$B/protected.sha256"
cat > "$B/rollback.sh" <<'SH'
#!/bin/sh
set -eu
B=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ "${1:-}" != '--force' ] && { [ -f "$B/confirmed" ] || [ -f "$B/restored" ]; }; then exit 0; fi
# Only these two management configs were changed; never restore network or Wi-Fi.
uci revert uhttpd
uci revert dropbear
cp -p "$B/uhttpd.before" /etc/config/uhttpd
cp -p "$B/dropbear.before" /etc/config/dropbear
/etc/init.d/uhttpd restart
/etc/init.d/dropbear restart
touch "$B/restored"
SH
cat > "$B/guard.sh" <<'SH'
#!/bin/sh
set -eu
B=$1
echo "$$" > "$B/guard.pid"
sleep 600
exec sh "$B/rollback.sh"
SH
sh -n "$B/rollback.sh"
sh -n "$B/guard.sh"
setsid sh "$B/guard.sh" "$B" </dev/null > "$B/guard.log" 2>&1 &
i=0
while [ ! -s "$B/guard.pid" ]; do
    i=$((i + 1))
    [ "$i" -lt 6 ]
    sleep 1
done
kill -0 "$(cat "$B/guard.pid")"
trap 'sh "$B/rollback.sh"' HUP INT TERM
uci -q delete uhttpd.main.listen_http
uci add_list uhttpd.main.listen_http='192.168.0.1:80'
uci -q delete uhttpd.main.listen_https
uci add_list uhttpd.main.listen_https='192.168.0.1:443'
# This installed network_get_ipaddrs_all returns empty for lan. DirectInterface
# resolves br-lan correctly and Dropbear binds the listening sockets to it.
uci -q delete dropbear.main.Interface || true
uci set dropbear.main.DirectInterface='lan'
uci commit uhttpd
uci commit dropbear
cp -p /etc/config/uhttpd "$B/uhttpd.after"
cp -p /etc/config/dropbear "$B/dropbear.after"
/etc/init.d/uhttpd restart > "$B/uhttpd-restart.log" 2>&1
/etc/init.d/dropbear restart > "$B/dropbear-restart.log" 2>&1
trap - HUP INT TERM
printf 'LAN bindings applied; confirm new LAN access before creating %s/confirmed.\n' "$B"
