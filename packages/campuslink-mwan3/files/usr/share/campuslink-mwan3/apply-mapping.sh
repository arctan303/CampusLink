#!/bin/sh
# Only explicit mappings may change eligibility. No netifd or UCI writes.
set -e
target=${1:-}; desired=${2:-}; source_iface=${3:-}; target_network=${4:-}
device=${5:-}; source_ip=${6:-}; source_token=${7:-}; target_token=${8:-}; generation=${9:-}
task_root=${CAMPUSLINK_MWAN3_RUNTIME:-/var/run/campuslink-mwan3}
task_config=${CAMPUSLINK_MWAN3_CONFIG:-/etc/campuslink-mwan3/config.json}
task_system=${CAMPUSLINK_MWAN3_SYSTEM_ROOT:-}
for task_name in "$target" "$source_iface" "$target_network"; do
    case "$task_name" in ''|[!a-zA-Z0-9_]*|*[!a-zA-Z0-9_.-]*) exit 2 ;; esac
    [ "${#task_name}" -le 64 ] || exit 2
done
case "$desired" in online|offline) ;; *) exit 2 ;; esac
case "$device" in ''|*[!a-zA-Z0-9_.:-]*) exit 2 ;; esac
case "$source_ip" in ''|*[!0-9.-]*) exit 2 ;; esac
for task_token in "$source_token" "$target_token"; do
    case "$task_token" in ''|*[!a-zA-Z0-9_.:-]*) exit 2 ;; esac
done
case "$generation" in ''|*[!0-9]*) exit 2 ;; esac
set +e
. "$task_system/lib/functions.sh"
. "$task_system/lib/functions/network.sh"
. "$task_system/lib/mwan3/mwan3.sh"
initscript=$task_system/etc/init.d/mwan3
. "$task_system/lib/functions/procd.sh"
procd_lock
flock -n 1000 || exit 6
set -e
nft list chain inet mwan3 mwan3_prerouting >/dev/null 2>&1 || exit 3
[ "$(uci -q get "mwan3.$target")" = interface ] || exit 3
[ "$(uci -q get "mwan3.$target.enabled")" = 1 ] || exit 3
family=$(uci -q get "mwan3.$target.family") || family=ipv4
[ "${family:-ipv4}" = ipv4 ] || exit 3
[ -z "$(uci -q get "mwan3.$target.track_ip")" ] || exit 3
[ "$(uci -q get "mwan3.$target.track_gateway")" != 1 ] || exit 3
[ "$(uci -q get "mwan3.$target.initial_state")" = offline ] || exit 3
pid=$(cat "$task_system/var/run/mwan3track/$target/PID" 2>/dev/null) || pid=
case "$pid" in ''|*[!0-9]*) ;; *)
    if [ -r "$task_system/proc/$pid/cmdline" ] && grep -q mwan3track "$task_system/proc/$pid/cmdline"; then exit 3; fi ;;
