#!/bin/sh
# Legacy 0.1.0 deployment on the verified TR3000; restore only tracking keys.
set -eu
B=/root/campuslink-mwan3-link-20261008
S=/tmp/campuslink-mwan3-candidate
[ ! -e "$S/usr/share/campuslink-mwan3/mappings.uc" ] || { echo 'Legacy deploy cannot install configurable addon; use the mapping upgrade workflow'; exit 1; }
[ ! -e "$B" ] || { echo 'Backup already exists'; exit 1; }
for target in /etc/init.d/campuslink-mwan3 /etc/hotplug.d/iface/24-campuslink-mwan3 /usr/share/campuslink-mwan3; do
    [ ! -e "$target" ] || { echo "Existing installation: $target"; exit 1; }
done
[ -z "$(uci changes mwan3)" ] || { echo 'Pending mwan3 changes'; exit 1; }
[ "$(uci -q get firewall.@defaults[0].flow_offloading)" = 0 ] || exit 1
umask 077
mkdir "$B"
cp /etc/config/mwan3 "$B/mwan3"
cp /etc/config/network "$B/network.before"
cp /etc/config/firewall "$B/firewall.before"
sha256sum /etc/campuslink/config.json > "$B/campuslink-config.sha256"
cat > "$B/rollback.sh" <<'ROLLBACK'
#!/bin/sh
set -eu
B=/root/campuslink-mwan3-link-20261008
[ "${1:-}" = --force ] || [ ! -f "$B/confirmed" ] || exit 0
if [ -x /etc/init.d/campuslink-mwan3 ]; then
    /etc/init.d/campuslink-mwan3 stop
    /etc/init.d/campuslink-mwan3 disable
fi
rm -f /etc/hotplug.d/iface/24-campuslink-mwan3
for n in 1 2 3 4; do
    for key in initial_state track_method track_gateway track_ip; do
        path="mwan3.wan$n.$key"
        uci -q delete "$path" || :
        value=$(uci -c "$B" -q get "$path") || value=
        if [ "$key" = track_ip ]; then
            for ip in $value; do uci add_list "$path=$ip"; done
        elif [ -n "$value" ]; then uci set "$path=$value"; fi
    done
done
uci commit mwan3
/etc/init.d/mwan3 reload
if [ -f "$B/wan4-test-down" ]; then ifup wan4; fi
date > "$B/rolled-back"
ROLLBACK
cat > "$B/guard.sh" <<'GUARD'
#!/bin/sh
B=/root/campuslink-mwan3-link-20261008
echo $$ > "$B/guard.pid"
sleep 1800
exec sh "$B/rollback.sh"
GUARD
chmod 700 "$B/rollback.sh" "$B/guard.sh"
setsid sh "$B/guard.sh" > "$B/guard.log" 2>&1 < /dev/null &
sleep 1
kill -0 "$(cat "$B/guard.pid")"
trap 'rc=$?; if [ "$rc" -ne 0 ]; then sh "$B/rollback.sh" --force; fi' EXIT
mkdir /usr/share/campuslink-mwan3
cp "$S"/usr/share/campuslink-mwan3/* /usr/share/campuslink-mwan3/
cp "$S/etc/init.d/campuslink-mwan3" /etc/init.d/campuslink-mwan3
cp "$S/etc/hotplug.d/iface/24-campuslink-mwan3" /etc/hotplug.d/iface/24-campuslink-mwan3
chmod 755 /etc/init.d/campuslink-mwan3 /usr/share/campuslink-mwan3/apply.sh
for n in 1 2 3 4; do
    uci -q delete "mwan3.wan$n.track_ip" || :
    uci -q delete "mwan3.wan$n.track_method" || :
    uci set "mwan3.wan$n.track_gateway=0"
    uci set "mwan3.wan$n.initial_state=offline"
done
uci commit mwan3
/etc/init.d/mwan3 reload
ucode /usr/share/campuslink-mwan3/daemon.uc --once
date > "$B/deployed"
echo "DEPLOYED with service not yet enabled; backup=$B"
