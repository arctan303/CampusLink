# MWAN-01：四路 mwan3 接入预检

目标：根据用户“这里处理 mwan3，先看看”的要求，核对现有四路出口、CampusLink 登录状态和 mwan3 的接入条件。

范围：只读检查及指定出口的联网探测。本轮不启动 mwan3、不改网络、防火墙或校园网插件配置；代理与 VNT 继续留待后续。

规模与风险：短任务，R0；本轮没有运行配置变更。后续部署另按实际路由影响评估，并保留备份与定时恢复。

状态：预检完成；四路策略实施未开始。检查时间为 2026-10-08 16:19–16:24（Asia/Singapore），结果仅代表该时点。

## 已核验基线

设备为 Cudy TR3000 256MB v1，Kwrt 25.12-SNAPSHOT（2026-10-08），内核 6.12.108；SSH、原物理 WAN 和管理路径正常。

| 接口 | 设备 | DHCP IPv4 | 独立路由表 | metric | 指定出口 HTTP 探测 |
| --- | --- | --- | --- | --- | --- |
| wan1 | vwan1 | 172.21.106.115/23 | 101 | 101 | 204 |
| wan2 | vwan2 | 172.21.106.114/23 | 102 | 102 | 204 |
| wan3 | vwan3 | 172.21.106.116/23 | 103 | 103 | 204 |
| wan4 | vwan4 | 172.21.106.113/23 | 104 | 104 | 204 |

四个 macvlan 设备的父设备均为 eth0，模式为 bridge，MAC 不同。四表均有经 172.21.107.254 的默认路由；原物理 wan 为 eth0、172.21.106.111/23，默认路由仍在 main 表。LAN 为 192.168.0.1/24。

CampusLink 0.1.0 的公开状态显示四路均为 `online / already_online`，自动登录均开启。逐路执行 `curl --interface vwanN` 访问 `http://connectivitycheck.platform.hicloud.com/generate_204`，全部返回 HTTP 204，源地址分别对应上表；物理 eth0 同样返回 204。这证明当前四路可联网，不证明认证失效后的行为。

每个 vwan 分别 ping 223.5.5.5 和 119.29.29.29，8 次均成功。未主动退出校园网，因此尚未验证这些 ICMP 目标在认证失效时是否会失败。

## mwan3 当前状态

- 已安装 `mwan3-nft 3.6.12-r4`，服务未启用，没有 mwan3 跟踪进程或 `inet mwan3` 表。
- UCI 仍为禁用的 wan/wan6/wanb/wanb6 示例，没有 wan1–wan4 的成员及策略。当前普通流量仍走原物理 WAN。
- 全局 `mmx_mask` 为 `0x3F00`，未设置 `rt_table_lookup`。
- 软件与硬件流量卸载均开启，运行中的 fw4 flowtable 包含 eth0、eth1、无线和 vwan1–vwan4。
- `fw4 check` 返回 0；IPv4 转发开启，eth0 和四个 vwan 的 rp_filter 均为 0。network/firewall/mwan3 没有未提交的 UCI 变更。

## 接入时必须处理的事项

1. **导入现有路由表。** 设备上的 `/lib/mwan3/mwan3-create-iface-route.uc` 只读取 main 及 `rt_table_lookup` 指定的额外表，再按设备复制默认路由。四个 vwan 的默认网关在 101–104；直接添加成员并启动可能缺少对应默认路由。建议保留现有网络配置，给 mwan3 增加这四个 lookup 表。mwan3 自身成员表编号按 UCI 顺序生成，不能与现有 101–104 混为一谈。
2. **保持认证请求的出口。** mwan3 的 fwmark 规则优先级早于现有 netifd 源地址规则。CampusLink 的 curl 已同时绑定设备和源 IP（`ifhost!设备!地址`）；建议先将均衡规则限定为 LAN 源网段，避免路由器自身的认证流量被全局均衡规则重新选路。后续必须用实际认证流量验证。
3. **验证流量卸载与切换。** 本机 mwan3 启动脚本在软件卸载开启时可能清空 conntrack，以清理旧卸载路由，现有连接可能重建。建议首次接入和故障测试时暂时关闭卸载；是否恢复应依据验证结果，不据此断言卸载始终不兼容。
4. **健康检查应证明外网可用。** 目前可以使用 ping；设备未安装 httping。不要把校园网门户地址 1.1.1.1 当作外网连通性目标。认证失效时 ICMP 的表现仍需验证，避免 mwan3 把只能访问门户的线路报告为在线。

本机源码依据：`/lib/mwan3/mwan3-create-iface-route.uc`、`mwan3-list-routes.uc`、`mwan3.sh`、`/usr/sbin/mwan3rtmon`、`mwan3track`、`/etc/init.d/mwan3` 和 `/usr/share/campuslink/transport.uc`。原生 nft 版本背景核对了[维护者的 OpenWrt 25.12 README](https://github.com/dl12345/mwan3/blob/openwrt-25.12/README.md)；具体行为以上述已安装源码为准。

## 后续实施与验收（尚未执行）

- 备份最新 network/firewall/mwan3 配置并准备定时恢复；保留原 WAN 和 LAN 管理路径。
- 将 wan1–wan4 纳入 IPv4 成员，初始均衡权重建议 1:1:1:1，并提供单路策略；该比例是建议，尚未作为用户决定。
- 补充 101–104 路由表读取；LAN 流量进入四路均衡，认证请求继续使用各自绑定的出口。
- 核验四个成员表的默认路由、NAT/标记、实际新连接分布、单路故障剔除及恢复；同时复查 CampusLink 登录与管理访问。
- 后续 DHCP 地址或网关变化时，核验 netifd 热插拔与 mwan3 路由刷新，不能只依赖静态地址下的验证。

恢复入口：先重新读取路由器与校园网插件状态，确认另一处插件开发没有改变接口/绑定契约；复用 [四虚拟 WAN 任务](virtual-wans.md)中的恢复资料，再按当时最新配置部署。
