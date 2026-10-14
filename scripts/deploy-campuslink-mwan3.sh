#!/bin/sh
# Scoped upgrade of the existing four-line router; no core/network restart.
set -eu
action=${1:?backup/install/guard/rollback/confirm}
stage=${2:?isolated staging directory}
backup=${3:?fresh backup directory}
case "$stage" in /tmp/campuslink-mwan3-20[0-9]*) ;; *) exit 2;; esac
case "$backup" in /root/campuslink-mwan3-20[0-9]*) ;; *) exit 2;; esac
umask 077
case "$action" in
backup)
    [ ! -e "$backup" ]
    [ -f "$stage/candidate/usr/share/campuslink-mwan3/mappings.uc" ]
    mkdir "$backup"
    cp "$0" "$backup/deploy.sh"
    cat /proc/sys/kernel/random/boot_id > "$backup/boot-id"
    ubus call service list '{"name":"campuslink"}' | jsonfilter -e '@.campuslink.instances.main.pid' > "$backup/core-pid"
    sha256sum /etc/campuslink/config.json /etc/config/network /etc/config/firewall /etc/config/wireless /etc/config/dhcp /etc/config/mwan3 /etc/config/nikki /etc/config/uhttpd /etc/config/dropbear /etc/shadow > "$backup/protected.sha256"
    (cd "$stage/candidate"; find . -type f | sed 's|^./||') > "$backup/payload-files"
    : > "$backup/restore-files"
    while IFS= read -r name; do [ ! -f "/$name" ] || echo "$name" >> "$backup/restore-files"; done < "$backup/payload-files"
    if [ -f /etc/campuslink-mwan3/config.json ]; then echo etc/campuslink-mwan3/config.json >> "$backup/restore-files"; fi
    for name in /usr/lib/opkg/info/luci-app-campuslink.* /usr/lib/opkg/info/campuslink-mwan3.*; do
        [ ! -f "$name" ] || echo "${name#/}" >> "$backup/restore-files"
    done
    if [ -d /var/run/campuslink-mwan3 ]; then find /var/run/campuslink-mwan3 -type f | sed 's|^/||' >> "$backup/restore-files"; fi
    awk 'BEGIN {RS="";ORS="\n\n"} /^Package: (luci-app-campuslink|campuslink-mwan3)\n/ {print}' /usr/lib/opkg/status > "$backup/package-status"
    /etc/init.d/campuslink-mwan3 enabled && touch "$backup/was-enabled"
    tar czf "$backup/restore.tar.gz" -C / -T "$backup/restore-files"
    sha256sum "$backup/restore.tar.gz"
    ;;
install)
    [ -f "$backup/restore.tar.gz" ] && [ ! -e "$backup/installed" ]
    sha256sum -c "$backup/protected.sha256" > "$backup/pre-install-hashes.log"
    [ "$(cat /proc/sys/kernel/random/boot_id)" = "$(cat "$backup/boot-id")" ]
    command -v setsid > /dev/null
    setsid sh "$backup/deploy.sh" guard "$stage" "$backup" > "$backup/guard.log" 2>&1 < /dev/null &
    echo $! > "$backup/guard-pid"
    kill -0 "$(cat "$backup/guard-pid")"
    /etc/init.d/campuslink-mwan3 stop
    mkdir -p /etc/campuslink-mwan3
    cp "$stage/production-config.json" /etc/campuslink-mwan3/config.json
    chmod 700 /etc/campuslink-mwan3
    chmod 600 /etc/campuslink-mwan3/config.json
    opkg install "$stage/campuslink-mwan3_0.2.0-1_all.ipk" "$stage/luci-app-campuslink_0.4.0-1_all.ipk" > "$backup/install.log" 2>&1
    /etc/init.d/campuslink-mwan3 enable
    /etc/init.d/campuslink-mwan3 start
    touch "$backup/installed"
    cat "$backup/install.log"
    ;;
guard)
    sleep 900
    [ -f "$backup/confirmed" ] || sh "$backup/deploy.sh" rollback "$stage" "$backup"
    ;;
rollback)
    [ -f "$backup/restore.tar.gz" ]
    /etc/init.d/campuslink-mwan3 stop || true
    /etc/init.d/campuslink-mwan3 disable || true
    while IFS= read -r name; do rm -f "/$name"; done < "$backup/payload-files"
    rm -f /etc/campuslink-mwan3/config.json /var/run/campuslink-mwan3/active.json /var/run/campuslink-mwan3/status.json
    rm -f /usr/lib/opkg/info/luci-app-campuslink.* /usr/lib/opkg/info/campuslink-mwan3.*
    tar xzf "$backup/restore.tar.gz" -C /
    awk 'BEGIN {RS="";ORS="\n\n"} !/^Package: (luci-app-campuslink|campuslink-mwan3)\n/ {print}' /usr/lib/opkg/status > "$backup/status.new"
    cat "$backup/package-status" >> "$backup/status.new"
    cp "$backup/status.new" /usr/lib/opkg/status
    rm -f /tmp/luci-indexcache
    /etc/init.d/rpcd reload
    if [ -f "$backup/was-enabled" ]; then /etc/init.d/campuslink-mwan3 enable; fi
    /etc/init.d/campuslink-mwan3 start
    touch "$backup/rolled-back"
    ;;
confirm)
    [ -f "$backup/installed" ] && [ ! -f "$backup/rolled-back" ]
    sha256sum -c "$backup/protected.sha256" > "$backup/post-install-hashes.log"
    [ "$(cat /proc/sys/kernel/random/boot_id)" = "$(cat "$backup/boot-id")" ]
    [ "$(ubus call service list '{"name":"campuslink"}' | jsonfilter -e '@.campuslink.instances.main.pid')" = "$(cat "$backup/core-pid")" ]
    touch "$backup/confirmed"
    ;;
*) exit 2;;
esac
