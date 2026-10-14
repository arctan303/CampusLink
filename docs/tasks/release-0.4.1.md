# CL-REL-02：GitHub v0.4.1 发布

依据：2026-10-14 用户明确要求推送云端、发布 IPK、将 GitHub About 改为简洁中文，并完善 README 等用户文档。承接 [CL-PUSH-01](repository-push.md)，本次新增 Release 与仓库介绍修改授权。

目标：同步已完成工作到 `arctan303/CampusLink` 的 main，发布 v0.4.1 及三个组件 IPK、干净源码包和 SHA256SUMS；用户可从 README 找到下载、安装与兼容边界。

范围：当前源码、测试、任务与验证记录、支持脚本；更新 README、安装说明、组件说明与发布说明。保留未实现需求的真实状态。非目标：再次部署路由器、修改固件/游戏分流规则、实现后续需求、改写历史提交或清理旧脚本历史。

路线与风险：发布准备短任务，R1。包载荷沿用已在目标设备验证的版本；新增影响为公开当前变更与下载资料，需防止本机凭据、原始日志和备份进入提交或 Release。使用 release-builder；自查和针对性验证，不扩展为无关维护队列的独立复核。

依赖：已验证核心 0.3.0、LuCI 0.4.1、addon 0.2.0；GitHub CLI 已登录仓库所有者，身份来自系统凭据存储，不写入项目。源同步起点 `4e234129e3dc4e5debd4dc5f77a2c049f59e087b`，开工 origin/main 与本地一致。

预期行为：默认分支正常推送，不 force push；tag 指向明确源码提交。Release 提供三包独立版本和安装说明，About 仅修改 description，保持其余设置。回读 main/tag/description/Release 与资产 SHA256，验证下载资产和本地字节一致。

验证与证据：复用 [0.4.0](../testing/0.4.0.md) 与 [0.4.1](../testing/0.4.1.md) 的原生、安装及设备载荷证据。发布前运行本地针对性回归、确定性打包、文档链接检查和 staged blob 敏感信息审计；私有证据、截图、配置、日志不进入公共源码或资产。既有 Git 历史不属于本次新增审计范围。

实施：用户文档与发布说明已整理。验证：本地 ui_config、settings_config、ui_view、mwan3_mappings、mwan3_native 均通过；184 个本地文档链接有效，diff 格式检查通过。三包确定性构建通过，LuCI/addon 哈希与设备交付证据一致，核心哈希见下表。实际 staged blob 的 67 个文本文件审计通过：与冻结候选一致、无暂存后漂移、JSON 有效，无私有路径或二进制，凭据模式命中仅为中文密码字段名、私钥检查器字符串和模拟事件 token；远端资产尚待回读。审查：R1 自查，无新增独立审查。发布：中文 About 已更新并回读，homepage 保持为空；尚未推送本轮提交或创建 Release。

| IPK | SHA256 |
| --- | --- |
| campuslink_0.3.0-1_all.ipk | 2b999bba84dfe6f6afd5971d8e7e957aabcc9210e03ef2d1708d9ea765f0a7a5 |
| luci-app-campuslink_0.4.1-1_all.ipk | c7e829a6d61af96a1c615cf27e85d45f95965fa9c175ddf56d9ef9df4977cac1 |
| campuslink-mwan3_0.2.0-1_all.ipk | 82d009af20e03535f1cf7e13dec1030525e11c964f2f19e8c618fb32a1311f50 |

恢复：源码出现问题用新提交修正或 revert，不改写远端历史。Release 需要撤回时可退为草稿或删除本次 Release，保留对应源码历史；路由器按升级前备份与旧 IPK 恢复，格式降级见安装说明。公网资产可能已经被下载，撤回无法收回用户副本。
