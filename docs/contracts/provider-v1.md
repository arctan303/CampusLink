# 提供商与旧学校配置兼容契约 v1

状态：0.3.0 公共设置契约，提供商/学校 metadata 仍为 v1，配置新增 schema 2 与字段作用域。原认证与权限证据见 [0.1.0](../testing/0.1.0.md)，界面简化见 [0.2.0](../testing/0.2.0.md)，本次公共配置见 [CL-UI-02](../tasks/plugin-settings.md)。[架构](../Architecture.md)说明调度；[provider schema](provider.schema.json)、[school schema](school.schema.json)供编辑器检查结构，运行时另执行语义校验。

D-20261013-15 / [CL-UI-03](../tasks/school-removal-mwan3-naming.md)移除产品中的学校选择；当前源码的学校 metadata、schema 与示例仅供旧配置加载兼容。页面保存先显式保留旧预设有效公共值及每路继承值，再清空 school；服务端 schema 1/2 与既有外部调用仍兼容。本次不删除已有 JSON 或更改公开配置格式，设备部署待执行。

## 身份与字段

提供商 ID 对应随包安装的代码注册表，不是路径或命令。首版支持 username_password，账号字段固定为 username/string 与 password/secret，均必填。新凭据类型需要同时扩展账号校验与页面，不仅添加 JSON。

元信息含 schema_version=1、id、label、credential_type、capabilities、account_fields、connection_fields。check/login 必须为 true；logout 可选；当前 0.3.0 heartbeat 必须为 false，保活通过周期检查与重新登录实现。

线路字段支持 string、enum、integer、boolean、url；secret 只用于账号密码。字段 ID 唯一，枚举值唯一，默认值与类型/范围匹配，min ≤ max。核心 validate_provider() 校验元信息和声明入口，field_value() 校验用户值，不要求各提供商重复实现 validate。

字段可声明 advanced=true，普通编辑表单折叠至高级设置；可声明 capability=logout/heartbeat，仅对应能力支持时显示。展示分类不免除后台校验。字段默认值负责填充隐藏的常规参数，旧配置仍可继承学校预设；不支持退出时不得要求用户补填退出 URL。

connection_fields 的 scope 默认为 global，位于插件设置；scope=connection 位于每条 WAN。Dr.COM terminal_mode 和 Mock scenario 为 connection，其余当前字段为 global。学校可提供两种字段的默认值；用户覆盖只能进入相应作用域。后台拒绝线路的公共参数或公共设置中的线路参数，不能仅靠隐藏输入保证唯一来源。

配置 schema 2 为 `{schema_version:2,generation,settings,accounts,connections}`。settings 含 provider、school、params、check_interval、retry_interval、retry_max；connection 只含 id、label、interface、account、params、enabled、auto_login。调度器以 effective_connection 把公共设置与线路参数合并后交给原 worker，出口绑定、冷却与密码保留仍按原规则。全局校验暂不要求无默认值的线路级必填字段，但每条实际线路校验仍必须满足它。

schema 1 旧配置仅在提供商/学校/周期相同，且所有公共字段的有效值一致时在内存升级，保持 generation、账号/密码、接口/开关、每路参数与有效端点，成功保存才写 schema 2。异构旧配置保持 schema 1 原调度，编辑线路前先由管理员在插件设置选择统一配置；不得自动选择一条线路覆盖其他线路。schema 2 保存不接受 schema 1 降级，旧 0.2.0 不认识 schema 2 而停止插件；回退必须恢复升级前配置。初次空配置也先在插件设置保存公共值。

URL 仅 HTTP/HTTPS，不含 userinfo 和控制字符；每字段最多 1024 字节。学校 defaults 只能包含此提供商声明的线路字段。verified 预设须附日期、环境和脱敏摘要；不表示所有学校/固件均兼容。

## 模块入口

| 入口 | 必需 | 合法 outcome |
| --- | --- | --- |
| check(ctx) | 是 | online / unauthenticated / indeterminate |
| login(ctx) | 是 | accepted / rejected / rate_limited / indeterminate |
| logout(ctx) | 能力为 true 时 | unauthenticated / rejected / rate_limited / indeterminate |
| resolve_params(params, context) | 可选 | 返回完整有效参数对象，失败抛出配置错误 |

resolve_params 在启动、保存、启用校验和发起操作时执行；输入为提供商默认值 → 学校默认值 → 公共覆盖 → 线路级覆盖，两个覆盖的字段作用域互斥；context 提供 provider、school、overrides 以区分继承值与显式覆盖。插件设置独立校验时可能没有线路级必填值，解析器须允许其缺省，由实际线路校验补齐；输出再次进行字段/URL/未知字段校验。它只解析配置，不访问网络、不执行认证或修改存储。持久化只保存覆盖，不写入派生完整 URL。没有此入口的旧提供商保持原行为。

