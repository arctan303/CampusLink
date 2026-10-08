# CL-UI-01 独立审查

日期：2026-10-08。执行者为未参与本次实现的 fresh reviewer。最新结论：**通过代码独立审查及第 2 次集成修复聚焦补查，CLUI-R01–04 保持关闭，无新增未解决问题**。原设备已更新 0.2.0-1 并完成主会话真实 LuCI 验收；reviewer 只独立核对代码与本地 Node 证据，未连接设备。补查时最终审计/清理仍进行中；后续主会话收尾结果另见末尾回执，不扩大独立审查范围。

## 范围与基线

- 有效契约：[界面任务](../tasks/ui-simplification.md)、[设计规范](../Design-Brief.md)、[Product Spec](../Product-Spec.md) AC-011/012、[提供商 v1](../contracts/provider-v1.md)，按 reviewer 技能及阶段契约执行。
- 首审基线为 `.local/ui-change.patch`，SHA256 `c73ad8d9a04677be66c479451299f80b9a7c78d5dfa549b44d7650dede823940`；首审开始与结束均逐项核对当时 `.local/ui-change-hashes.json`，登记文件全部匹配。`.local/ui-baseline/` 仅用于比较纯源码；未读取秘密、真实配置或 SSH key。
- 聚焦复核基线为新 `.local/ui-change.patch`，SHA256 `cc24eeae13023ea9a7adb7fc394045c6cba794a9dd2c64a913ff233aa3dafc6d`；开始和报告更新前，24 项登记文件全部匹配。关键 SHA256：main.js `8f3ab16b0052f5b1db8028456de60ebc43acf5db41770743dad4a3761ea2afa0`，config.js `104c7eaccd2b7e09bddad7fbfd54cb571438a38b828b0853c99fe02fb44b139c`，common.uc `152b140fd6d7299bda45de84838ce1e9da812ece85969b202293e01a47042a73`，drcom-http.uc `05a493fb7bdf488e996d2635c01885e89dc8884847b94a2b9923bdabc371dcf3`。报告自己也在该输入清单中；本次原位记录结论会改变报告哈希，运行代码未修改。清单中的 mwan3 脚本/任务属于范围外内容，不计为本次已审查成果。
- 第 2 次补查开始时的 `.local/ui-change.patch` SHA256 为 `7f475357363da5d3158e6afc1d489d513ca7d4e72a44ff896e68ea5e4f36e7c0`，30 项登记文件全部匹配。本轮运行代码基线为 main.js `7ec7cac467d70998ff8649c06165f42d274181f21ae5f96356efed310b3c1030`、config.js `65082762b28283fd54f3242314ddecddfaccbe627027bdd40c543a4b49db4fc6`；后台 common/daemon/drcom 等保持第 1 次通过基线。补查期间主会话只修订 Architecture 历史表述、provider-v1 版本文案及 Design-Brief 字段分区的残留词语，本报告也原位更新；报告落盘前所有相关运行代码/测试哈希仍匹配。未将其他网络任务纳入补查。
- 核对 LuCI 四标签、列表及局部编辑、内联账号原子保存、密码保留、Dr.COM 参数解析、学校兼容、schema、后台调用点及相关打包脚本。没有修改运行代码，没有连接或操作路由器。
- R2 依据：参数派生改变认证请求目标；账号或整体配置保存错误可能向错误服务器发凭据或覆盖其他 WAN。路线为产品变更、短任务；没有因文件数或文档格式扩大风险。

## 首审原始发现（均已关闭）

下述行号、代码缺陷与失败证据描述的是首审基线；各项修复和关闭依据见后面的聚焦复核表。

### CLUI-R01 / P1：旧学校的标准完整 URL 默认值阻止新服务器生效

证据：[前端 defaults/lineDraft](../../packages/luci-app-campuslink/htdocs/luci-static/resources/campuslink/config.js) 4–30 行、[合并](../../packages/campuslink/files/usr/share/campuslink/common.uc) 56–73 行、[解析](../../packages/campuslink/files/usr/share/campuslink/providers/drcom-http.uc) 14–24 行。学校 v1 仍允许默认值声明完整 URL；核心先把学校 URL 合并进 params，解析器只在 URL 缺失时派生。前端却从标准旧 auth_url 推断出可编辑的 auth_server。

复现：使用合法旧式学校 defaults `auth_url=http://old.example:801/eportal/portal/login`、`status_url=http://old.example/`、标准 logout_url；线路仅覆盖终端方式。`lineDraft()` 后把 auth_server 改为 `new.example`，有效参数仍含旧学校的登录/状态 URL。对前端模型运行本地 Node 场景，结果为：

