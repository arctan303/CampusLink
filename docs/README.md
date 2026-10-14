# CampusLink 当前状态

通用 OpenWrt 校园网登录管理，当前用 Cudy TR3000 256MB v1 做四 WAN 试用。有效目标见 [需求](Product-Spec.md)、[计划](DEV-PLAN.md)。

## 已验证环境与能力

- 路由器 192.168.0.1，Kwrt 25.12-SNAPSHOT，kernel 6.12.108，OPKG；ucode 2026.01.16、curl 8.22.0。
- LAN br-lan / eth1，原物理 WAN eth0；LAN 网页/SSH 与原 WAN 出站 HTTPS 200 保留。四路 vwan1–4/wan1–4、独立 DHCP 和源路由表 101–104，见 [网口任务](tasks/virtual-wans.md)。
- 无线 2.4 GHz 已按用户要求从 HT20 改为 HE20（Wi-Fi 6 / 20 MHz），运行 AP 的 AX 已开启；5 GHz 保持 HE80、宿主连接及四路联网正常，见 [维护记录](maintenance/wifi6-24ghz.md)。未做 2.4 GHz 客户端吞吐或所有终端兼容测试。
- CampusLink 0.3.0 后台已安装（LuCI 当前版本见下一条），原 schema 1 经页面保存为 schema 2，插件服务重启验证通过。两账号绑定四 WAN：A 的电脑/手机对应 wan1/2，B 的电脑/手机对应 wan3/4。原账号/密码、绑定、终端、有效端点和开关保留；四路在线，自动登录开，共用 60 秒检查。账号信息仅在路由器私有配置。
- LuCI 0.4.0 与联动 addon 0.2.0 已于 2026-10-14 更新，认证核心仍为 0.3.0；新增独立 mwan3 联动标签，学校选择已移除，登录系统与服务器保留。四条显式映射、关联成员、独立保存及实际三路排除/四路恢复通过，账号/网络/无线/代理配置和认证核心 PID 保留，见 [0.4.0 证据](testing/0.4.0.md)。原公共保存/迁移/小屏/ACL 与独立复核见 [0.3.0](testing/0.3.0.md)，原核心证据见 [0.1.0](testing/0.1.0.md)。
- LuCI 0.4.1 于 2026-10-14 增加按 WAN 手动查询公网 IPv4，独立诊断 RPC、缓存/冷却与时间/失败显示；四路查询得到四个不同公网 IP。认证/联动进程、成员状态和配置保留；游戏设备规则尚未实施，见 [0.4.1 证据](testing/0.4.1.md)。
- 当前实际认证账号无法核验；本校退出未能验证，因此不显示退出按钮。禁用停止插件任务，不退出校园会话。其他固件/APK/版本迁移尚未验证。
- 新插件 IPK 和不含旧脚本的源码包在 dist/；[安装与使用](Install.md)、[架构](Architecture.md)、[提供商契约](contracts/provider-v1.md)。0.3.0 源码的既有同步见 [CL-PUSH-01](tasks/repository-push.md)；本轮源码同步、v0.4.1 IPK 发布及中文 About 由 [CL-REL-02](tasks/release-0.4.1.md)承接，正在准备，尚未创建 Release。
- 核心 CL-R01–08 和发布检查 CL-R09 均已关闭；最终交付独立复核通过，见 [报告](reviews/cl-03.md)。

## 后续工作与保留资料

2026-10-14 本轮功能需求已确认、尚未开发：并发上限 4、账号级熔断及全部检查由 [CL-CORE-01](tasks/concurrency-account-fuse.md)承接；可选 [计划停网重试](tasks/scheduled-outage-retry.md)、[一键诊断与脱敏报告](tasks/doctor-report.md)、[未知资格有条件过期](tasks/mwan3-unknown-expiry.md)分别留任务。普通/高级设置分层，手机卡片/灯号等视觉优化后置，不增加全部登录。当前运行能力仍以上述已验证版本为准，具体行为及验收见 [需求](Product-Spec.md)。

[CL-UI-03](tasks/school-removal-mwan3-naming.md)与 [CL-MWAN-06](tasks/mwan3-mappings.md)已在原设备部署：六个标签、最多 32 条配置映射、关联成员和实际状态，分别保存认证/联动配置。原生 ucode/ubus、真实 LuCI 保存、四路实际分流及恢复通过；实际环境仍只验证四路同名，动态六路及异名绑定为规则/夹具验证。未公开发布或推送；IPv4、mwan3-nft 和长期未知边界见 [组件限制](../packages/campuslink-mwan3/README.md)。

