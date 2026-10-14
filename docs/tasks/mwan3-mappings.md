# CL-MWAN-06：mwan3 联动标签与接口映射

目标与依据：用户要求单独设置分栏，选择哪些接口参加联动并配置名称映射；已选择“mwan3 接口，并显示关联成员名”，后续授权按合理方案实现。D-20261013-16，承接 CL-UI-03 与 MWAN-05。

范围：第六个原生 LuCI 标签“mwan3 联动”；独立 addon get/save RPC、配置版本与原子保存；总开关和逐行启用、CampusLink 来源接口 → 已有 mwan3 接口的一对一映射；只读成员名与运行结果；daemon/apply/hotplug 消费同一映射，不再硬编码四路。

非目标：不公开发布或推送，不改账号/认证调度/网络/防火墙/代理；不创建 mwan3 接口、成员或策略，不自动改原生跟踪配置，不支持 IPv6/传统 iptables 后端，不引入长期未知过期策略。

预期行为：新安装默认关闭、空映射；只有明确启用的映射能控制目标，源/目标不重复，目标必须存在并为启用的 IPv4 接口。目标独立跟踪须关闭且 initial_state=offline，运行时存在 tracker 时暂停控制并提示。成员名称从 mwan3 配置只读派生，不作为控制对象。两端实际设备/IP 必须一致；native mwan3 的 target_4 网络解析在存在时优先，无匹配绑定时不能借源线路结果操作另一出口。停用/移除仅释放联动控制、保留当时成员状态，用户需在 mwan3 恢复原生探测；不隐式重载全局选路。

配置：独立 `/etc/campuslink-mwan3/config.json`，schema_version=1、generation、enabled、mappings（最多 32 项）；每项 source_interface、mwan3_interface、enabled。无账号或凭据。RPC `campuslink.mwan3.get/save` 使用现有 LuCI 管理读/写权限；配置并发冲突保留草稿，保存不重启认证任务。

依赖：已存在的 CampusLink WAN、mwan3-nft 原生 connected/disconnected 入口及跟踪预置。旧固定四路部署升级前须先导入显式映射；2026-10-14 用户授权部署，先隔离验证原生 VM/RPC，再备份及更新界面与联动服务，保持认证核心运行。缺 addon/旧 addon 无 RPC、缺 mwan3、跟踪冲突、映射对象失效均展示可解释状态，认证页面继续可用。

路线/规模/风险：产品变更、单一可验收短任务、R1。错误映射可能把一条线路的认证结果应用于另一出口；以来源/目标唯一性、已存在目标、两端实时绑定和执行时复核限定目标，且不写 mwan3 UCI、不全局重载、不接管未选线路。停用不恢复跟踪这一边界明确展示，不宣称自动恢复。

验收：动态接口名及超过四路映射；重复/未知/IPv6/跟踪冲突拒绝；源/目标不同名但同绑定可联动、不同绑定不变更目标；配置切换及物理事件使旧证据失效；未选线路/停用不触发 apply；实际成员状态和错误可见；addon 不可用时其余标签正常；保存/取消/冲突/重复提交/旧轮询不丢草稿。

状态：2026-10-14 实施、打包和原设备部署完成，R1 diff 自查；本地逻辑/交互、原生 ucode/ubus、真实 LuCI 保存与实际三路排除/四路恢复通过。未独立审查、未公开发布或推送，详见 [0.4.0 交付证据](../testing/0.4.0.md)。

验证证据：`node tests/mwan3_mappings.cjs`、`node tests/mwan3_native.cjs`、`node tests/ui_view.cjs`、`node tests/settings_config.cjs`、`node tests/ui_config.cjs` 最终均退出 0。映射测试用 Node 适配 ucode 的 ECMAScript 子集和内置函数，并提供假 fs/ubus/UCI cursor，不是原生 VM 验证。目录使用只读 UCI cursor.get_all 并声明 ucode-mod-uci 依赖，不通过需要会话的 rpcd UCI 读取，也不提供 set/commit；服务发布与本地请求使用独立 ubus 连接。隔离 native 测试执行真实 apply-mapping/events shell，仅 native 工具与系统目录替换为 `.local/mwan3-mapping-tests/` 下夹具；Git Bash 信号管道需要沙箱外执行，未连接路由器或执行真实选路。两个 shell 的语法检查通过。

覆盖：动态六路、成员目录、重复/未知/IPv6/非法名称与控制字符/独立探测冲突、不同名同绑定及 native IPv4 别名、错绑定不操作目标、原生 tracker 仍运行、旧配置/事件拒绝、物理来源失效、未知保留、停用/未选隔离、配置持久化与损坏加载、原子失败/版本冲突、无关保存不抖动；页面独立保存（认证保存计数保持 0）、草稿跨标签、恢复/冲突/防重复、状态刷新不盖输入、失联后旧版本不回退、组件不可用时认证仍可用。原学校移除回归继续通过。

相关文件：LuCI main/config 与 ACL；addon mappings/controller/decision（decision 未改）/apply-mapping/events 及兼容入口、Makefile；新增映射与 native 测试，原页面测试扩展。旧设备专用部署脚本加候选版本前置拒绝，防止把新版本当成固定四路直接停用跟踪；未运行该部署脚本。

恢复检查点：保留原会话前未提交修改；原设备当前为核心 0.3.0 / LuCI 0.4.0 / addon 0.2.0，四条显式映射、generation 2、服务运行并启用。备份和手动恢复命令见 0.4.0 证据，自动回退已确认解除；无必须待执行动作。其他设备/后端/长期稳定性不在本次验收范围，未重启路由器。

依据：接口/成员分层和原生 IPv4 网络解析已核对维护者 [mwan3 README](https://github.com/dl12345/mwan3/blob/openwrt-25.12/README.md)、[common.sh](https://github.com/dl12345/mwan3/blob/openwrt-25.12/files/lib/mwan3/common.sh)及[原生事件入口](https://github.com/dl12345/mwan3/blob/openwrt-25.12/files/etc/hotplug.d/iface/25-mwan3)；UCI cursor/get_all 核对 [ucode 官方模块文档](https://ucode-lang.org/ucode/module-uci.html)与[官方实现](https://github.com/jow-/ucode/blob/master/lib/uci.c)。这些当前上游资料不能代替已安装 3.6.12-r4 的回读与新版本设备验证。

2026-10-14 部署状态：D-20261014-17 授权已执行，原不部署限制被替代；LuCI 0.4.0 与 addon 0.2.0 安装、回读及针对性行为验证完成。原生编译暴露的 export 分号问题已修复，最终包及设备载荷一致。原来没有 SSH 测试身份的缺口已由用户提供当前凭据解决，凭据只用于连接。
