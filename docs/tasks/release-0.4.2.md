# CL-REL-03：GitHub v0.4.2 实验性试用发布

来源：2026-10-15 用户批准完善深澜变体、接入锐捷 RSA，离线测试后“上传提交以及释放到仓库”。实现与 R2 门禁由 [CL-PROVIDER-02](provider-variants-rsa.md) 承接；本任务只记录交付物与远端事实。

目标/范围：正常提交推送 `arctan303/CampusLink` main，tag v0.4.2 指向冻结源码，发布三个 IPK、干净源码 ZIP、SHA256SUMS；公开下载逐项回读。非目标：路由器部署、修改仓库设置、其它需求或旧脚本历史清理。v0.4.2 使用 prerelease，v0.4.1 保持稳定 latest。

依赖：独立 reviewer 通过、离线测试和最终载荷冒烟、敏感信息检查、现有 Python 打包脚本、已登录 gh CLI。远端与本地起点均为 `fbfe83fffac524049a632bad764772d7fa067f55`；v0.4.2 tag 尚未存在。

预期行为：不 force push；源码、版本、附件可追溯且秘密不进入提交/产物；发布后回读 main/tag/Release 及下载资产 SHA256。使用系统凭据存储中的 GitHub 认证，内部传给 gh/git，不打印或写入项目；路由器账号没有参与本轮测试。

实施：发布说明已准备，独立审查已通过。验证：`scripts/check_release.py` 两次构建一致、包结构/权限/JSON/路径检查通过；最终核心 IPK 已解包并通过同一 233 断言/21 worker/curl 回环冒烟。源 UI 三项回归、mwan3 映射及真实本地 shell 夹具通过。本地文档链接有效；新增/变更候选均为 UTF-8 源码、假数据测试或说明，无新增私有配置/日志/截图/二进制。

隐私审计：变更候选、打包白名单和归档内容检查，不含 `.local`、`.git`、dist 或根目录历史登录脚本；已知 token/私钥签名未命中。测试账号、IP、公钥/密文均为合成数据。新增模块返回固定提示，不输出原始服务器响应、密码或密文；请求仅在 root 私有工作区由 curl config 读取。既有公开 Git 历史不属于本次新增审计范围。本地敏感证据及下载记录仅留忽略目录 `.local/release-0.4.2/`。

审查：[CL-PROVIDER-02 fresh reviewer 通过](../reviews/provider-variants-rsa.md)，两项 P2 已修复关闭。发布：已完成，远端提交/tag 及公开附件已回读核验；真实校园可用性仍待试用反馈。

恢复：先核对冻结代码哈希、审查回执及工作区，再执行未完成步骤；不重跑未变化的长测试。不移动已发布标签或替换已核验附件，回执用后续文档提交。问题修复使用新提交/revert；路由器回退旧核心前切回 Dr.COM 保存或恢复备份，使用稳定旧 IPK。若需撤回试用 Release，可退为草稿或删除该 Release；无法收回已下载副本。

边界：目标固件原生加载/性能、进程取消、多 WAN 和真实校园未测，由试用者反馈；不会因离线通过声明全校兼容。维护队列 NET-06 是设备 Wi-Fi 复查，不随插件发布关闭。

## 公开发布回读

源码提交 `f1742db54fe46b60de98de36599ff59dafadd0e8` 正常推送 main，远端回读一致；注释 tag `v0.4.2` 解引用为同一提交。Release 于 `2026-10-15T07:22:01Z` 公开：[v0.4.2](https://github.com/arctan303/CampusLink/releases/tag/v0.4.2)，draft=false、prerelease=true，v0.4.1 仍为 latest。草稿与公开后均实际下载五个附件，SHA256、API digest 与 uploaded 状态全部匹配。

| 资产 | SHA256 |
| --- | --- |
| campuslink_0.4.0-1_all.ipk | efb4ad594dd42dd0466446042b73d2da905a4e322a76c39b16f43ed7b6b6c4cc |
| luci-app-campuslink_0.4.2-1_all.ipk | e31149f9328c7e0dd7aa025afa3854dc790ae9cf825314c856fc0558b2aa8278 |
| campuslink-mwan3_0.2.0-1_all.ipk | e32fb653ca8e01d4d39f2e5242961fd07b39a300cd7754fd0f5e5cf04cde2a00 |
| CampusLink-0.4.2-source.zip | 81e6a62e7f557680ec397d3eac10bf4c2a0a0f989cf15ca074d92c11fbe8b08c |
| SHA256SUMS | c1adcaa1d088e59eba94cc5669c80edc9febcc997942b1d9bcb6775dc76acaf0 |

最终审计：39 个新增/变更暂存 blob 与冻结候选一致，无暂存后漂移；271 个本地文档链接有效。三个包共 35 个载荷文件与经过测试的源码一致（仅 LF 归一）；源码 ZIP 的 138 个文件与已发布 tag 一致，不包含历史脚本、私有目录/配置、原始日志或截图。核心解包运行 233 断言/21 worker/curl 冒烟通过；新协议真实校园、目标固件原生及多 WAN 验证缺口保留。

本回执随后仅以文档提交同步 main，不移动标签或替换附件。发布记录与下载副本保留在忽略目录 `.local/release-0.4.2/`，不提交秘密或私有原始材料。当前没有发布阻塞；本轮没有部署路由器。
