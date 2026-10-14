# CampusLink mwan3 联动

独立可选服务，根据 CampusLink 联网检查结果控制 WAN 是否参与 mwan3 分流。产品功能名为“mwan3 联动”，包名、服务名及运行目录统一保留 `campuslink-mwan3`。0.2.0 提供独立 LuCI 标签、最多 32 条接口映射和关联成员/状态展示；已在原设备验证，见 [0.4.0 证据](../../docs/testing/0.4.0.md)。

## 下载与安装

从 [v0.4.1 Release](https://github.com/arctan303/CampusLink/releases/tag/v0.4.1) 下载 `campuslink-mwan3_0.2.0-1_all.ipk`，搭配核心 0.3.0 与 LuCI 0.4.1。需要已配置好的 mwan3-nft 3.6.12-r4 / IPv4 环境，传统 iptables mwan3 尚未验证。将 IPK 上传到 `/tmp/` 后执行：

```sh
opkg install /tmp/campuslink-mwan3_0.2.0-1_all.ipk
/etc/init.d/campuslink-mwan3 enable
/etc/init.d/campuslink-mwan3 start
```

先阅读下方接管条件，再重新登录 LuCI 配置“mwan3 联动”。服务启动后默认关闭、没有映射。完整流程及卸载见[安装说明](../../docs/Install.md)。

## 配置与使用

“mwan3 联动”标签单独保存总开关和映射，每行选择一个已有 CampusLink 来源接口及已有 mwan3 接口，显示引用目标的成员名称和实际分流状态。成员、权重和策略由 mwan3 自身管理。新配置默认关闭、没有映射，新行也默认停用；不自动接管所有 WAN。

配置保存在 `/etc/campuslink-mwan3/config.json`，与账号配置分开，保存不重启认证任务。每行含 `source_interface`、`mwan3_interface`、`enabled`，另有 schema_version=1、generation 与总 enabled；服务内部保留激活代号以保证修改无关配置不使已有线路抖动，不开放为可编辑 RPC 字段。来源及目标各自唯一，已删除对象可在停用后删除恢复。

启用前须在 mwan3 对选中目标关闭 tracking IP/gateway，并设 initial_state=offline，再按原生流程应用；本组件只检测冲突，不代替用户修改这些配置或全局重载。即使 UCI 已修改，仍在运行的原生 tracker 也会阻止接管。两端必须指向同一实际设备/IPv4；原生 target_4 网络解析在存在时优先，并在执行前按原生 helper 复核。名称映射不能把另一条线路的认证结果用于无关出口。

停用、删除映射或停止服务只停止联动控制，保留当时的 mwan3 成员状态；恢复原生探测需在 mwan3 设置。未选中的接口不受控制。

## 当前限制

- 当前源码不再限制 wan1–wan4，支持选择接口和不同名称映射，最多 32 条；目标必须是已经在 mwan3 正确配置的 IPv4 接口，不能仅手填别名制造新的路由出口。
- 依赖 mwan3-nft 的 nft chain、运行状态文件和 `25-mwan3` 原生事件入口；只验证 3.6.12-r4，不承诺传统 iptables mwan3 或其他版本兼容。
- 绑定与证据只处理当前 IPv4 地址，不支持 IPv6 健康资格；不创建虚拟 WAN、源路由、均衡策略或自动接管未配置的网络。
- 短时未知/插件失联保留上次资格，没有资格年龄上限；持续未知可能让已故障线路保留分流资格。认证检查有周期和退避，本地每 2 秒轮询不代表 2 秒检测外网故障。
- 移出成员可能中断原有连接，不提供无损迁移或单连接带宽合并。原 WAN 兜底是本次设备配置，其他环境须另行提供并验证。

接口配置化及状态展示已在原设备验证；其他后端/固件、更多真实接口/异名部署及长期未知策略仍有边界。原生规则的六路测试不等于六个真实出口验收。

## 文件与行为

- decision.uc：保留最近确定资格，检查中/未知 DNS 错误不误剔除；明确未认证或物理绑定失效时退出，新的联网复查通过才恢复。
- mappings.uc：配置、目标目录、唯一性和绑定纯规则；没有固定接口数组。
- daemon.uc / controller.uc：入口与独立 ubus 服务，每 2 秒读取本地状态；配置按 generation 原子保存，按显式映射匹配设备/IP 和完成时间，物理失效后至多请求一次原 check，不重复高频外网探测。
- apply.sh / apply-mapping.sh：共享原生 mwan3 procd 锁，复核已保存映射、版本、物理事件、两端绑定、目标启用/IPv4/跟踪冲突后调用原生 connected/disconnected，不关闭认证网口。
- 24-campuslink-mwan3 / events.sh：只标记当前选中来源与目标网络的物理事件，下次控制循环作废旧证据并退出，不直接操作其他接口。
- init.d/campuslink-mwan3：procd 管理。资格缓存仅在 /var/run，同绑定服务重启/失联保留既有判断，冷启动未知等待新检查。

原生 disconnected 会清理该成员相关连接，已有 TCP 可能中断；不提供单连接带宽合并。

## 设备基线、升级与验证入口

[旧部署脚本](../../scripts/configure-campuslink-mwan3.sh)仅适用 MWAN-05 的 0.1.0 固定四路候选，拒绝 0.2.0。当前 Makefile 和 `scripts/build_ipk.py` 均生成 0.2.0 addon 包；原设备已安装并启用，导入四条显式同名映射。此次更新脚本只用于已核验原设备，备份和恢复见 0.4.0 证据。

旧版本升级前备份旧文件、账号配置及 mwan3 配置；新 addon 初始关闭，需在独立标签中显式配置原四条来源/目标并启用。完成原生运行验证并保存映射后再安排重启，不能只替换文件就假设原四路已自动迁移。LuCI 新 ACL 需要重载 rpcd 并重新登录。新包卸载前会停用服务，但不会自动恢复原生跟踪。

```sh
ucode /usr/share/campuslink-mwan3/daemon.uc --dry-run
mwan3 status
/etc/init.d/campuslink-mwan3 status
ubus call campuslink.mwan3 get
```

`--dry-run`不更改成员状态。`--once [fixture.json]`供 root 隔离实验，会调用真实 mwan3 状态入口，必须配置独立 runtime/config；它没有开放为 RPC。原生决策验证源为 [mwan3_decision.uc](../../tests/mwan3_decision.uc)。本地执行 `node tests/mwan3_mappings.cjs`、`node tests/mwan3_native.cjs`、`node tests/ui_view.cjs`；前者在 Node 的 ucode 兼容子集适配器及假 fs/ubus 上执行相同业务源，后者运行真实 shell 并替换原生工具；均不代表目标 OpenWrt 运行验证。

其他路由器、mwan3 版本、接口命名或策略需先验证原生入口与绑定，不能直接运行此设备脚本。本次手动恢复路径、覆盖场景和验证边界见 [0.4.0](../../docs/testing/0.4.0.md)，旧固定四路证据保留在 MWAN-05。
