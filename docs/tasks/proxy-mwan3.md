# PROXY-01：Mihomo LAN 代理与四 WAN 共存

目标：导入用户提供的订阅，使现有路由器的 LAN 代理可用，并让代理节点出站连接利用四路 mwan3。依据 D-20261008-11 / REQ-004 / AC-015；用户授权导入、设置和设备测试，禁止重启路由器及修改 5 GHz。

范围：已安装 Nikki/Mihomo 的订阅、混入、LAN 代理/DNS 和原生 mwan3 标记匹配；修正当前 Nikki 启动脚本的进程托管。CampusLink 核心、账号、WAN 设备/租约/源路由、LAN 地址、无线、固件及宿主长期路由/代理配置保留。DHCP 的唯一改动是 dnsmasq 的 dns_redirect；不改 DHCP 分配或原上游 DNS。VNT 后续处理。

规模/风险：短产品任务，R1。错误选路可能影响 LAN 上网；变更仅限本设备代理及标记匹配，有私有备份、定时回退和针对性真实流量验证。初始 API 限制回环；后续 [PROXY-02](nikki-panel.md)按 D-20261009-12 改为仅 LAN 地址及强随机密钥。显式代理仅允许当前 LAN，WAN 入站策略保留；不改变 CampusLink 权限/凭据接口。未安排独立审查、未提交或推送仓库。

## 交付状态

2026-10-09 完成设备实施与针对性验证，首次实施时代理和 CampusLink 联动均启用服务自启动。后续用户自行关闭 Nikki，D-20261009-13 / [NET-07](lan-management.md)实测 config.enabled=0、无核心和接管；CampusLink 与四路均衡继续运行。后续按需启用代理，以下原验证不作为关闭状态下的实时流量证据。首次实施未主动重启整机；10:08 追加核验时设备已有新的启动，配置与服务运行核验通过，未测试启动各阶段的先后时序。测试结束后取消临时回退计时器，保留手动恢复入口。

- 环境：Nikki 2026.04.08-r15、luci-app-nikki 1.26.1-r9、Mihomo 1.19.32-r34、mwan3-nft 3.6.12-r4。
- 订阅已私有导入，7 个条目（含 DNS 节点）、3 个组、133 条原规则；混入 7 条私有网段、管理/校园门户及本地域名直连规则，运行规则共 140 条。优先使用缓存配置，启动不等待订阅下载；store-selected/store-fake-ip 均为 true，节点选择与 fake-ip 缓存持久化。
- 本任务验收时手动选择订阅中的原生 IPv4 VLESS TCP 节点，后续管理员可自行切换；不同节点的验证不相互替代。LAN 显式 HTTP/SOCKS 混合端口 `192.168.0.1:7890`，允许 `127.0.0.0/8` 和 `192.168.0.0/24`；当前控制 API 为 `192.168.0.1:9090`、强随机密钥，本机面板入口由 [PROXY-02](nikki-panel.md)修复。原回环/旧密钥选择已替代。
- IPv4 LAN TCP/UDP 透明代理采用 TPROXY，DNS 在 LAN 接管到 1053 / fake-ip。路由器普通流量不接管，IPv6 代理/DNS 接管关闭，TUN 和自动路由关闭；5 GHz 未修改。
- Nikki 出站 socket 标记 `0x10000`；新增原生 `mwan3.mihomo_outbound` 匹配该位进入 balanced。mwan3 成员仍使用 `0x3f00`；原 `lan_balanced` 增加 `fwmark=0x0/fwmask=0x80`，让已被 TPROXY 接管的客户端前半段不占用同一个均衡序列，实际节点连接参与四路分配。
- Kwrt 的 dnsmasq 自有 NAT redirect 优先级早于 Nikki，原先使普通 53 端口请求绕过代理 DNS。仅将原生 `dhcp.@dnsmasq[0].dns_redirect` 从 1 改为 0，交给 Nikki 的 LAN DNS 接管；原 DNS 地址与 DHCP 租约配置保留。
- 当前 Nikki 版本用 shell 启动核心且缺少 `exec`，服务停止/重启会遗留旧核心。备份后只加 `exec`，使 procd 管理核心本身；清理时逐个核对可执行文件与本次运行目录参数。真实 Nikki 服务重启后旧 PID 消失、仅一个核心，procd PID 一致。升级 Nikki 后需核对供应商是否已修复或覆盖此行。

