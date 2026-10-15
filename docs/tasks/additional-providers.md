# CL-PROVIDER-01：从学校开源工具接入其它登录系统

来源：用户 2026-10-15 明确要求自行寻找 GitHub 上学校登录工具，分析认证原理并接入；用户没有其它校园环境，接受先做离线验证、后续由对应用户反馈。
路线：产品变更，短任务；两个适配共享现有接口并可独立验证，不拆 Phase。
风险 R2：新增密码衍生参数与 POST 传输 → 错误目标/编码/状态分类可能泄露凭据或反复认证，并影响原 Dr.COM 请求 → 补充算法向量、请求流程/目标约束、未知响应拒绝、传输回归及 fresh reviewer。

## 目标、范围与非目标

新增实验性 `srun-srbx1`（深澜 SRBX1）及 `ruijie-eportal`（非 RSA、免验证码表单）模块，使用现有账号、WAN 绑定、调度和 LuCI 声明字段。资料分析见[研究与试用说明](../providers/experimental.md)。
非目标：所有同厂商变体、802.1X/UDP 客户端、验证码识别、RSA、退出/专用心跳、生产部署或发布；不改当前路由器/账号/网络和并发等其它待开发能力。
depends_on：现有 provider-v1、统一 HTTP 传输及开源协议资料，无需真实账号。

## 预期行为与验收

- REQ-014 / AC-038：登录系统列表包含明确标为实验性的两个模块；新线路仍默认关闭；切换系统沿用现有保存与凭据保留规则。
- AC-039：深澜状态 `not_online_error` 才允许认证；获取新挑战后按选定 HMAC 变体构造 SRBX1 信息及校验和，使用当前 WAN IPv4；挑战未知/缺失、IP 不一致不发送密码衍生参数。
- AC-040：锐捷仅接受当前绑定出口探测得到的、与配置服务器同源的 `/eportal/index.jsp` 重定向；每次登录重新获取查询参数，向固定同源登录接口 POST；普通 200/跨源跳转/未知内容不发密码。RSA/验证码不宣称支持。
- AC-041：未知/超时/已接受但复查失败不报已联网；只有联网探测 204 证明在线。新模块使用固定提示而不转发服务器原文/令牌。
- AC-042：GET 编码与原安全选项保持，POST 字段逐项编码；密码及派生参数仅经私有配置交给 curl，不进入命令行；回归 Dr.COM。
- AC-043：执行实际 ucode 的算法向量、模拟请求流程、元数据与配置/UI回归；记录真实网络/固件的验证缺口。独立审查针对同一最终 diff。

## 状态与恢复

实施：完成，本地核心 0.4.0 / LuCI 0.4.2。验证：离线范围通过，边界见下文。审查：[独立复核通过](../reviews/additional-providers.md)，首审三项 P2 均已关闭。发布/部署：未执行。
基线：`fbfe83fffac524049a632bad764772d7fa067f55`，开始时 Git 工作区干净。当前线上仍为核心 0.3.0 / LuCI 0.4.1。
恢复：核对工作区 diff、本文与研究记录；仅继续本任务，测试依赖和资料缓存放在忽略目录 `.local/provider-research/`。

## 验证证据（2026-10-15）

- `python tests/generate_provider_vectors.py`：独立标准库参考生成并固定假数据向量，MD5/SHA-1 分块边界、HMAC 长密钥、两种 HMAC 和 SRBX1 完整信息/校验和。`node tests/run_provider_tests.cjs .local/provider-research/ucode.js` 在官方 ucode VM `2f62a446 2026-10-07` 完成 134 项针对性断言；元数据/配置、挑战与 IP、未知状态/错误分类、跨源/重复与编码参数拒绝和 Dr.COM 请求回归通过。另 `node .local/protocol-golden.cjs` 对照 PUMC 固定 `srun_test.go` 外部向量，密文/HMAC/校验和三项一致。
- 同一运行器执行实际 worker 的 11 个流程：仅检查不开自动登录、手动登录成功、接受后复查失败、未知状态不登录、锐捷手动/自动 POST、真实密码不匹配及 E2531/E2553 拒绝、E2532/E2533 冷却。明确断言原因码和 90 秒冷却不丢失；结果不含密码，只有 204 才为 online。daemon 的既有 rejected→paused 与 rate_limited→cooldown 映射未修改，本轮没有重新执行原生 daemon。
- 真实 curl 回环 HTTP GET/POST：用户名/密码含 `&=+%`、引号、反斜线与 Unicode，服务器解码后逐字段相等且没有额外字段；queryString 内原有 `%26` 保持，POST URL 不带密码。Linux `ifhost` 行在 Windows 回环检查中排除，其生成配置仍有设备/源 IP、无代理、禁止跟随和协议限制断言。
- `node tests/ui_config.cjs`、`node tests/settings_config.cjs`、`node tests/ui_view.cjs`：原界面回归及新增系统实际表单/必填 AC ID、保存、切换、密码保留通过。
- `python scripts/check_release.py`：两次 IPK 构建一致、包路径/权限/JSON 与干净源码检查通过；生成 `dist/campuslink_0.4.0-1_all.ipk`、`luci-app-campuslink_0.4.2-1_all.ipk`、原 addon 0.2.0 及源码 ZIP。不含本机 `.local` 调研/账号资料；本轮没有读取/注入任何真实凭据，未使用 `--secrets`，不把检查宣称为真实凭据审计。
- 缺口：WASM 适配了 fs 导入及 worker 上下文入口，替换了 HTTP 响应；未跑目标固件原生模块/daemon ubus、真实多 WAN、取消进程和其它学校认证。现有原设备证据仅适用于未变化路径，不能直接证明新增适配已实测。用户接受先离线试用的范围不扩展为生产部署授权。

范围承接：本任务保留首批非 RSA 的历史验收；2026-10-15 用户批准扩展深澜变体、锐捷 RSA 和仓库试用发布，见 [CL-PROVIDER-02](provider-variants-rsa.md)。本任务旧独立结论不覆盖新 RSA diff。
