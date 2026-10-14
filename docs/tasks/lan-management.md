# NET-07：管理入口仅限 LAN 与普通上网检查

目标与依据：用户提供新的设备登录凭据，要求 WAN 不能打开后台、只能 LAN；代理已经由用户关闭，后续需要时再启用。承接 D-20261009-13 / REQ-005 / AC-017。凭据仅用于当前登录，不进入公开文件。

路线/规模/风险：短产品配置任务，R1。只收紧已安装 uhttpd/Dropbear 的绑定地址，不新增身份或修改鉴权；误绑定可能导致管理员失联，保留当前 LAN、独立自动回退和第二条新连接验证。当前 WAN input REJECT 已生效，不凭全地址监听推断校园侧实际可访问。

预期与范围：HTTP/HTTPS 只监听 192.168.0.1 的现有 80/443 端口，SSH 使用 DirectInterface=lan 直接绑定 br-lan 设备；原 WAN 区域包括 eth0、vwan1–4，仍拒绝入站。LAN 页面、新 SSH 登录、四路认证/上网均保持。Nikki 关闭、无核心/代理端口和接管规则。检查负载、存储、DNS、现有插件并给出按收益排序的建议，不据此自动安装插件或改 DNS/限速/流量卸载。

非目标：不重启路由器、不改无线尤其 5 GHz、不改校园账号/认证逻辑、四路策略和 WAN 租约、不变更管理员密码、不启用代理/VNT、不进行软件包批量升级或关闭宿主机。

依赖与基线：LAN 192.168.0.1，uhttpd main、dropbear main；当前启动 ID d8fef3f1-467a-4363-b0ae-fb95ecc8e899。用户已在任务外重启过设备；本轮只使用当前基线，不沿用上轮启动 ID。没有待提交 UCI。

验证：前后网页监听地址及 SSH 设备绑定、LAN 网页认证与新 SSH 认证、五个 WAN 地址的 TCP 22/80/443 拒绝；同时核对 WAN nft input 拒绝规则，区分本机地址探测与真实校园侧外部测试。保护配置哈希、本次启动 ID、代理停止和四路状态不变。

状态：2026-10-09 已完成设备实施和针对性验证，R1 自查；不安排独立审查，不提交或推送。私有资料 `.local/lan-management/`。

## 结果与证据

- 网页 HTTP/HTTPS 仅监听 `192.168.0.1:80/443`，无 IPv6/通配网页监听。浏览器使用用户的新密码登录成功，Web 管理页面显示 LAN HTTP 地址及“只允许内网访问”；截图 `lan-webadmin.jpg`。未认证 LuCI 请求为 403，不能把缺少会话时的 403 当成 LAN 服务不通。
- Kwrt 当前 `/lib/functions/network.sh` 的 `network_get_ipaddrs_all lan` 实测返回空，Dropbear Interface=lan 曾回退通配监听。此方案未保留；改为原生 `DirectInterface=lan`，运行命令明确带 `-l br-lan`，新 LAN SSH 认证通过。此模式 netstat 仍显示 `0.0.0.0/::`，但套接字绑定 LAN 设备；不能仅据 netstat 文本判定所有接口开放，也不宣称 SSH 仅 IPv4 地址监听。未修改公共 network.sh 或供应商 init。
- 从路由器本机对五个 WAN 地址的 22/80/443 共 15 个 TCP 探测均失败；LAN 客户端三个端口均成功，且网页/SSH 实际登录成功。运行 nft input 将 eth0/vwan1–4 送入 input_wan，最终 REJECT，无管理 ACCEPT。未安排真实校园侧客户端发起的独立入站测试，保留此证据边界。
- vwan1–4 绑定 HTTP 探测全部 204；CampusLink 四路 online，mwan3 四路 online、tracking disabled、各 25%。Nikki config.enabled=0、无 Mihomo 进程，无 7890/7892/9090 或代理 nft 表；其缓存/订阅保留供后续启用。
- 网络、firewall、无线、DHCP、mwan3、Nikki 和 CampusLink 配置哈希全部与本次基线一致，无 UCI 缓冲；启动 ID 不变。只重启管理服务，不重启整机，不改 5 GHz。
- 十分钟独立回退守护真实启动并核对存活；新连接验证后写 confirmed，进程组已取消。确认后的正常 rollback 调用为无操作，哈希验证通过。未故意断开 LAN 或实测定时恢复，不能追认为失联恢复实验。