## 验证与证据

| 项目 | 结果与边界 |
| --- | --- |
| 核心与服务 | 当前配置 `mihomo -t` 通过；服务重启后单核心且 procd 管理 PID 一致；私有配置/订阅/mixin/run config 均 root 0600。 |
| 显式 LAN 代理 | 最终单核心下 4/4 HTTPS 通过，包括 Google 204、Cloudflare 与百度 200；TLS 证书验证开启。初始验收时控制 API 从 LAN 连接被拒绝，此访问选择后由 PROXY-02 替代并实测认证边界；非允许来源未获代理 CONNECT。 |
| 透明 TCP/UDP | 最终 WLAN 绑定测试 42/42 通过：32 个 Google HTTPS、Cloudflare/百度 HTTPS，以及 8 个 UDP STUN。另即时捕获 8/8 STUN 均由 TProxy 接管且选择原生节点；响应来源、事务 ID 和 magic cookie 校验通过。 |
| 四路代理出站 | 最终被捕获的 32 条节点 TCP 连接，NAT wan1/2/3/4 分别 9/8/8/7，ct mark 分别 256/512/768/1024。API 中 32 个 Google 连接选择指定节点，百度为 DIRECT。API 前半段与实际节点 conntrack 数量可能不同，按实际节点地址/端口和 NAT 回包目的地址计数。 |
| CampusLink 联动 | 受控 wan4 未认证状态夹具经真实联动处理后，25 条新节点流量分配 wan1/2/3=8/9/8、wan4=0，26/26 TLS 通过。恢复实时 CampusLink 后四路各 25%。未真实退出校园会话，也未把夹具当作校园登录实测。 |
| 认证出口保留 | 四个绑定 vwan1–4 的路由器 HTTP 探测均 204，源地址分别为 172.21.106.115/.114/.116/.132；CampusLink 四路在线，配置 generation 15 保留。 |
| 标准 LAN DNS | 宿主现有代理阻止普通 53 请求，未修改宿主代理。Windows 使用 WLAN 绑定请求 1053；另建独立 LAN namespace，经 br-lan 的普通 53 请求得到 fake-ip，HTTPS 204 通过；指定外部 DNS 的 LAN 请求接管也已验证。测试 namespace/veth、临时 kmod-veth 和诊断规则已清理。 |
| 管理与保护配置 | 原网络、防火墙、无线、CampusLink JSON 的 SHA256 均与前置备份一致，启动 ID 始终相同；5 GHz 保持 HE80，管理 SSH/LuCI 保留。只重启代理服务，未重启路由器。 |

早期节点对照包含多核心存活，不能用于最终节点稳定性或 UDP 能力结论；另一次测试与服务重启重叠，也不计入验收。清理后的最终原生节点 TCP/UDP 证据独立记录。住宅节点在单核心的一轮中出现 UDP 超时及一次 TLS 失败，因此当前未选为默认；不据此宣称节点永久不支持 UDP。

未做本轮代理吞吐测试，不承诺达到 400 Mbps。四 WAN 是多连接均衡；QUIC、连接复用及代理服务商限制可能让多个请求共用单个出口，不能从 LAN 请求数量推断带宽叠加。IPv6 节点与长期稳定性仍未验收。

### 2026-10-09 10:08 追加运行核验

用户要求确认透明代理及四 WAN 配合。本轮只读核对及短时真实流量测试，不改路由器配置、不重启或改无线。设备启动 ID 已与首次实施不同，读取时 uptime 约 10 分钟；不把昨晚证据替代为本次运行结果。原保护配置，以及 Nikki/mwan3/DHCP/init 的最终哈希均一致；单个核心由 procd 管理，四路 CampusLink 在线，mwan3 四路各 25%，ping 跟踪仍关闭。

