#!/bin/sh
# Selectively undo PROXY-01; the original CampusLink and wireless settings stay.
set -eu
B=/root/campuslink-proxy-mwan3-20261008
[ "${1:-}" = --force ] || [ ! -e "$B/confirmed" ] || exit 0
/etc/init.d/nikki stop > "$B/rollback-stop.log" 2>&1 || true
[ ! -f "$B/nikki-init" ] || cp -p "$B/nikki-init" /etc/init.d/nikki
cp "$B/nikki" /etc/config/nikki
cp "$B/mixin.yaml" /etc/nikki/mixin.yaml
uci -q revert nikki || true
uci -q delete mwan3.mihomo_outbound || true
uci -q delete mwan3.lan_balanced.fwmark || true
uci -q delete mwan3.lan_balanced.fwmask || true
uci commit mwan3
/etc/init.d/mwan3 reload > "$B/rollback-mwan3.log" 2>&1
if [ -f "$B/dns-redirect" ]; then
    if [ -s "$B/dns-redirect" ]; then
        uci set "dhcp.@dnsmasq[0].dns_redirect=$(cat "$B/dns-redirect")"
    else
        uci -q delete 'dhcp.@dnsmasq[0].dns_redirect' || true
    fi
    uci commit dhcp
    /etc/init.d/dnsmasq reload > "$B/rollback-dnsmasq.log" 2>&1
fi
if [ "$(cat "$B/nikki-enabled")" = 1 ]; then
    /etc/init.d/nikki enable
else
    /etc/init.d/nikki disable
fi
if [ "$(uci -q get nikki.config.enabled || echo 0)" = 1 ]; then
    /etc/init.d/nikki start > "$B/rollback-start.log" 2>&1
fi
date > "$B/rolled-back"
printf 'Proxy rollback completed.\n'
