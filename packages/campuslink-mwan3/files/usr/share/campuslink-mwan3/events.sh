#!/bin/sh
# Mark selected physical events; the controller owns all native transitions.
case "$INTERFACE" in ''|[!a-zA-Z0-9_]*|*[!a-zA-Z0-9_.-]*) exit 0 ;; esac
[ "${#INTERFACE}" -le 64 ] || exit 0
case "$ACTION" in ifup|ifdown) ;; ifupdate) [ "$IFUPDATE_ADDRESSES" = 1 ] || exit 0 ;; *) exit 0 ;; esac
task_root=${CAMPUSLINK_MWAN3_RUNTIME:-/var/run/campuslink-mwan3}
task_system=${CAMPUSLINK_MWAN3_SYSTEM_ROOT:-}
[ -r "$task_root/active.json" ] || exit 0
task_selected=0
for task_name in $(jsonfilter -i "$task_root/active.json" -e '@.mappings[*].source_interface' -e '@.mappings[*].network_interface'); do
    [ "$task_name" = "$INTERFACE" ] && task_selected=1
done
[ "$task_selected" = 1 ] || exit 0
umask 077
mkdir -p "$task_root/events"
task_epoch=$(date +%s)
read task_uptime task_rest < "$task_system/proc/uptime"
printf '{"time":%s,"token":"%s:%s:%s"}\n' "$task_epoch" "$task_epoch" "$task_uptime" "$$" \
    > "$task_root/events/$INTERFACE.$$.new"
mv "$task_root/events/$INTERFACE.$$.new" "$task_root/events/$INTERFACE.json"