[配置入口](../../scripts/restrict-router-management.sh)要求新的备份目录、已确认的 LAN/单服务实例和空 UCI 缓冲；只改两个管理配置。当前设备已经完成，勿重复执行覆盖新基线。设备备份 `/root/campuslink-lan-management-20261009/`；手动恢复 `sh /root/campuslink-lan-management-20261009/rollback.sh --force` 只恢复 uhttpd/Dropbear，会回到旧的通配管理监听，按需要使用。

私有档案 `campuslink-lan-management-evidence-20261009.tar.gz`，SHA256 `e312fd638e692010a20cf5324e197d99dbda520679e481f377a00626938a5da5`；包含配置前后、实际 SSH 命令、WAN nft 输入规则、保护哈希及手动恢复，不包含新登录密码。

## 普通上网建议（尚未实施）

后续承接：用户在 2026-10-09 授权按建议优先级实施，DNS 缓存、流量统计和轻量去广告由 [NET-08](../dev-plan/phase-04.md)负责；以下保留 NET-07 当时检查结果，SQM 仍需延迟证据。

- 当前约 483 MiB 内存、初始已用约 18%，overlay 剩余约 140.6 MiB，空闲负载低；packet_steering=1。没有内存/连接表饱和证据，不因“优化”批量安装常驻服务。软硬件卸载保留 0/0，已有 MWAN-04 对照没有证明软件卸载提升吞吐。
- dnsmasq 缓存为 0，运行配置也是 cache-size=0；建议优先试 1000 条缓存，保持校园 DHCP 提供的 DNS 上游，观察缓存命中和域名访问，再与启用代理时的 DNS 接管一起回归。本轮没有变更 DNS 或声称已经测出提速。
- 已有 CampusLink 调度之外，还存在每分钟 `/data/school_net/keepalive.sh`，包含 login/ping 信号；尚未完整核对其行为，不能据文件名确认重复认证，不删除它。后续若研究无谓重复登录，先确定这个旧任务与 CampusLink 的职责。
- 优先推荐 `luci-app-nlbwmon`（设备流量统计）；按需 `luci-app-adblock-fast`（DNS 去广告，先保留校园认证域名允许列表）；只有满速下载时明显影响延迟才对照 `luci-app-sqm`。当前源中这些包存在，但未安装，未宣称它们增加带宽。SQM 消耗 CPU 并需要按实际出口规划限速，不直接照单 WAN 默认配置套到四个虚拟 WAN。
- 固件仍采用 mwan3-nft 3.6.12-r4 / luci-app-mwan3-nft 27.202.70822~201f770，与实际 firewall4/nftables 及既有 CampusLink/代理标记验证对应。旧 mwan3 可经 iptables-nft 兼容，但没有本任务迁移收益证据。当前无 mwan3 中文 LMO，已更新包索引也无对应简体中文翻译包；英文包描述与 UI 缺少翻译是两个问题，不用换路由后端解决。

依据：[uhttpd LAN 绑定](https://openwrt.org/docs/guide-user/services/webserver/uhttpd)、[Dropbear DirectInterface](https://openwrt.org/docs/guide-user/base-system/dropbear)、[mwan3 nft 社区变体](https://openwrt.org/docs/guide-user/network/wan/multiwan/mwan3-nft)、[nlbwmon](https://github.com/openwrt/packages/blob/master/net/nlbwmon/Makefile)、[adblock-fast](https://docs.mossdef.org/adblock-fast/)、[SQM](https://openwrt.org/docs/guide-user/network/traffic-shaping/sqm)。具体当前设备状态以上述配置及运行证据为准。
