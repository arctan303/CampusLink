# CampusLink 0.3.0 开发与安装

面向已配置好 WAN 的 OpenWrt 路由器。首个已验证目标是使用 OPKG 的 Kwrt 25.12-SNAPSHOT；官方 APK 固件尚未验证。依赖 ucode、ucode-mod-fs、ucode-mod-ubus、ucode-mod-uloop、curl、ca-bundle、luci-base。curl 至少 8.9，必须支持 ifhost!设备!IP；不满足时请求失败，不退回默认出口。

## 构建与安装

本项目全为脚本，无编译器和路由器 Python/Node 依赖。本机 Python 3 运行：

```sh
python scripts/build_ipk.py
scp dist/campuslink_0.3.0-1_all.ipk dist/luci-app-campuslink_0.3.0-1_all.ipk root@ROUTER:/tmp/
ssh root@ROUTER
opkg install /tmp/campuslink_0.3.0-1_all.ipk /tmp/luci-app-campuslink_0.3.0-1_all.ipk
```

OpenWrt SDK 源码包入口为 packages/campuslink 和 packages/luci-app-campuslink 的 Makefile；本轮直接构建 IPK 的目标安装验证不等于已验证所有 SDK/APK 环境。

首次安装后重新登录 LuCI，以加载新包的会话权限；升级后取消未保存草稿并重载页面。打开服务 → CampusLink，先在“插件设置”选择认证系统、学校预设、服务器及所有 WAN 共用的检查周期。Dr.COM HTTP 根据服务器（例如 1.1.1.1）自动派生校园端点；完整 URL、探测地址和重试间隔可在高级设置覆盖。再到“登录配置”新增线路，选择已有 WAN、账号和电脑/手机终端方式，或在账号选择中直接新增账号。先启用线路做手动检查，再开自动登录。新线路默认禁用，自动登录关闭。

账号为本机 root 0600 的 /etc/campuslink/config.json；密码栏留空保留已有密码。网页读取不返回密码，无额外加密或账号系统。状态只说明当前出口联网，无法确认实际认证账号。首版本校退出未验证，不显示退出按钮；禁用仅停止插件任务，不退出校园会话。

## 服务、升级与卸载

```sh
/etc/init.d/campuslink restart
ubus call campuslink get '{}'
opkg install --force-reinstall /tmp/campuslink_0.3.0-1_all.ipk /tmp/luci-app-campuslink_0.3.0-1_all.ipk
opkg remove luci-app-campuslink campuslink
```

配置由服务创建，不是包内文件，升级/卸载保留；卸载停止服务。重新安装恢复账号和线路。需要完全清除时，卸载后由管理员主动删除 /etc/campuslink/config.json。备份含真实密码，仅保存于自己的可信设备。不要将配置、原始门户响应或 Cookie 提交到 GitHub。

0.3.0 使用 schema 2 公共设置。旧 schema 1 的系统、学校、周期及有效公共参数相同时，服务仅在内存迁移，首次成功保存才写入 schema 2，账号、密码、接口和终端方式保留。异构旧配置继续原调度，编辑前由管理员在插件设置选择统一配置。旧标准 URL 可收拢为服务器，特殊覆盖保留。升级前备份配置及旧包，同时更新后台和界面；旧 0.2.0 不认识 schema 2，降级须先停止服务、安装旧包并恢复升级前配置，再启动。

安装和卸载不创建 WAN、不修改路由、防火墙、代理或固件。异常先停用服务并查看 logread，不要运行原仓库旧安装脚本作为迁移工具。

## 扩展与测试

同协议学校：在 schools/ 添加 JSON，填写 provider、defaults 和验证说明。不同协议：新增 providers/ 下的 .uc 和 .json，在 daemon.uc、worker.uc 注册模块。参考 [提供商契约](contracts/provider-v1.md)。不支持从网页上传代码。

本机运行 `node tests/ui_config.cjs`、`node tests/settings_config.cjs` 和 `node tests/ui_view.cjs` 验证草稿、公共设置、内联账号、密码保留和页面保存/轮询回归。tests/provider.uc、tests/drcom_params.uc、tests/settings.uc 验证解析、声明、端点派生与 schema 迁移；将 imports 指向已上传的后端源码。tests/router_mock.py、tests/settings_rpc.py 和 tests/transport_cancel.py 只针对临时 campuslink.test 对象，不要将正式配置替换为假测试配置。设备准备与验证记录见 [公共设置证据](testing/0.3.0.md)、[原界面证据](testing/0.2.0.md)及[原认证测试](testing/0.1.0.md)。