用户反馈的长页、重复提示、分散流程和字段平铺已在 [CL-UI-01](tasks/ui-simplification.md)处理；随后 [CL-UI-02](tasks/plugin-settings.md)将公共认证和调度移入插件设置，0.3.0 已在原设备更新和验收。独立问题与关闭证据分别见 [界面复核](reviews/ui-simplification.md)及[公共设置复核](reviews/plugin-settings.md)。

mwan3-nft 四路等权策略与 mwan3 联动均已启用开机启动；[MWAN-05](tasks/campuslink-mwan3.md) 的固定四路实现已由 [CL-MWAN-06](tasks/mwan3-mappings.md) 显式映射替代。当前停用四路 ping，独立服务按已保存映射消费 CampusLink 的确定联网/未认证结果；检查中、DNS 不确定与插件暂时失联保留同绑定的上次资格。未认证夹具下真实新连接仅走三路，恢复后四路各 8 个；物理故障/租约变化和服务重启验证通过。MWAN-05 验证时 wan4 为 172.21.106.132，源表/成员表及 NAT 已刷新。认证出口及原 WAN 保留，软硬件卸载仍为 0。原配置 WLAN 短测约 388/406 Mbps；软件卸载未证明提速，已回退，见 [MWAN-04](tasks/mwan3-optimization.md)。真实校园退出、整机重启与长期健康表现仍有验证边界。[PROXY-01](tasks/proxy-mwan3.md)已验证 Nikki/Mihomo 能力（当前按用户决定关闭）：LAN 混合代理 `192.168.0.1:7890` 和 IPv4 TCP/UDP 透明代理/DNS，最终 42/42 检查通过；节点连接实际利用四路 mwan3，百度直连，原认证出口保留。Nikki 服务托管已修正并验证重启后单核心；[PROXY-02](tasks/nikki-panel.md)修复本机面板，API 仅 LAN 地址监听并使用强随机密钥，原生按钮自动连接与实时统计已实测。未做本轮代理吞吐/长期稳定性测试，未重启整机或修改 5 GHz，VNT 后续处理；CampusLink 核心不直接修改这些网络配置。

[NET-07](tasks/lan-management.md)已将网页后台绑定到 LAN 的 `192.168.0.1:80/443`，SSH 原生直接绑定 `br-lan`；新密码的 LAN 网页/SSH 登录、WAN 本机端口拒绝和四路认证出口验证通过。用户已关闭 Nikki（config.enabled=0、无核心或代理接管），后续再按需启用；原订阅与代理共存配置保留。

[NET-08 普通上网优化](dev-plan/phase-04.md)已按用户授权部署：dnsmasq 缓存 1000、保持校园 DHCP DNS；nlbwmon 只统计 LAN，按日持久化并保留 3 个统计周期；adblock-fast 使用 AdAway 单列表、DNS 域名过滤、4289 个阻断域名、校园探测白名单、TLS 和下载时间限制，不强制劫持 DNS。新插件均有中文 LuCI 页面/服务菜单，四路校园探测 204、均衡各 25%、网络/无线/管理/账号配置及启动 ID 保留。客户端 Windows 端口 53 测试受宿主限制，不能宣称该客户端所有流量已经去广告；路由器阻断/允许 DNS 与其他 LAN DNS 回复已核验。SQM 未启用，未来重新启用 Nikki 时复核 DNS 接管关系。

2026-10-12 [NET-09 有线诊断](maintenance/wired-connectivity.md)：强制走以太网的 HTTPS 与微软探测页面均正常，追加普通系统解析和按域名访问也成功；当前 Mihomo 的 11 条公网连接均使用有线地址。有线和 Wi-Fi 的物理接口 DNS 受限，TUN DNS 正常。Sparkle 工作配置含 strict-route=true，与 DNS 防泄漏拦截现象吻合；四 WAN 在线、路由器 Nikki 仍关闭。用户此前小米路由器有线可用、电脑配置未改；尚无旧路由器同条件对照，也未关闭宿主 TUN，不能认定 TUN 是新回归的唯一原因。本次未修改配置，Windows 提示不等于 LAN 断网。

原始脚本及 campus-network-scripts/ 保留原样，不作为新插件安装工具。它们不进入源码交付包；公开整个历史仓库前另行检查硬编码凭据。

固件升级的配置备份、镜像、迁移档案和独立审查保留在本机含密目录，不提交：

C:\Users\30330\.codex\visualizations\2026\10\08\01a119ec-6f89-7880-935d-23de18ac9575\router-upgrade

其中 upgrade-plan.md、preflight-evidence.md、review-receipt.md、client-validation.json 仍是先前设备升级证据；本轮未再次刷机。