esac
[ "$(jsonfilter -i "$task_root/active.json" -e '@.generation')" = "$generation" ] || exit 4
mapping_expr="@.mappings[@.mwan3_interface=\"$target\"]"
[ "$(jsonfilter -i "$task_config" -e '@.generation')" = "$generation" ] || exit 4
[ "$(jsonfilter -i "$task_config" -e '@.enabled')" = true ] || exit 4
[ "$(jsonfilter -i "$task_config" -e "${mapping_expr}.enabled")" = true ] || exit 4
[ "$(jsonfilter -i "$task_config" -e "${mapping_expr}.source_interface")" = "$source_iface" ] || exit 4
[ "$(jsonfilter -i "$task_root/active.json" -e "${mapping_expr}.source_interface")" = "$source_iface" ] || exit 4
[ "$(jsonfilter -i "$task_root/active.json" -e "${mapping_expr}.network_interface")" = "$target_network" ] || exit 4
registered_binding=$(jsonfilter -i "$task_root/active.json" -e "${mapping_expr}.verified_binding") || registered_binding=
live_source_token=$(jsonfilter -i "$task_root/events/$source_iface.json" -e '@.token' 2>/dev/null) || live_source_token=-
live_target_token=$(jsonfilter -i "$task_root/events/$target_network.json" -e '@.token' 2>/dev/null) || live_target_token=-
[ "${live_source_token:--}" = "$source_token" ] && [ "${live_target_token:--}" = "$target_token" ] || exit 4
resolved_network=$target
if type mwan3_get_true_iface >/dev/null 2>&1; then mwan3_get_true_iface resolved_network "$target"; fi
[ "$resolved_network" = "$target_network" ] || exit 4
target_frame=$(ubus -S call "network.interface.$target_network" status) || exit 4
source_frame=$(ubus -S call "network.interface.$source_iface" status) || exit 4
target_up=$(jsonfilter -s "$target_frame" -e '@.up') || target_up=false
source_up=$(jsonfilter -s "$source_frame" -e '@.up') || source_up=false
live_device=$(jsonfilter -s "$target_frame" -e '@.l3_device') || live_device=
live_ip=$(jsonfilter -s "$target_frame" -e '@["ipv4-address"][0].address') || live_ip=
source_device=$(jsonfilter -s "$source_frame" -e '@.l3_device') || source_device=
live_source_ip=$(jsonfilter -s "$source_frame" -e '@["ipv4-address"][0].address') || live_source_ip=
if [ "$target_up" = true ]; then
    [ "${live_device:--}/${live_ip:--}" = "$device/$source_ip" ] || exit 4
    if [ "$source_up" = true ]; then [ "${source_device:--}/${live_source_ip:--}" = "$device/$source_ip" ] || exit 4; fi
elif [ "$source_iface" = "$target_network" ] && [ "$source_up" = true ]; then
    exit 4
fi
if [ "$desired" = online ]; then
    [ "$target_up" = true ] && [ "$source_up" = true ] || exit 4
    [ "$live_device" = "$device" ] && [ "$live_ip" = "$source_ip" ] || exit 4
    [ "$source_device" = "$device" ] && [ "$live_source_ip" = "$source_ip" ] || exit 4
    [ "$(cat "$task_system/var/run/mwan3track/$target/ROUTE_STATUS" 2>/dev/null || :)" != down ] || exit 4
elif [ "$source_iface" != "$target_network" ]; then
    [ "$target_up" = true ] && [ "$live_device/$live_ip" = "$device/$source_ip" ] || exit 4
    if [ "$source_up" = true ]; then
        [ "$source_device/$live_source_ip" = "$device/$source_ip" ] || exit 4
    else
        [ "$registered_binding" = "$device/$source_ip" ] || exit 4
    fi
fi
umask 077
mkdir -p "$task_system/var/run/mwan3track/$target"
printf '%s\n' "$desired" > "$task_system/var/run/mwan3track/$target/STATUS"
read task_uptime task_rest < "$task_system/proc/uptime"
task_seconds=${task_uptime%.*}
if [ "$desired" = online ]; then
    echo "$task_seconds" > "$task_system/var/run/mwan3track/$target/ONLINE"
    echo 0 > "$task_system/var/run/mwan3track/$target/OFFLINE"
    task_action=connected
else
    echo 0 > "$task_system/var/run/mwan3track/$target/ONLINE"
    echo "$task_seconds" > "$task_system/var/run/mwan3track/$target/OFFLINE"
    task_action=disconnected
fi
env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin MWAN3_STARTUP=init ACTION="$task_action" \
    INTERFACE="$target" DEVICE="$device" CAMPUSLINK_MWAN3_SYSTEM_ROOT="$task_system" \
    sh "$task_system/etc/hotplug.d/iface/25-mwan3"
[ "$(cat "$task_system/var/run/mwan3/iface_state/$target")" = "$desired" ] || exit 5
printf '%s %s\n' "$target" "$desired"
