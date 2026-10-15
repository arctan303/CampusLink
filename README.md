# CampusLink

OpenWrt 校园网自动登录插件。通过 LuCI 管理账号和线路，让每个 WAN 使用指定账号登录，并定时检查联网状态。

当前公开版本支持 **Dr.COM HTTP 门户**，可选安装 **mwan3 联动**组件。适合已经配置好单 WAN 或多 WAN 的路由器。

v0.4.2 试用构建新增 **深澜 SRBX1 变体**、**锐捷 ePortal 非 RSA / RSA 零填充**实验性适配，离线验证和独立审查已通过，发布准备就绪；真实校园兼容性等待使用者反馈。[支持范围、源码参考与试用反馈](docs/providers/experimental.md)。

## 下载与安装

从 [GitHub Releases](https://github.com/arctan303/CampusLink/releases/latest) 下载 IPK；本次发布为 [v0.4.1](https://github.com/arctan303/CampusLink/releases/tag/v0.4.1)。

| 安装包 | 用途 | 是否必需 |
| --- | --- | --- |
| `campuslink_0.3.0-1_all.ipk` | 登录与联网检查后台 | 必需 |
| `luci-app-campuslink_0.4.1-1_all.ipk` | LuCI 管理界面及公网 IP 查询 | 必需 |
| `campuslink-mwan3_0.2.0-1_all.ipk` | 根据认证状态控制 mwan3 接口参与分流 | 可选 |

三个组件独立版本号，按上表搭配安装即可。当前提供 **OPKG 的 IPK 包**，已在 Kwrt 25.12-SNAPSHOT 验证；APK 固件尚未验证。需要 ucode、支持 `ifhost!设备!IP` 的 curl 8.9+ 和 HTTPS 证书，依赖详情见[安装说明](docs/Install.md)。

将前两个 IPK 上传到路由器 `/tmp/`，在路由器上执行：

```sh
opkg install /tmp/campuslink_0.3.0-1_all.ipk /tmp/luci-app-campuslink_0.4.1-1_all.ipk
```

重新登录 LuCI，打开 **服务 → CampusLink**：

1. 在“插件设置”选择登录系统，填写校园网认证服务器。
2. 在“账号”和“登录配置”中添加账号、选择已有 WAN 及电脑/手机终端方式。
3. 启用线路并手动检查，确认正常后开启自动登录。

首次配置的线路和自动登录默认关闭。详细步骤、升级及卸载见[安装说明](docs/Install.md)。

## 可以做什么

- **多 WAN 登录**：为各线路分别绑定账号和终端方式，共用认证服务器与检查周期。
- **自动检查与重新登录**：查看每路状态及日志，对需要认证的线路执行登录。
- **查询出口 IP**：在总览手动查询各 WAN 的公网 IPv4，区分接口地址和公网出口，并显示查询时间。
- **可选 mwan3 联动**：在独立设置标签中，选择参与联动的接口、映射已有 mwan3 接口，并查看关联成员与实际状态。支持不同名称，最多 32 条映射。

联动组件仅控制选定接口是否参与分流，成员、权重和策略仍由 mwan3 管理。当前仅验证 **mwan3-nft 3.6.12-r4 / IPv4**；安装前请读[联动组件说明](packages/campuslink-mwan3/README.md)。

## 使用前了解

- 不同 Dr.COM 协议不能直接通用；需要确认学校使用的是 HTTP 门户。
- 插件使用已有 WAN，不自动创建网络接口或分流策略。
- “已联网”表示该线路可访问外网，无法确认当前校园会话实际使用哪个账号。“禁用”停止插件任务，不执行校园网退出。
- 公网 IP 查询访问固定的 IPIP HTTPS 服务，只代表到该站点的直连出口；代理或游戏加速器的出口可能不同。
- 多 WAN 的不同连接可能使用不同公网 IP。当前没有游戏专用分流或设备固定出口功能；游戏电脑需要稳定出口时，应在 mwan3 中另行配置规则。
- 联动遇到短时未知会保留上次资格，目前没有自动过期上限；停止联动会保留当时的成员状态。恢复原生探测需在 mwan3 中设置。

账号保存在路由器本地、仅 root 可读的配置中。反馈问题时请先删除账号、密码、Cookie 和公网 IP 等个人信息，不要上传完整配置或原始备份。

## 文档与开发

- [安装、升级、常见问题与卸载](docs/Install.md)
- [mwan3 联动配置与限制](packages/campuslink-mwan3/README.md)
- [当前状态与后续计划](docs/README.md)
- [架构](docs/Architecture.md) · [提供商扩展契约](docs/contracts/provider-v1.md)
- [0.4.1 公网 IP 验证](docs/testing/0.4.1.md) · [0.4.0 接口映射验证](docs/testing/0.4.0.md)

本机使用 Python 3 运行 `python scripts/check_release.py`，会检查可复现构建并生成三个 IPK 和插件源码包。路由器运行不需要 Python 或 Node.js。仓库根目录的历史登录脚本不作为当前插件的安装入口。

[MIT License](LICENSE)
