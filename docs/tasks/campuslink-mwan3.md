# MWAN-05：mwan3 联动（四路设备适配）

目标：关闭 mwan3 的独立 ping，由 CampusLink 的确定联网/未认证结果控制同名 wan1–wan4 的成员资格。

功能名为“mwan3 联动”，技术包/服务名为 `campuslink-mwan3`；名称与当前适配边界说明由 [CL-UI-03](school-removal-mwan3-naming.md)整理，未改变本任务已部署的运行规则。当前硬编码四路同名接口、IPv4 和特定 mwan3-nft 事件入口，未知/失联没有资格过期上限，不等同于通用链路健康管理。

依据：D-20261008-10 / REQ-003 / AC-014；用户确认独立联动设计后明确“那行，开始吧”。

范围：独立 ucode/procd 联动服务、mwan3 跟踪选项、物理事件失效处理与备份/回退。CampusLink 核心、账号、公共周期不变；网络/防火墙/无线、代理/VNT、固件与 bootloader 不变。

预期行为：逻辑接口一对一映射；明确联网才加入，明确未认证才暂停新连接分配，认证网口继续运行。检查中/临时 DNS 或未知错误保留上次资格；当前 worker 的 authenticating/verifying 已有未认证依据，先暂停直到复查通过。网口/IP/物理事件失效时作废旧证据，调用原插件检查刷新一次。插件重启/暂时失联/停止登录调度保留相同绑定的既有资格；冷启动缺证据保持离线。控制与状态仅写 /var/run，不反复写 UCI。

依赖：设备 mwan3-nft 3.6.12-r4 原生 connected/disconnected 事件、CampusLink 0.3.0 public status/interface/device/ip/last_check、ucode fs/ubus/uloop、现有四路源路由和原 WAN 兜底。

规模/风险：短产品任务，R1。错误判定可能降低或暂时阻断 LAN 分流，影响可用配置备份、定时回退和原管理/上网路径界定；不改变访问权限、不读取/写入校园密码。独立审查不自动触发。

验证：决策状态序列、短时未知/插件重启/接口-IP变化；真实 mwan3 控制事件与被动 NAT 证明三路/四路分布；ping 停止及恢复不被自行覆盖；物理接口与认证 HTTP 保留；mwan3/控制器重启、fw4 与管理可达、配置哈希。校园真实退出未支持，不借账号后台踢设备，使用受控假状态证明判定到实际分流链。

状态：实施和 R1 行为验证完成，2026-10-08 已部署到现有 Kwrt 路由器并启用开机启动。当前 CampusLink 四路与 mwan3 四路均在线，各 25%。本次为小型产品变更，不进入维护批次；完成 diff 自查，未进行独立审查。其他会话的插件实现与未提交修改保留。

恢复：部署前保存跟踪原值和配置，启动 1800 秒独立定时回退。设备验证通过后写入 confirmed，核对进程归属并停止该定时器；再次调用普通回退入口不改配置。手动强制回退见下文，只撤销此联动/跟踪选项，不回退插件或校园账号。

## 实现与运行

- [独立服务源码](../../packages/campuslink-mwan3/README.md)：纯决策模块、ucode 本地 ubus 读取、procd 服务、物理热插拔失效标记和原生 mwan3 状态适配器。仅管理 wan1–wan4，以 CampusLink connection.interface 对应逻辑接口，不按账号或 DHCP 地址猜测线路。
- 本地每 2 秒读取状态，不发外网请求。认证检查沿用插件原有共用 60 秒周期与重试/冷却；接口、地址或默认路由失效后，至多调用一次原插件 check 刷新，认证失败不触发额外高频检查。
- 删除四路 track_ip/track_method、track_gateway=0、initial_state=offline，因此没有 mwan3track ping 进程。该版本不支持用 track_method=none 停止 ping。联动持有原生 mwan3 锁，调用已安装 25-mwan3 的 connected/disconnected 分支，由 mwan3 更新策略与相关连接状态。
- 热插拔事件先将对应成员置离线；后续加入需当前设备/IP、完成时间和事件标记一致。检查中及 DNS/超时未知状态保留上次资格。已确认未认证后的 authenticating/verifying 先移出，登录 accepted 本身不恢复资格。
- 运行缓存仅在 /var/run，含接口绑定、时间和确定资格，无账号密码；服务短暂停止/重启可复用相同绑定的资格，整机冷启动没有该缓存时等待新证据。未改 CampusLink 核心、公共 RPC 或配置。
- [部署脚本](../../scripts/configure-campuslink-mwan3.sh)仅适用本次已验证设备，备份存在时拒绝重跑。已手动部署服务文件；附有 SDK Makefile，但未构建/安装 addon IPK，也未推送或公开发布。

