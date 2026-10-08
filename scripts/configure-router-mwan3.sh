#!/bin/sh
set -eu
B=/root/campuslink-mwan3-20261008-1650
[ ! -e "$B" ] || { echo "Backup directory already exists"; exit 1; }
command -v setsid >/dev/null 2>&1 || { echo "setsid is required for the recovery timer"; exit 1; }
umask 077
mkdir -p "$B/candidate"
cp /etc/config/mwan3 "$B/mwan3.before"
cp /etc/config/firewall "$B/firewall.before"
cp /etc/config/network "$B/network.before"
uci -q get firewall.@defaults[0].flow_offloading > "$B/software.before" || :
uci -q get firewall.@defaults[0].flow_offloading_hw > "$B/hardware.before" || :
if /etc/init.d/mwan3 enabled; then echo 1 > "$B/enabled.before"; else echo 0 > "$B/enabled.before"; fi
cat > "$B/rollback.sh" <<'ROLLBACK'
#!/bin/sh
B=/root/campuslink-mwan3-20261008-1650
[ "${1:-}" = "--force" ] || [ ! -f "$B/confirmed" ] || exit 0
logger -t campuslink-mwan-rollback "Restoring pre-mwan3 configuration"
/etc/init.d/mwan3 stop
/etc/init.d/mwan3 disable
nft delete table inet campuslink_mwan_test 2>/dev/null || :
cp "$B/mwan3.before" /etc/config/mwan3
for item in software hardware; do
    case "$item" in software) key=flow_offloading ;; hardware) key=flow_offloading_hw ;; esac
    value=$(cat "$B/$item.before")
    if [ -n "$value" ]; then uci set "firewall.@defaults[0].$key=$value"; else uci -q delete "firewall.@defaults[0].$key" || :; fi
done
uci commit firewall
/etc/init.d/firewall reload
if [ "$(cat "$B/enabled.before")" = 1 ]; then /etc/init.d/mwan3 enable; /etc/init.d/mwan3 start; fi
date > "$B/rolled-back"
ROLLBACK
chmod 700 "$B/rollback.sh"
setsid sh -c 'echo $$ > /root/campuslink-mwan3-20261008-1650/watchdog.pid; sleep 1200; exec sh /root/campuslink-mwan3-20261008-1650/rollback.sh' > "$B/watchdog.log" 2>&1 < /dev/null &
sleep 1
kill -0 "$(cat "$B/watchdog.pid")"
trap 'rc=$?; if [ "$rc" -ne 0 ]; then sh "$B/rollback.sh" --force; fi' EXIT
cat > "$B/candidate/mwan3" <<'GLOBAL'
config globals 'globals'
    option mmx_mask '0x3F00'
    list rt_table_lookup '101'
    list rt_table_lookup '102'
    list rt_table_lookup '103'
    list rt_table_lookup '104'
GLOBAL
for n in 1 2 3 4; do
    cat >> "$B/candidate/mwan3" <<IFACE

config interface 'wan$n'
    option enabled '1'
    option family 'ipv4'
    option initial_state 'offline'
    option track_method 'ping'
    list track_ip '223.5.5.5'
    list track_ip '119.29.29.29'
    option reliability '1'
    option count '1'
    option timeout '2'
    option interval '5'
    option failure_interval '3'
    option recovery_interval '3'
    option down '3'
    option up '3'
    option check_quality '0'

config member 'wan${n}_m1_w1'
    option interface 'wan$n'
    option metric '1'
    option weight '1'

config policy 'wan${n}_only'
    list use_member 'wan${n}_m1_w1'
    option last_resort 'unreachable'
IFACE
done
cat >> "$B/candidate/mwan3" <<'POLICY'

config policy 'balanced'
    list use_member 'wan1_m1_w1'
    list use_member 'wan2_m1_w1'
    list use_member 'wan3_m1_w1'
    list use_member 'wan4_m1_w1'
    option last_resort 'default'

config rule 'lan_balanced'
    option enabled '1'
    option family 'ipv4'
    option proto 'all'
    option src_iface 'lan'
    option src_ip '192.168.0.0/24'
    option dest_ip '0.0.0.0/0'
    option sticky '0'
    option use_policy 'balanced'
POLICY
uci -c "$B/candidate" show mwan3 > "$B/candidate-uci.txt"
cp "$B/candidate/mwan3" /etc/config/mwan3
uci set firewall.@defaults[0].flow_offloading='0'
uci set firewall.@defaults[0].flow_offloading_hw='0'
uci commit firewall
fw4 check
/etc/init.d/firewall reload
/etc/init.d/mwan3 enable
/etc/init.d/mwan3 start
cp /etc/config/mwan3 "$B/mwan3.after"
cp /etc/config/firewall "$B/firewall.after"
date > "$B/deployed"
echo "DEPLOYED backup=$B watchdog=$(cat "$B/watchdog.pid")"
