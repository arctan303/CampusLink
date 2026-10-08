# CampusLink 当前状态

通用 OpenWrt 校园网登录管理，当前用 Cudy TR3000 256MB v1 做四 WAN 试用。有效目标见 [需求](Product-Spec.md)、[计划](DEV-PLAN.md)。

## 已验证环境与能力

- 路由器 192.168.0.1，Kwrt 25.12-SNAPSHOT，kernel 6.12.108，OPKG；ucode 2026.01.16、curl 8.22.0。
- LAN br-lan / eth1，原物理 WAN eth0；网页、SSH、原 WAN HTTPS 200 保留。四路 vwan1–4/wan1–4、独立 DHCP 和源路由表 101–104，见 [网口任务](tasks/virtual-wans.md)。
- CampusLink 0.3.0 后台与 LuCI 已安装，原 schema 1 经页面保存为 schema 2，插件服务重启验证通过。两账号绑定四 WAN：A 的电脑/手机对应 wan1/2，B 的电脑/手机对应 wan3/4。原账号/密码、绑定、终端、有效端点和开关保留；四路在线，自动登录开，共用 60 秒检查。账号信息仅在路由器私有配置。
- 原生 LuCI 总览/登录配置/账号/插件设置/日志标签已上线；认证系统、学校、服务器、检查/重试周期和探测在插件层统一管理，每路只绑定接口、账号、终端和开关。新建线路可同时新增账号，Dr.COM 服务器自动派生端点，高级覆盖保留，密码不回读。公共保存/草稿/迁移/服务重启/小屏/ACL 与独立复核见 [0.3.0](testing/0.3.0.md)；原界面流程见 [0.2.0](testing/0.2.0.md)，受控认证恢复、错误/冷却、安装/卸载等原核心证据见 [0.1.0](testing/0.1.0.md)。
- 当前实际认证账号无法核验；本校退出未能验证，因此不显示退出按钮。禁用停止插件任务，不退出校园会话。其他固件/APK/版本迁移尚未验证。
- 新插件 IPK 和不含旧脚本的源码包在 dist/；[安装与开发](Install.md)、[架构](Architecture.md)、[提供商契约](contracts/provider-v1.md)。尚未推送或公开 GitHub。
- 核心 CL-R01–08 和发布检查 CL-R09 均已关闭；最终交付独立复核通过，见 [报告](reviews/cl-03.md)。

## 后续工作与保留资料

用户反馈的长页、重复提示、分散流程和字段平铺已在 [CL-UI-01](tasks/ui-simplification.md)处理；随后 [CL-UI-02](tasks/plugin-settings.md)将公共认证和调度移入插件设置，0.3.0 已在原设备更新和验收。独立问题与关闭证据分别见 [界面复核](reviews/ui-simplification.md)及[公共设置复核](reviews/plugin-settings.md)。

学校正式名称待补。mwan3-nft 四路等权策略已启用并设为开机启动，LAN 实际分流及单路接口故障/恢复通过；认证出口及原 WAN 保留，软硬件流量卸载关闭。wan4 续租地址为 172.21.106.127，详细证据、恢复入口和验证边界见 [MWAN-02](tasks/mwan3-setup.md)。Nikki/Mihomo、TUN 已安装，代理保持未启用，VNT 后续处理。本插件不负责这些网络配置。

原始脚本及 campus-network-scripts/ 保留原样，不作为新插件安装工具。它们不进入源码交付包；公开整个历史仓库前另行检查硬编码凭据。

固件升级的配置备份、镜像、迁移档案和独立审查保留在本机含密目录，不提交：

C:\Users\30330\.codex\visualizations\2026\10\08\01a119ec-6f89-7880-935d-23de18ac9575\router-upgrade

其中 upgrade-plan.md、preflight-evidence.md、review-receipt.md、client-validation.json 仍是先前设备升级证据；本轮未再次刷机。
