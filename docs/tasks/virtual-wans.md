# 四个虚拟 WAN

目标：在 eth0 上建立四个可持久化的独立 macvlan / DHCP 接口，为两账户 × 两种方式的校园网管理包准备出口。

依据：REQ-001 / AC-001–003；用户明确要求先完成四个虚拟网口。

depends_on：固件升级后的 25.12-SNAPSHOT 10.08.2026、内核 6.12.108、eth0 DHCP 正常、macvlan 已加载。上述前置成果已回读。

范围：vwan1–vwan4 对应 wan1–wan4，MAC 02:af:ca:f2:99:71–74，独立 DHCP 与路由表 101–104；加入现有 WAN 区域。不改原 WAN、LAN、无线、认证信息，不启用 mwan3 或代理。

风险：R1。增加四个受限出口可能收到不正确/缺失 DHCP 租约；新默认网关只放独立表，DNS 不接管，备份 network/firewall 并使用定时恢复脚本覆盖本次变更。网络 reload 仅应用新增配置。

预期行为：四个 macvlan 为 eth0 子设备，MAC 不同；netifd 独立维护接口租约；LuCI 显示四路。校园门户尚未认证，因此租约不等于可上网。

验证：运行 `ip -d link show type macvlan`、逐路 `ifstatus`、源 IP 路由选择及门户只读请求、原 WAN 的路由/DNS/HTTPS、`fw4 check` 和 LuCI 回读。配置重新 reload 后核对仍存在；不为验证再次重启设备。

状态：实施完成；验证通过；独立审查不适用本 R1 网口变更；已部署并回读。固件预检审查不冒充本变更的独立审查。

## 实际结果（2026-10-08 14:23–14:26）

| 接口 | 设备 | IPv4 /23 | MAC | IPv4 表 |
| --- | --- | --- | --- | --- |
| wan1 | vwan1@eth0 | 172.21.106.115 | 02:af:ca:f2:99:71 | 101 |
| wan2 | vwan2@eth0 | 172.21.106.114 | 02:af:ca:f2:99:72 | 102 |
| wan3 | vwan3@eth0 | 172.21.106.116 | 02:af:ca:f2:99:73 | 103 |
| wan4 | vwan4@eth0 | 172.21.106.113 | 02:af:ca:f2:99:74 | 104 |

- `ip -d link`：四个 macvlan，bridge 模式、UP/LOWER_UP、父设备 eth0，MAC 互异。`ifstatus` 四路 up=true，实际获得上表租约。
- 当前版本 DHCP 支持 `sendclientid=hardware`，据设备上的实际 dhcp.sh 设置，避免使用同一全局客户端标识。
- 独立源路由应用后，逐路 `ip route get 1.1.1.1 from <本路IP> oif <本路设备>` 选择对应表及设备；绑定设备的 HTTP 门户读取四路均返回 302，记录的 local_ip 与本路租约一致。没有发送账户认证请求。
- 主表仍只有 eth0 默认路由，网关 172.21.107.254。DNS 仍来自原 wan，四路 peerdns=0。`fw4 check` 返回 0。
- 原 WAN HTTPS 返回 200；最终配置后 Windows 使用指定 WLAN 的普通套接字、标准 TLS 证书验证再次返回 HTTP 200，未改变宿主机路由或代理。
- LuCI 显示四路 DHCP 已连接。UCI 已提交，变更缓冲为空；netifd reload 后运行结果一致。没有为了验收再次重启。
- 本机对恢复档案中实际 network.before/network.after 的差异自查确认原 network 条款逐字保留；firewall 除 network 列表外逐字一致。此结构证据补充运行检查，不代替运行检查。
- 两次定时恢复都已用确认标记解除，定时脚本日志为空；原启动 ID 持续至 uptime 1407.93 秒（约 23 分钟）。

## 恢复与证据

设备备份目录：`/root/campuslink-fourwan-20261008`，配置备份 0600、恢复脚本 0700。

- 回退本次全部四路网口及防火墙：`sh /root/campuslink-fourwan-20261008/rollback.sh --force`。
- 仅回退独立路由表、保留四个网口：`sh /root/campuslink-fourwan-20261008/rollback-routing.sh --force`。
- 本机目录见 `docs/README.md`；`create-four-wans.sh` 与 `configure-wan-source-routes.sh` 是本次实际部署步骤，`four-wan-interfaces.png` 是网页回读截图，`four-wan-diff-review.json` 与 `client-validation-after-fourwan.json` 是最终验证。
- 当前完整配置备份 `kwrt-after-four-wans-20261008.tar.gz`：SHA256 `afcb344fdaaed6ff866eb55ecd724d5b0cbcee0dfcf0d0b5f61a5f1ddb624113`。
- 四路专用恢复档案 `four-wan-recovery-20261008.tar.gz`：SHA256 `de68251bc5205894cdd2b3cd567c3d7ac58d9fde572519289920af41faf26e5f`。上述哈希在设备与本机一致；完整备份实际包含 network、firewall、shadow 和原校园配置，档案含凭据，仅本机保存。

已知边界：本任务时点的 DHCP 租约和门户 302 只证明网口与指定出口可用。后续真实校园认证与四路 mwan3 分流已另行验证，见 [当前状态](../README.md)及 [MWAN-02](mwan3-setup.md)；wan4 在后续接口恢复测试中续租为 172.21.106.127，上表保留网口任务当时的租约。代理与 VNT 仍未启用。

配置依据：[OpenWrt network device](https://openwrt.org/docs/guide-user/network/network_configuration)、[netifd macvlan](https://github.com/openwrt/netifd/blob/master/macvlan.c)、[OpenWrt 源路由](https://openwrt.org/docs/guide-user/network/routing/basics)。
