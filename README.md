# CampusLink

OpenWrt 校园网登录管理：独立账号、多 WAN 绑定、认证提供商、学校预设、定时检查与重新登录。界面包为 luci-app-campuslink，后台包为 campuslink。

0.3.0 已在使用 OPKG 的 Kwrt 上试用，两账号的电脑/手机模式分别绑定四路 WAN。原生 LuCI 按总览、登录配置、账号、插件设置、日志分区；认证系统、学校、服务器和检查周期统一在插件设置选择，特殊地址和重试参数放高级设置。每路只选择接口、账号、终端方式和开关，新增线路可直接新增账号。账号仅保存在路由器 root 可读文件，不引入额外用户系统、配置加密或云服务。

当前适配 Dr.COM HTTP 门户；不同 Dr.COM 协议不能直接复用。本校退出尚未能验证，暂不开放退出按钮；“禁用”仅停止插件任务。联网状态不保证当前登录账号身份。

- [安装、升级、卸载与开发](docs/Install.md)
- [提供商和学校扩展契约](docs/contracts/provider-v1.md)
- [公共设置与设备验证](docs/testing/0.3.0.md)
- [原界面简化验证](docs/testing/0.2.0.md)
- [原认证与安装测试](docs/testing/0.1.0.md)
- [当前项目状态](docs/README.md)

运行 python scripts/build_ipk.py 生成 IPK。APK 与其他 SDK 构建尚未验证。源码包只包含新插件及文档；仓库中的历史登录脚本保留原样，公开整个历史仓库前应单独检查其中的硬编码凭据。

MIT License。