```json
{"visibleAuthServer":"new.example","persistedOverrides":{"terminal_mode":"pc","auth_server":"new.example"},"effectiveLoginUrl":"http://old.example:801/eportal/portal/login","effectiveStatusUrl":"http://old.example/"}
```

这是前端模型执行与解析代码核对的证据，不冒称此场景已在 ucode/设备运行。当前内置 local-campus 已改为 auth_server 默认值，因此本例不直接改变现有四路的请求目标；但仍合法的旧学校预设会显示新服务器而向旧目标认证。

修复方向：按来源区分学校默认 URL 与用户显式覆盖，把同一服务器标准格式的旧学校默认端点归一化后再应用服务器覆盖；前后端采用相同规则。保留用户显式 URL 和非标准学校默认 URL，不能把所有完整 URL 一律重写。回归需覆盖旧学校标准默认 URL + auth_server 覆盖、特殊学校 URL、用户显式特殊 URL。

### CLUI-R02 / P2：填写完整 URL 后服务器的必填条件没有更新

证据：[main.js](../../packages/luci-app-campuslink/htdocs/luci-static/resources/view/campuslink/main.js) 144–148 行。auth_server 的 required 只在 draw 时按现有 auth_url/status_url 决定；高级输入 change 后不会更新它。

本地最小 DOM 执行当前页面：新建线路后将服务器留空，填入完整 HTTPS auth_url 与 status_url；服务器 required 仍为 true，form.reportValidity() 返回 false，点击保存未发出 RPC。后台解析器允许完整登录/状态 URL 配置而无服务器；契约也把非标准端口/HTTPS 放在完整 URL 覆盖中。新建手动特殊端点配置会被前端拦住，用户须额外重绘或填入无用服务器才能绕过。

修复方向：每次相关 URL/服务器输入变化时，依据有效参数动态更新服务器必填条件。回归应从全新手动配置开始，完整 URL 有效且服务器为空可保存；缺少登录或状态 URL 时仍要求服务器。

### CLUI-R03 / P2：晚返回的轮询可回退成功保存后的快照

证据：[main.js](../../packages/luci-app-campuslink/htdocs/luci-static/resources/view/campuslink/main.js) 31–35、84–86、117–123 行。轮询无条件接受 next；操作和保存后的回读也没有统一快照新旧检查。

独立 Node 页面 RPC 队列执行：先启动 generation=7 的轮询，随后保存成功并回读 generation=8；最后让旧轮询返回。当前 data/config 都回退为 7，新开编辑弹窗继续提交 expected_generation=7。后台拒绝陈旧保存，故没有证据表明存储被覆盖，但刚保存的页面外观会回退，下一次编辑出现无效冲突。

```text
configGenerationAfterSuccessfulSave=8
configGenerationAfterLatePoll=7
next save expected_generation=7
```

修复方向：所有快照接收走统一入口，拒绝比当前已接受 generation 更旧的配置；保持编辑草稿冻结规则。回归覆盖保存前发起的轮询在成功回读后返回，以及 action 回读与 poll 的乱序。

### CLUI-R04 / P2：折叠高级设置中的无效数字输入无法显示校验位置

证据：[main.js](../../packages/luci-app-campuslink/htdocs/luci-static/resources/view/campuslink/main.js) 107–109、158–161 行。保存直接执行 form.reportValidity()；没有 invalid 处理或先展开含无效字段的 details。

在独立 Edge 会话的本地 data: 表单验证相同原生控件组合：关闭 details，内含 required number/min=10/max=600/value=0，点击保存调用 reportValidity。结果 `valid=false, advancedOpen=false, activeElement=save`，控制台报 `An invalid form control with name='' is not focusable.`。这证明原生校验不会自动展开该控件；对应页面中用户先改错重试数字、再收起高级设置，会无反馈地无法保存。此证据只针对原生控件组合，不声称完整 LuCI 浏览器流程已验收。

