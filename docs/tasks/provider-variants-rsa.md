# CL-PROVIDER-02：深澜变体、锐捷 RSA 与开源试用发布

来源：用户 2026-10-15 接受调研建议，明确要求完善深澜变体、接入锐捷 RSA，执行离线测试，真实校园由其它用户反馈，并提交、上传和发布到仓库。
路线：产品变更短任务，承接 CL-PROVIDER-01；R2：扩大认证字段/参数发现及密码编码 → 错误目标/编码/状态可能泄露凭据、反复认证或回归旧系统 → 补充独立向量、模拟完整请求、负面分支、包冒烟与 fresh reviewer。

目标：深澜支持有依据的 error/res 响应、受限 AC ID 自动发现；锐捷增加明确选择的 RSA 零填充兼容模式、同源 pageInfo 公钥及编码变体。保留原手动 AC ID、非 RSA 表单与 Dr.COM。原配置 schema 2 兼容，不自动切换系统或试探多种算法。
非目标：其它协议、验证码识别、Cookie/CAS、退出/心跳、生产路由器部署；用户只授权仓库提交/推送/Release，本轮不修改原设备。
depends_on：原适配及[调研](../providers/research-20261015.md)、provider-v1、官方 ucode WASM 测试环境。已有未提交文件为本会话前轮成果，一并纳入发布，不覆盖其它工作。

## 验收

- AC-044：深澜允许填写 AC ID 或留空；留空仅从配置服务器同源的 Location/明确 meta refresh 获取唯一有效 AC ID，不默认猜 1，不跨源跟随，不改变 WAN IP。失败不发送挑战/密码。
- AC-045：error/res 一致或单独字段按已知值分类，冲突/未知/负面码不能接受；无状态字段的挑战须有合法 token、明确当前 WAN IP，且没有负面 ecode。原两种 HMAC 与手动配置保留。
- AC-046：锐捷 RSA 由管理员明确选择，公钥来自固定同源 pageInfo；校验公钥、MAC、输入长度和字符范围，公钥页未知、已显示验证码或缺钥时不发送登录；登录响应要求验证码则暂停，不降级明文。零填充编码使用独立 Python pow 和参考 JS 向量交叉验证；支持 1024/2048 位与标准指数，有界执行。
- AC-047：明确区分一次/双重表单编码；支持严格固定来源的字面门户跳转，拒绝任意 JS、跨源、重复/IP 不匹配参数；登录接受仍需 204 联网复查。密码/密文/原始响应不进入日志或 argv。
- AC-048：真实 ucode 模拟 worker、实际 curl 回环与 UI 回归、最终 IPK 解包冒烟、敏感信息审计通过，独立复核关闭问题。缺口保持：目标固件原生、多 WAN、真实校园未验证。
- AC-049：提交并正常推送 main，不重写历史；创建带实验性边界的 v0.4.2 试用 Release，附三个 IPK、源码 ZIP、SHA256SUMS；回读远端提交/tag，并下载附件逐项校验。旧稳定版继续可用。

## 状态与证据

实施：完成。验证：源代码离线通过，最终包解包后同一 233 断言/21 worker/curl 冒烟通过。审查：[fresh reviewer 聚焦复核通过](../reviews/provider-variants-rsa.md)，两项 P2 关闭。发布：已正常推送并公开为 v0.4.2 预发布版，附件下载/哈希回读通过；原设备未部署，见 [CL-REL-03](release-0.4.2.md)。

有效离线证据（2026-10-15）：官方 ucode WASM `2f62a446 2026-10-07` 执行 233 项断言、21 个真实 worker 场景，包括 RSA 的自动/手动、未知公钥、联网复查和深澜发现；实际 curl 回环 GET/POST/双重编码通过。Python stdlib 20 组 RSA pow 向量与固定 MIT 浏览器纯算法交叉一致；三个 UI 回归、mwan3 映射规则通过。Windows 子进程 sandbox 拒绝时在已授权的本地测试范围提权重跑；不将 EPERM 认作生产代码失败。WASM 适配和原生/学校缺口详见实验说明。

复现：`python tests/generate_provider_vectors.py`、`node tests/rsa_reference.cjs .local/provider-research/auto-body.js`、`node tests/run_provider_tests.cjs .local/provider-research/ucode.js`、`node tests/ui_config.cjs`、`node tests/settings_config.cjs`、`node tests/ui_view.cjs`。
开工 Git 基线：`fbfe83fffac524049a632bad764772d7fa067f55`，main；当时未提交的 CL-PROVIDER-01 与调研成果已一并纳入 v0.4.2。恢复时先核对 diff、本文和旧有效证据，只补受影响部分。构建仍使用现有 scripts/check_release.py，不引入路由器 Python/Node 依赖。
