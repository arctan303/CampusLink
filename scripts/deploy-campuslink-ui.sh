#!/bin/sh
# Upgrade only the reviewed LuCI payload, retaining core and addon processes.
set -eu
action=${1:?backup/install/guard/confirm/rollback}
stage=${2:?staging directory}; backup=${3:?fresh backup directory}
case "$stage" in /tmp/campuslink-public-ip-20[0-9]*) ;; *) exit 2;; esac
case "$backup" in /root/campuslink-public-ip-20[0-9]*) ;; *) exit 2;; esac
umask 077
case "$action" in
backup)
    [ ! -e "$backup" ] && [ -f "$stage/luci-app-campuslink_0.4.1-1_all.ipk" ]
    mkdir "$backup"; cp "$0" "$backup/deploy.sh"
    cat /proc/sys/kernel/random/boot_id > "$backup/boot-id"
    for service in campuslink campuslink-mwan3; do
        ubus call service list "{\"name\":\"$service\"}" | jsonfilter -e "@[\"$service\"].instances.main.pid" > "$backup/$service.pid"
        [ -s "$backup/$service.pid" ]
    done
    sha256sum /etc/campuslink/config.json /etc/config/network /etc/config/firewall /etc/config/wireless /etc/config/dhcp /etc/config/mwan3 /etc/config/nikki /etc/config/uhttpd /etc/config/dropbear /etc/shadow /etc/campuslink-mwan3/config.json > "$backup/protected.sha256"
    sha256sum /var/run/mwan3/iface_state/wan* /var/run/mwan3track/wan*/ONLINE /var/run/mwan3track/wan*/OFFLINE > "$backup/native.sha256"
    (cd "$stage/payload"; find . -type f | sed 's|^./||') > "$backup/payload-files"
    : > "$backup/restore-files"
    while IFS= read -r name; do [ ! -f "/$name" ] || echo "$name" >> "$backup/restore-files"; done < "$backup/payload-files"
    for name in /usr/lib/opkg/info/luci-app-campuslink.*; do [ ! -f "$name" ] || echo "${name#/}" >> "$backup/restore-files"; done
    awk 'BEGIN {RS="";ORS="\n\n"} /^Package: luci-app-campuslink\n/ {print}' /usr/lib/opkg/status > "$backup/package-status"
    tar czf "$backup/restore.tar.gz" -C / -T "$backup/restore-files"
    sha256sum "$backup/restore.tar.gz"
    ;;
install)
    [ -f "$backup/restore.tar.gz" ] && [ ! -f "$backup/installed" ]
    sha256sum -c "$backup/protected.sha256" > "$backup/pre-install.log"
    setsid sh "$backup/deploy.sh" guard "$stage" "$backup" > "$backup/guard.log" 2>&1 < /dev/null &
    echo $! > "$backup/guard-pid"; kill -0 "$(cat "$backup/guard-pid")"
    opkg install "$stage/luci-app-campuslink_0.4.1-1_all.ipk" > "$backup/install.log" 2>&1
    touch "$backup/installed"; cat "$backup/install.log"
    ;;
guard)
    sleep 600
    [ -f "$backup/confirmed" ] || sh "$backup/deploy.sh" rollback "$stage" "$backup"
    ;;
confirm)
    [ -f "$backup/installed" ] && [ ! -f "$backup/rolled-back" ]
    sha256sum -c "$backup/protected.sha256" > "$backup/post-install.log"
    sha256sum -c "$backup/native.sha256" > "$backup/native-after.log"
    [ "$(cat /proc/sys/kernel/random/boot_id)" = "$(cat "$backup/boot-id")" ]
    for service in campuslink campuslink-mwan3; do
        pid=$(ubus call service list "{\"name\":\"$service\"}" | jsonfilter -e "@[\"$service\"].instances.main.pid")
        [ "$pid" = "$(cat "$backup/$service.pid")" ]
    done
    touch "$backup/confirmed"
    ;;
rollback)
    [ -f "$backup/restore.tar.gz" ]
    while IFS= read -r name; do rm -f "/$name"; done < "$backup/payload-files"
    rm -f /usr/lib/opkg/info/luci-app-campuslink.*
    tar xzf "$backup/restore.tar.gz" -C /
    awk 'BEGIN {RS="";ORS="\n\n"} !/^Package: luci-app-campuslink\n/ {print}' /usr/lib/opkg/status > "$backup/status.new"
    cat "$backup/package-status" >> "$backup/status.new"; cp "$backup/status.new" /usr/lib/opkg/status
    rm -f /tmp/luci-indexcache; /etc/init.d/rpcd restart; touch "$backup/rolled-back"
    ;;
*) exit 2;;
esac
