# CL-PROVIDER-02 独立审查回执

日期：2026-10-15。范围：HEAD `fbfe83fffac524049a632bad764772d7fa067f55` 以上提供商变更，重点 [AC-044–049](../tasks/provider-variants-rsa.md)。R2 风险为密码编码、目标/参数/状态错误可能导致秘密外发、错误登录或循环认证。用户授权离线实施及仓库试用发布，未授权原路由器部署。

Fresh reviewer：未参与实施的 `/root/provider_rsa_review`，同一实例首审/聚焦复核；主会话整理回执。此前 `/root/provider_review` 的非 RSA [历史结论](additional-providers.md)仅适用于未变基线，不替代本次审查。

首审不通过，两项 P2：深澜 AC ID 发现误继承锐捷专用 HTTP 200 字面 JS 分支；深澜检查阶段忽略矛盾的负面 ecode，从而打开自动认证门。

修复：深澜仅在 HTTP 301/302/303/307/308 读取 Location，200 仅解析明确 meta refresh；检查阶段 ecode 须缺省、空或严格零值。补充 JS 页面返回 ac_id_unavailable 且不发挑战/登录，以及负面、未知、错误类型 ecode 的自动 worker 回归。同一 reviewer 聚焦复核通过，两项 P2 均关闭，没有新增相邻发现。

首审独立复跑：222 项 ucode 断言、15 个实际 worker 场景、20 组 Python pow / 固定 MIT 浏览器 RSA 向量，以及三个 UI 回归通过。反例由 reviewer 在实际 VM 独立复现，不用源码匹配替代运行行为。修复后独立重跑 233 项 ucode 断言与 21 个实际 worker 场景通过；新增反例、原 RSA、编码与 Dr.COM 回归均通过。

边界：reviewer 的真实 curl 重跑遇到宿主 spawn EPERM，沿用主会话提权后回环通过证据；WASM fs/ARGV 与 transport 夹具适配、回环去掉 ifhost 行。目标固件原生、取消、多 WAN、RSA 原生性能、真实校园仍未验证。最终包及远端发布由主会话另行核验；维护 NET-06 不在本次审查范围。
