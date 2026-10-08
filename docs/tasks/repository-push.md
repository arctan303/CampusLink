# CL-PUSH-01：同步仓库至 GitHub

依据：2026-10-08 用户明确要求推送一次仓库变更到云端。目标为已有 origin `git@github.com:arctan303/CampusLink.git` 的 main 分支。

范围：CampusLink 0.3.0 源码、构建工具、测试、项目文档、已完成网络任务的支持脚本及项目工作流。非目标：GitHub Release、安装包上传、再次设备部署、改写 Git 历史。忽略本机测试资料、浏览器日志、构建产物及含硬编码凭据的历史脚本副本；既有已跟踪脚本保持原样，不将此记录视为历史凭据清理。

风险 R1：发布当前已验证工作到原仓库，审计实际提交新增/修改的内容，避免把本机账号、密码、私钥或日志加入云端。原插件的 R2 运行变更复用核心、界面及公共设置独立复核与设备证据，不重复运行相同审查。网络任务脚本沿用各自任务验证，不扩展插件 reviewer 的覆盖范围。

依赖与证据：原 main 为 `8607acb60486cbb14b0a7d3e2ea2ff6b18946cac`，远端回读与本机一致；0.3.0 设备及打包证据见 [测试](../testing/0.3.0.md)。提交前检查实际 staged blob、凭据/私钥、路径、格式和文件漂移；推送后回读远端 main 的 commit ID，禁止 force push。

状态：本次仓库同步完成。源码提交 `08ff6df18f04ebd5eebd988caa03265542874fd9`（`feat: add CampusLink 0.3.0 OpenWrt login manager`）已正常推送至 origin/main，独立 `git ls-remote --heads origin main` 回读与本机提交一致。111 个新增/修改文件的 staged blob 检查通过：无提供的账号/密码、真实私钥或令牌，无排除路径或暂存后漂移，JSON 有效；`git diff --cached --check` 与确定性构建/交付审计通过。保留已有运行验证与独立审查，不声称重新运行所有设备场景。

同步后更新本文件和现状入口，文档回执单独提交。授权仅为本次仓库同步，没有创建 GitHub Release 或上传 IPK，既有历史脚本及 Git 历史未改写。