WLAN 绑定的直接 TCP/UDP 测试没有显式代理 CONNECT：26 条均在 Mihomo API 匹配为 TProxy，16 条 Google 请求选择原生节点，8 条 UDP 选择同一节点，百度 DIRECT。请求 25/26 成功，一条 Google 在 TLS 握手成功后读取超时；随后针对该目标的小型复测 3/3 成功，不能据此宣称不存在偶发超时。同时活动的节点 TCP 连接 NAT wan1/2/3/4 为 6/7/7/7、成员 mark 为 256/512/768/1024；该快照含背景连接，不等同于本轮请求数。普通 53 接管规则存在，计数当时为 0；本轮 Windows DNS 仍因既有宿主代理限制使用 1053，普通 LAN 53 的真实验证沿用首次独立 namespace 证据，不宣称本轮再次测过 53。

新增私有证据：`live-recheck.json`、`live-recheck-private.tgz`、`live-recheck-summary.json`、`live-timeout-recheck.json`。没有执行关机；待确认的收尾对象仍未确定。

## 脚本、资料与恢复

- [配置脚本](../../scripts/configure-router-proxy.sh)：针对本设备的无凭据部署入口，要求备份/私有输入/自动回退已就绪、无旧核心、无待提交 UCI；先仅启用显式代理。配置及节点验证后再设置 `nikki.proxy.enabled=1` 并只重启 Nikki。本设备已完成该阶段和透明接管，不重复运行配置脚本覆盖备份。
- [验证脚本](../../scripts/verify-router-proxy.py)：Windows WLAN 绑定 HTTPS/DNS/UDP，保留 TLS 校验，不修改宿主长期路由。
- [回退脚本](../../scripts/rollback-router-proxy.sh)：仅撤销此次 Nikki 配置、init 修正、mwan3 规则及 dns_redirect，恢复原启用状态；网络、无线与 CampusLink 不覆盖。原始缓存/geodata 可以保留为未启用资料。
- 设备私有备份：`/root/campuslink-proxy-mwan3-20261008/`。若需撤销后续面板和全部代理，先执行 [PROXY-02](nikki-panel.md) 的面板恢复，再执行本任务完整回退。手动回退：`sh /root/campuslink-proxy-mwan3-20261008/rollback.sh --force`。确认完成后的普通回退调用是无操作，防止旧计时器撤销已验收配置。
- 本机 Git 忽略资料：`.local/proxy-mwan3/`，含最终报告、API/conntrack、订阅与私有恢复档案。公开文档不包含订阅 key、节点密码/UUID、API secret 或原始配置。
- 有效最终证据：`final-native.json`、`final-native-evidence.tgz`、`udp-final-live.json`（即时 API 快照；其交互保持步骤因 stdin EOF 结束）、`udp-final-peer.json`（10/10 独立复测，正常退出）、`final-explicit.json`、`acceptance-summary.json`；联动证据为 `coexistence-summary.json` 与 wan4-paused 记录。设备完整私有档案为 `campuslink-proxy-mwan3-evidence-20261009.tar.gz`，SHA256 `077c85578bcf8ac69170e467d264322e543a67ee1b63ab7a468f7ccbaa7380d2`，与设备原档案一致；摘要见 `evidence-manifest.json`。

依据：[Mihomo Linux routing-mark](https://wiki.metacubex.one/config/general/)；UDP 测试采用 [Cloudflare 公共 STUN](https://developers.cloudflare.com/realtime/turn/)。具体标记/优先级和进程问题以本机已安装脚本及实际流量为准。

收尾指令：用户要求测试后强制关闭“当前设备”；已询问指 Windows 电脑还是路由器，尚未收到对象选择。关机未执行，不能从等待时间或选项预选推定对象授权。代理任务与备份完成后仅等待此收尾澄清。