成员移出会执行原生 mwan3 的相关连接清理，已有该路 TCP 可能中断；这项能力是新连接选路，不提供单 TCP 四路合并或无损迁移。

## 设备验证（20:24–20:46）

| 场景 | 实际结果 |
| --- | --- |
| 确定联网、检查中、认证/复查、未知错误、旧结果、事件/IP/路由失效等状态序列 | 已安装决策模块通过 25 项行为断言 |
| 模拟 wan4 明确未认证，生产联动继续运行 | wan4 保持离线；40 秒观察没有 ping 重新加入。最终 30 个新 HTTP 204 连接，wan1/2/3 各 10 个；额外 HTTPS 200 且证书验证通过 |
| 完成新的真实联网检查，恢复 wan4 | 最终 32 个新 HTTP 204 连接，四路各 8 个；额外 HTTPS 200 且证书验证通过 |
| 四路 DNS 失败夹具 | 保持原四路 25%，没有全部误剔除 |
| 实际停止 CampusLink 服务后再启动 | 失联期间维持相同绑定的四路资格；32 个 HTTP 204、四路各 8 个，HTTPS 校验通过；插件恢复后四路仍在线 |
| 实际重启联动、重启 mwan3 | 四路重新接入，ping 跟踪保持停用 |
| 实际 ifdown/ifup wan4，租约 .131 → .132 | 关闭后仅前三路各 33%；旧证据失效，新地址完成联网检查后恢复 25%，最终 NAT 地址为 .132 |
| 认证/管理与配置保留 | 四路分别绑定当前设备/IP 的域名 HTTP 探测均 204；SSH 与 LuCI 登录入口可达，fw4 check 通过；原 WAN 默认路由、network/firewall/CampusLink 配置哈希不变，插件 generation=15，UCI 缓冲为空 |
| 安装一致性与回退确认 | 五个安装文件与仓库 LF 规范源码 SHA256 一致；联动与 mwan3 已启用，回退定时器已停止，confirmed 后普通回退为无操作 |

客户端报告按原始源端口和目标地址逐连接匹配 conntrack，不用配置权重代替实际出口证据。最终四路地址为 .115/.114/.116/.132；均衡仍只匹配 192.168.0.0/24 从 br-lan 入站的 IPv4，校园认证请求继续绑定指定设备/IP。

验证边界：本校真实退出能力未支持，未踢出真实校园会话；认证失效使用脱敏状态夹具，但后续成员、策略、NAT 和客户端流量为真实运行。服务重启已测，整机重启、断开 SSH 等待定时回退、强制执行完整回退及长期会话故障率未测；不据此承诺固定检测时限或吞吐提升。

## 证据与恢复入口

- 本机私有证据：`.local/mwan3-link/`，含 portal-final.json、service-paused.json、final-four.json 与逐连接核验 summary.json，Git 忽略。
- 路由器备份/回退：`/root/campuslink-mwan3-link-20261008`。强制撤销此联动并恢复四路原 ping 跟踪：`sh /root/campuslink-mwan3-link-20261008/rollback.sh --force`。它停止/禁用联动、移除本联动热插拔文件，仅恢复原 mwan3 的四组跟踪键并重载；其他网络、账号及策略不回滚。
- 设备与本机证据档案 campuslink-mwan3-link-evidence-20261008.tar.gz 的 SHA256 均为 `12c6467fb956dc9a5b2b8cbdc36d17153d0fa8c75422cf5924c6537a64f50ff3`。归档含脱敏状态、原 mwan3 配置和恢复脚本，不纳入公开交付。
- 最终 mwan3 配置 SHA256：`fc7d39719b0e42cf948dd579fb230c8e7167df5990496cb73f3bfb45bebe4544`。network/firewall/CampusLink 的不变哈希见私有 final-files.sha256。

下一步：按实际使用观察联动；DNS 故障根因与另一测速节点对照仍由 MWAN-04 后续建议承接。代理与 VNT 继续按用户顺序后续处理。
