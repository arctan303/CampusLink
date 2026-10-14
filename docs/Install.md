# CampusLink 安装与使用

本指南对应核心 **0.3.0**、LuCI **0.4.1**、可选 mwan3 联动 **0.2.0**。各组件独立版本号。

## 适用环境

- 已经配置好 WAN、可以管理 LuCI 的 OpenWrt 路由器，校园网使用 Dr.COM HTTP 门户。
- 使用 OPKG；已验证 Kwrt 25.12-SNAPSHOT。APK、其他 SDK 或固件尚未验证。
- 核心依赖 `ucode`、`ucode-mod-fs`、`ucode-mod-ubus`、`ucode-mod-uloop`、`curl`、`ca-bundle`；界面依赖 `luci-base`、`rpcd`、`busybox`，BusyBox 需提供 `flock`。
- curl 至少 8.9，并支持 `ifhost!设备!IP`。不满足时查询或检查会失败，不会自动改用默认 WAN。
- 可选联动还依赖 `mwan3-nft` 和 `ucode-mod-uci`，当前只验证 mwan3-nft 3.6.12-r4 / IPv4。

插件不会创建 WAN 或配置基础路由。安装前先确保对应接口在 OpenWrt 中存在，路由器的软件源与固件版本匹配。

## 安装

从 [v0.4.1 下载页面](https://github.com/arctan303/CampusLink/releases/tag/v0.4.1)获取所需文件：

| 文件 | 安装方式 |
| --- | --- |
| `campuslink_0.3.0-1_all.ipk` | 必装后台 |
| `luci-app-campuslink_0.4.1-1_all.ipk` | 必装界面 |
| `campuslink-mwan3_0.2.0-1_all.ipk` | 需要 mwan3 联动时再装 |
| `SHA256SUMS` | 下载文件的 SHA256 校验清单 |

将前两个包上传到路由器 `/tmp/`。可使用 SCP，也可通过 LuCI 软件包页面上传安装。SSH 安装命令在路由器上执行：

```sh
opkg install /tmp/campuslink_0.3.0-1_all.ipk /tmp/luci-app-campuslink_0.4.1-1_all.ipk
```

缺少依赖时，先通过固件对应的软件源安装依赖再重试。不要通过强制忽略依赖来安装。安装后重新登录 LuCI，打开 **服务 → CampusLink**；升级时先取消未保存的草稿，再刷新页面。

## 首次配置

1. **插件设置**：选择登录系统，填写认证服务器及各 WAN 共用的检查周期。Dr.COM HTTP 会从服务器派生认证端点；完整 URL、探测地址和重试间隔可在高级设置覆盖。新配置不预填学校服务器，学校选择入口已移除。
2. **账号**：添加校园网账号与密码。编辑已有账号时，密码栏留空会保留原密码。
3. **登录配置**：添加线路，选择已有 WAN、账号及电脑/手机终端方式；也可在账号选择处直接新增账号。
4. **检查**：启用线路，先手动检查、按需登录，确认正常后开启自动登录。新线路默认禁用，自动登录默认关闭。

账号保存在 `/etc/campuslink/config.json`，权限为 root 0600，网页读取不会返回密码。没有额外的配置加密或云端账号系统。

“已联网”只说明当前出口可联网，无法确认校园会话实际登录账号。退出行为尚未验证，因此不提供退出按钮；“禁用”只停止插件任务，不退出校园会话。

## 查询各 WAN 的公网 IPv4

在总览找到“公网 IPv4”，点击对应线路的查询或刷新。原 WAN 地址标为“接口 IP”，可能是内网地址；公网 IPv4 是外部站点观察到的出口地址。

查询固定访问 `https://myip.ipip.net/json`，绑定该 WAN 的设备和源 IPv4，绕过代理并校验 TLS。每接口有 60 秒冷却，全局最多一个查询；结果显示时间，5 分钟后标为上次结果，设备/IP 改变后需要重查。没有后台定时查询。

失败不改变认证或分流状态。外部服务会看到正常请求的公网来源地址，查询不发送校园账号与密码。结果只代表到查询站点的直连路径，不代表代理、游戏加速器或所有游戏连接。

## 可选：mwan3 联动

先在 mwan3 中配置好接口、成员、权重和策略，再安装可选组件：

```sh
opkg install /tmp/campuslink-mwan3_0.2.0-1_all.ipk
/etc/init.d/campuslink-mwan3 enable
/etc/init.d/campuslink-mwan3 start
```

重新登录 LuCI，在 **mwan3 联动** 标签配置：

1. 对准备联动的 mwan3 接口，停用独立 tracking IP/gateway，设 `initial_state=offline`，按 mwan3 原生流程应用配置。仍运行的原生 tracker 会阻止接管。
2. 每行选择已有 CampusLink 来源接口和对应 mwan3 接口。两端须指向同一实际设备及 IPv4；接口名称可以不同。成员名称由 mwan3 配置派生，只读展示。
3. 启用需要的行及总开关，保存后查看实际状态与原因。最多 32 行，来源和目标各自唯一。

新组件默认关闭、没有映射，启动服务本身不会接管接口。配置独立保存在 `/etc/campuslink-mwan3/config.json`，保存不重启认证任务。没有安装或运行组件时，认证仍可使用。

组件不创建成员、策略或游戏规则，也不修改 mwan3 跟踪配置或全局重载网络。停用、删除映射或停止服务只释放控制，**保留当时的成员状态**；需要恢复原生探测时在 mwan3 设置中处理。长期未知可能保留已故障线路的资格，目前没有自动过期上限。更多边界见[组件说明](../packages/campuslink-mwan3/README.md)。

手动安装的旧 0.1.0 固定四路组件不会自动迁移映射。升级前备份旧文件及配置，明确保存原接口映射并验证后再安排重启；原设备支持脚本不能直接用于其他路由器。

## 升级与恢复

升级前保存旧 IPK，并备份账号配置；使用联动时同时备份其配置和 mwan3 配置。备份包含真实密码，仅保存到自己的可信设备，不要提交到 GitHub。

用与首次安装相同的 `opkg install` 命令安装新版本，按需同时更新后台、界面和联动组件。仅需重装同一版本时加 `--force-reinstall`。首次增加诊断 RPC 时安装脚本会重启 rpcd，随后需要重新登录 LuCI；它不会重启认证核心或联动服务。

配置由服务创建，升级和卸载会保留。0.3.0 核心使用 schema 2：相同公共参数的旧 schema 1 配置先在内存迁移，成功保存后写入新格式，账号、密码、接口和终端方式保留；异构旧配置需在插件设置明确选择统一公共参数。旧学校预设的有效值在保存时转为显式参数。

需要降回旧 0.2.0 核心时，先停服务，安装旧包并恢复升级前配置，再启动；旧核心不认识 schema 2。不要用历史安装脚本进行迁移。

## 常见问题

- **菜单没出现或提示无权限**：重新登录 LuCI，清除旧页面缓存；确认后台和界面包均已安装。
- **检查失败、接口无地址**：先检查 OpenWrt 接口是否有 IPv4、服务器是否正确，再检查 curl 版本和日志。联网状态不能验证账号身份。
- **mwan3 组件不可用或拒绝接管**：确认 addon 服务已启动、版本为 0.2.0，并按页面原因检查映射、实际出口和原生 tracker。
- **公网 IP 查询失败**：查询服务或该 WAN 的 HTTPS 连接可能暂时不可用，冷却结束后可重试；该结果独立于校园认证状态。
- **游戏异常或要求重新登录**：多 WAN 会让不同连接使用不同出口；当前没有游戏专用规则。需要固定出口时，在 mwan3 中为游戏电脑设置合适的策略和规则。

管理员可在路由器上查看服务状态和日志：

```sh
/etc/init.d/campuslink status
logread -e campuslink
```

反馈时说明固件、组件版本、出错操作和已脱敏的日志，避免上传账号、密码、Cookie、原始门户响应或完整配置。

## 卸载

安装过可选组件时先卸载它，然后卸载界面与后台：

```sh
opkg remove campuslink-mwan3
opkg remove luci-app-campuslink campuslink
```

卸载停止对应服务，保留账号及联动配置；联动停止不会恢复原生探测。需要彻底清除时，由管理员在确认不再需要后删除对应配置文件。

## 从源码构建与开发

在开发电脑使用 Python 3，路由器无需 Python/Node：

```sh
python scripts/check_release.py
```

该命令检查两次构建一致性、包路径/权限/JSON，并在 `dist/` 生成三个 IPK 与 `CampusLink-0.4.1-source.zip`。只需打包可运行 `python scripts/build_ipk.py`；Windows 可将 `python` 换成 `py -3`。SDK Makefile 在各 `packages/` 子目录，SDK/APK 构建尚未验证。根目录历史脚本不作为新插件安装工具。

界面回归入口为 `node tests/ui_config.cjs`、`node tests/settings_config.cjs`、`node tests/ui_view.cjs`；映射和 shell 隔离验证为 `node tests/mwan3_mappings.cjs`、`node tests/mwan3_native.cjs`。原生 ucode 与设备验证见 [0.4.0](testing/0.4.0.md)、[0.4.1](testing/0.4.1.md)和[提供商契约](contracts/provider-v1.md)。模拟测试不能替代目标固件验证。
