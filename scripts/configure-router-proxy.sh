#!/bin/sh
# Credential-free deployment of the already installed Nikki/Mihomo LAN proxy.
# Private input and backups must exist in the supplied, root-only directory.
# For the currently installed MetaCubeXD, also apply fix-nikki-panel-link.sh
# with its own panel backup; it preserves the native button's auto-login.
set -eu
B=${1:?root-only backup directory required}
case "$B" in /root/campuslink-proxy-mwan3-*) ;; *) exit 2 ;; esac
[ -f "$B/nikki" ] && [ -f "$B/subscription.yaml" ] && [ -s "$B/subscription-url" ]
[ -f "$B/guard.pid" ] && kill -0 "$(cat "$B/guard.pid")"
sha256sum -c "$B/unchanged.sha256" >/dev/null
[ "$(cat /proc/sys/kernel/random/boot_id)" = "$(cat "$B/boot-id")" ]
[ -z "$(uci changes nikki)" ] && [ -z "$(uci changes mwan3)" ]
[ -z "$(uci changes dhcp)" ]
[ -z "$(uci -q get mwan3.mihomo_outbound || true)" ]
[ -z "$(uci -q get mwan3.lan_balanced.fwmark || true)" ]
[ -z "$(uci -q get mwan3.lan_balanced.fwmask || true)" ]
[ -z "$(pidof mihomo || true)" ]

umask 077
cp /etc/config/dhcp "$B/dhcp"
uci -q get 'dhcp.@dnsmasq[0].dns_redirect' > "$B/dns-redirect" || :
cp -p /etc/init.d/nikki "$B/nikki-init"
# This installed release leaves children when its shell wrapper is stopped.
# Let procd own the core itself, so restart cannot leave older listeners alive.
sed -i 's/command \/bin\/sh -c "\$PROG /command \/bin\/sh -c "exec \$PROG /' /etc/init.d/nikki
sh -n /etc/init.d/nikki
cp "$B/subscription.yaml" /etc/nikki/subscriptions/subscription.yaml
cat > /etc/nikki/mixin.yaml <<'YAML'
routing-mark: 65536
bind-address: '*'
lan-allowed-ips:
  - 127.0.0.0/8
  - 192.168.0.0/24
authentication: []
tun:
  auto-route: false
  auto-detect-interface: false
  strict-route: false
nikki-rules:
  - IP-CIDR,127.0.0.0/8,DIRECT,no-resolve
  - IP-CIDR,10.0.0.0/8,DIRECT,no-resolve
  - IP-CIDR,172.16.0.0/12,DIRECT,no-resolve
  - IP-CIDR,192.168.0.0/16,DIRECT,no-resolve
  - IP-CIDR,1.1.1.1/32,DIRECT,no-resolve
  - DOMAIN-SUFFIX,lan,DIRECT
  - DOMAIN-SUFFIX,local,DIRECT
YAML
uci set nikki.config.enabled='1'
uci set nikki.config.profile='subscription:subscription'
uci set nikki.config.test_profile='1'
uci set nikki.subscription.name='Campus LAN proxy'
uci set "nikki.subscription.url=$(cat "$B/subscription-url")"
uci set nikki.subscription.user_agent='clash.meta'
uci set nikki.subscription.prefer='local'
uci set nikki.mixin.mixin_file_content='1'
uci set nikki.mixin.api_listen='192.168.0.1:9090'
# The native dashboard opens the LAN host. Bind only that host and require a
# strong controller secret; the proxy's allow-lan option does not guard its API.
P_API_SECRET=$(head -c 32 /dev/urandom | sha256sum | awk '{print $1}')
[ "${#P_API_SECRET}" -eq 64 ]
uci set "nikki.mixin.api_secret=$P_API_SECRET"
printf 'header = "Authorization: Bearer %s"\n' "$P_API_SECRET" > "$B/api.curl"
unset P_API_SECRET
uci set nikki.mixin.allow_lan='1'
uci set nikki.mixin.authentication='0'
uci set nikki.mixin.http_port='0'
uci set nikki.mixin.socks_port='0'
uci set nikki.mixin.mixed_port='7890'
uci set nikki.mixin.redir_port='7891'
uci set nikki.mixin.tproxy_port='7892'
uci set nikki.mixin.tun_enabled='0'
uci set nikki.mixin.ipv6='0'
uci set nikki.mixin.dns_enabled='1'
uci set nikki.mixin.dns_listen='0.0.0.0:1053'
uci set nikki.mixin.dns_ipv6='0'
uci -q delete nikki.mixin.outbound_interface || true
uci -q delete nikki.mixin.api_tls_listen || true
uci -q delete nikki.mixin.ui_url || true
uci set nikki.proxy.enabled='0'
uci set nikki.proxy.router_proxy='0'
uci set nikki.proxy.lan_proxy='1'
uci set nikki.proxy.tcp_mode='tproxy'
uci set nikki.proxy.udp_mode='tproxy'
uci set nikki.proxy.ipv4_dns_hijack='1'
uci set nikki.proxy.ipv6_dns_hijack='0'
uci set nikki.proxy.ipv4_proxy='1'
uci set nikki.proxy.ipv6_proxy='0'
uci -q delete nikki.proxy.lan_inbound_interface || true
uci add_list nikki.proxy.lan_inbound_interface='lan'
uci add_list nikki.proxy.reserved_ip='1.1.1.1/32'
uci set nikki.log.clear_at_stop='0'
uci set nikki.log.scheduled_clear='0'
uci commit nikki
chmod 600 /etc/config/nikki /etc/nikki/mixin.yaml /etc/nikki/subscriptions/subscription.yaml

uci set mwan3.mihomo_outbound='rule'
uci set mwan3.mihomo_outbound.enabled='1'
uci set mwan3.mihomo_outbound.family='ipv4'
uci set mwan3.mihomo_outbound.proto='all'
uci set mwan3.mihomo_outbound.fwmark='0x10000'
uci set mwan3.mihomo_outbound.fwmask='0x10000'
uci set mwan3.mihomo_outbound.sticky='0'
uci set mwan3.mihomo_outbound.use_policy='balanced'
# TPROXY marks the intercepted client half before mwan3's prerouting hook.
# Only unclaimed LAN packets and actual proxy outbound sockets enter balanced.
uci set mwan3.lan_balanced.fwmark='0x0'
uci set mwan3.lan_balanced.fwmask='0x80'
uci commit mwan3
/etc/init.d/mwan3 reload > "$B/mwan3-reload.log" 2>&1
# Kwrt's earlier dnsmasq NAT redirect would otherwise shadow Nikki's LAN DNS.
uci set 'dhcp.@dnsmasq[0].dns_redirect=0'
uci commit dhcp
/etc/init.d/dnsmasq reload > "$B/dnsmasq-reload.log" 2>&1
/etc/init.d/nikki enable
/etc/init.d/nikki start > "$B/nikki-start.log" 2>&1
printf 'Configured explicit LAN proxy; transparent interception still disabled.\n'
# After profile/node/TCP/UDP validation, enable nikki.proxy.enabled and restart
# only this service. Do not reboot the router or reload its wireless/network.