ctx 包含 connection、account.values、params、route.device/ip、workdir、operation 和 allow_login。模块只通过 transport.http(ctx,url,params?) 发起绑定出口的 GET 请求，参数逐项编码。当前传输不包含 Cookie、POST 或通用 shell；新协议需要时先扩展传输并验证。

核心启动独立 worker，进程组包括 curl；禁用、配置变化、接口变化和服务停止会取消。模块不得修改 UCI、网络、防火墙或其他线路。新模块需在 daemon.uc 和 worker.uc 两处注册，不能通过网页上传代码。

## 结果与错误

```json
{"outcome":"accepted","reason_code":"auth_accepted","message":"登录请求已接受"}
```

retry_after_s 可选，必须为 0–86400 的整数。validate_result() 按操作校验 outcome、机器码、消息与重试时间，过滤控制字符并遮蔽账号值；无效结果成为 indeterminate/provider_contract_error。不附重复的版本/操作字段：模块注册和 worker 调用已经确定契约与操作。

online 必须有明确联网证据；unauthenticated 必须有门户证据。普通 200/302、DNS/超时、未知 JSON 不证明联网或密码错误。login accepted 后由核心 check，复查成功才展示已联网。已知凭据或永久拒绝用 rejected；未知码用 indeterminate/unknown_response，进入退避。

logout 必须确认此出口未认证才返回 unauthenticated/logout_verified，单纯接受请求不代表退出完成。核心先暂停此线路自动登录；无法核验作用范围时 capability 必须为 false。

UI/日志不接收原始响应、Cookie、密码、令牌或含凭据 URL。服务器内容脱敏后最多 240 字节，以文本渲染。稳定原因码包括 auth_accepted、already_online、portal_detected、invalid_credentials、rate_limited、dns_failed、connect_failed、timeout、binding_unavailable、unknown_response、provider_contract_error。

## 本校 Dr.COM HTTP

普通配置只输入 auth_server（IP/域名），生成 HTTP 801 端口的登录/退出路径及 HTTP 状态首页；新配置要求用户填写服务器或完整 URL，不默认选择旧本校预设。auth_url/status_url/logout_url 为高级完整 URL 覆盖，显式覆盖优先；旧配置只有完整登录和状态 URL 时仍可加载。probe_url 有默认值。服务器字段拒绝 scheme、端口、userinfo、路径或控制字符，非标准端口/HTTPS 使用完整 URL 覆盖。

插件设置编辑器仅把与同一服务器标准格式完全相同的旧 URL 收拢为服务器参数；后端同样识别旧学校的标准 URL 默认值，修改服务器后重新派生，用户显式 URL 覆盖与非标准学校地址继续优先。其他覆盖保留，并在高级设置中展示。编辑器在打开旧设置草稿时显式保留有效值并解除学校引用，只有保存才持久化；切换登录系统时清除旧公共参数，不再关联学校预设。切换系统只保留新提供商可接受的线路参数，不改变账号、接口和开关。

已验证 /eportal/portal/login、电脑/手机用户名前缀和终端参数；设备和 IPv4 来自 netifd。严格解析 JSON 或固定 dr1003 JSONP 包装，禁止 eval，result=10 不等于 1。ret_code=1 不作为通用限流判断，只按已知消息识别限流和密码错误。

探测期望 HTTP 204；明确未认证标记为 Dr.COMWebLoginID_0.htm，已认证页首注释为 Dr.COMWebLoginID_1.htm。静态 JavaScript 中的成功页面名不能作为登录状态。未知页面不触发自动登录。

2026-10-08 在本校四路验证登录和 204 联网。三个退出路径未能确认断开，自助后台要求验证码，因此正式 metadata logout=false。实际登录账号仍无法可靠核验。

## 贡献验收

协议相同的环境提供服务器/高级参数的脱敏配置说明；协议不同则添加代码、声明和协议样本。学校 JSON 及对应 schema 仅维护旧配置兼容，不作为新的学校目录入口。至少覆盖元信息语义、默认值、参数编码、成功/未知/拒绝/限流分类、出口绑定、取消和脱敏。真实账号仅留在贡献者设备，不写进配置示例、测试、截图或安装包。

测试入口见 [开发与安装](../Install.md)。Mock 模块用于独立测试；默认新线路为 Dr.COM，禁用并关闭自动登录。