修复方向：保存前或 invalid 事件中展开首个无效字段的折叠容器，然后显示并聚焦该字段，或在弹窗错误区给出明确字段原因。[HTML 标准的交互约束校验](https://html.spec.whatwg.org/multipage/form-control-infrastructure.html#constraint-validation)也允许未渲染控件导致脚本错误，不能依赖浏览器自动展开。

## 第 1 次聚焦复核

| 项目 | 结论及新证据 |
| --- | --- |
| CLUI-R01 | 关闭。common.merge_params 把 provider/school/overrides 来源传给解析器；解析器只删除继承自旧学校且精确匹配同服务器标准格式的默认 URL，用户显式及非标准 URL 保留。前端 defaults 执行相同标准默认归一化，未修改安装预设。独立运行新版 ui_config 通过；另运行 Node 相邻场景确认特殊学校状态 URL、显式标准 URL 与新服务器并存时仍保留覆盖。主会话目标临时 ucode 验证旧学校无覆盖、改服务器、显式 auth URL 优先并派生新 status URL 均通过。 |
| CLUI-R02 | 关闭。服务器必填按有效完整 URL 计算，并随字段变化更新。独立运行 ui_view 的 manualUrls：从全新手动配置填入完整 HTTPS 登录/状态 URL、服务器为空，可发出一次保存 RPC；backend 仍负责校验实际 URL。 |
| CLUI-R03 | 关闭。poll/action/save 回读均使用 acceptSnapshot，拒绝低于已接受 generation 的快照；编辑中的 cfg/base/draft 仍冻结，取消后回到最新接受配置。独立运行 delayedPoll：保存并回读 8 后，晚返回的 7 不再回退；重复点击仍只保存一次。conflictDraft 证明轮询不覆盖草稿，关闭编辑器后接受最新 generation。后台冲突拒绝沿用首审代码证据及新版实际 RPC 证据。 |
| CLUI-R04 | 关闭。保存先 checkValidity，对 :invalid 的 details 祖先展开，再 reportValidity。独立运行 hiddenInvalid 通过；用隔离 Edge 本地 data: 原生表单执行相同修复逻辑，结果 `valid=false, advancedOpen=true, activeElement=retry`，控制台 0 错误，证实错误输入可被聚焦。 |

独立命令：`node tests/ui_config.cjs`、`node tests/ui_view.cjs` 均通过；后者 manualUrls/delayedPoll/hiddenInvalid/conflictDraft 全部通过。本轮只聚焦上述修复与直接相邻回归，没有新增可执行问题，没有连接路由器。

主会话另提供新版目标临时源码 provider/drcom_params、daemon 编译及私有注入发布审计通过，以及新版临时实际 RPC 的手动服务器、HTTPS 完整 URL、非法保存不改原配置、冲突与密码保留通过。原 mock 回归在聚焦复核交接时仍重跑中，未把这次重跑写为已通过；此前已通过证据仅按未受影响范围复用。任何后续设备验收应记录实际结果，而非从本轮代码结论推导。

## 第 2 次聚焦补查：真实 LuCI 集成修复

本轮只覆盖真实页面发现的模块导出与 HTML 布尔属性问题，以及删除按钮/Mock 标签的直接相邻影响，没有重启全范围审查。

- 辅助模块增加 require baseclass 并返回 baseclass.extend，符合 LuCI 模块须提供构造器的集成形式；各模型函数及参数优先级保持原逻辑。独立 Node 以构造器/原型形式的 baseclass stub 执行模块，确认返回 function，实例可调用 copy/endpoints；此本地检查不冒充完整 LuCI loader 验证，主会话实际页面加载证据补足集成部分。
- input() 在传给 E 前删除 false/null/undefined 属性，避免 required=false 仍生成 HTML required 属性。独立检查确认 false required/max=null 不传入 E，true required、value="0"、min=0、autocomplete 及数字输入事件均保留。直接相邻的密码留空和高级空白 URL 由 defaultSave 覆盖；提供商字段更新服务器 required 的 DOM 属性规则保持有效。
- 独立重跑 `node tests/ui_config.cjs` 与 `node tests/ui_view.cjs`：全部通过，页面的 defaultSave/manualUrls/delayedPoll/hiddenInvalid/conflictDraft 五个场景通过。fixture 已按 HTML 布尔属性存在语义处理 required，不再把 required=false 误当作可选。原有特殊覆盖、账号原子构造、密码保留及旧轮询防回退的有效证据仍适用。
- 删除弹窗仅把主按钮标签改为“删除”，复用原提交/防重复/冲突路径，账号引用保护未改变；Mock 列表移除重复提供商名，Dr.COM 仍显示提供商与终端方式。未发现新增代码问题。
- 文档补查发现 Architecture 仍把 0.1.0 简化缺口写作当前状态；主会话已原位改为历史基线，并写明 0.2.0 实现及证据链接。provider-v1 heartbeat 表述同步当前版本，false 约束未改变；Design-Brief 高级字段中的“名称/启用”残留已改为“名称”，基础表单的启用开关规则与实现一致。已核对这三项说明修订，不要求重复运行行为测试。

主会话新增设备证据已记录于 [0.2.0 验证](../testing/0.2.0.md)：真实页面完成 WAN1 原值保存、错误重试字段展开聚焦/取消、停用 Mock 与内联假账号一次创建、账号空密码保存及路由器内保留比较、测试线路/账号删除、四标签、键盘和 390px 小屏。升级后与备份逐字节一致；完成页面测试后 generation=9，原两账号（含密码）与四 WAN 全部字段保持备份值，四路在线，network/firewall 哈希不变，原 eth0 HTTPS 200。

报告落盘前主会话进一步回读服务 0.2.0 running、两账号四路 online、无密码回读，安装的 main/config/style/common/daemon/drcom 哈希与当前源码一致；HTTP ACL read=0、write/action/anon=-32002。这些是主会话授权设备操作的结果声明及相关验证文档，reviewer 未读取秘密、截图或连接路由器重跑，不把它们标为 reviewer 独立设备证据。最终包可复现/源码清洁/私有注入审计与临时测试目录、访问密钥清理尚待完成；此前包审计不自动证明本次最后产物已完成。

## 已核对的保护与证据边界

- 独立运行 `node tests/ui_config.cjs`：通过标准旧线路 URL 收拢、特殊覆盖保留、单线路修改与取消不改原数据、内联账号一次构造、账号复用、空密码保留及页面语法检查。
- 首审独立页面 RPC 队列：连续保存点击只发一次 RPC；保存中 saving/save.disabled 生效；冲突返回保留弹窗并显示错误。当时同时发现 CLUI-R03；其后关闭证据见聚焦复核表，首审局部通过项不被追写成当时全面通过。
- 代码核对：编辑对象/base 均复制；后台整体保存先校验并原子写入，账号引用与 generation 检查保留；密码不回读，编辑留空省略 password 后由旧账号值保留；其他账号/WAN 配置进入同一候选但没有被本次局部编辑重写。显式非标准 auth/status/logout/probe 覆盖保留。
- resolve_params 在启动、保存、启用及发起操作调用，解析结果再次执行字段/URL/未知字段校验；没有新增网络访问、ACL、出口绑定或凭据传输方式。本轮不把未修改的这些路径再次扩展成全仓审计。
- Dr.COM logout=false 对应输入/按钮隐藏，logout_url 不再必填；新线路默认禁用、关闭自动登录，启用字段可见。正常行只呈现联网状态及绑定账号，未宣称实际身份，也没有恢复已撤销的常驻身份未知提示。
- 首审主会话提供的证据：目标路由器临时源码 provider.uc/drcom_params.uc、daemon 编译通过；私有注入的敏感信息检查及可复现包检查通过；isolated mock RPC 回归通过。新版证据状态见聚焦复核段。reviewer 没有连接设备或读取秘密来重跑这些项目，结论采用已声明范围，不能冒充独立设备证据。
- 首审与第 1 次复核时，需求、设计和任务承接待实施/验收范围，入口描述当时运行 0.1.0。第 2 次补查已核对 Product Spec、任务、入口与新版验证记录原位同步 0.2.0 的实际实施及验收，发布收尾单独保留进行中；未把本报告当作打包、设备或清理状态的替代证明。

## 剩余工作与恢复条件

首审四项已由同一 fresh reviewer 第 1 次聚焦复核关闭，真实 LuCI 集成修复经第 2 次补查通过，无剩余代码问题或需继续修复的门禁。运行代码若再有实质变化，仅补受影响证据；无需对相同输入再启动 reviewer。

设备与真实 LuCI 流程已按上述主会话证据验收。补查时下一步为完成最终产物审计、临时访问材料清理及收尾记录；原生 Edge 小表单与本地 Node 只证明各自范围，不能替代真实设备证据。

## 主会话发布收尾回执

以下为实现/部署主会话追加，非 reviewer 独立执行：最终安装文件 SHA 与当前源码匹配，四路在线，原账号/密码/线路与备份一致，HTTP ACL 通过；IPK 双构建和私有凭据注入审计通过，干净源码 ZIP 已生成。仅本次 mock 进程/临时目录及 authorized_keys 中精确匹配的测试 key 已移除，正式服务仍运行。详情及产物 SHA 见 [0.2.0 验证](../testing/0.2.0.md)。运行代码在第 2 次通过后未改变，无需重复同输入审查。
