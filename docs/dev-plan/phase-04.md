# NET-08：普通上网优化

目标与依据：D-20261009-14 / REQ-006 / AC-018–020；按 DNS 缓存 → 流量统计 → 轻量去广告逐项验收，避免当前经路由器上网的会话失联。

depends_on：NET-07 的 LAN 管理绑定、代理关闭和运行基线；MWAN-05 的四路认证健康联动。开工已复核四路 online、tracking disabled、各 25%，Nikki 主开关 0，启动 ID 与 NET-07 相同。

supersedes：NET-07 普通上网建议“尚未实施”的当前范围；其历史管理收紧证据继续有效。

路线/规模/风险：产品配置变更，单一顺序验收 Phase，R1。DNS 重载或域名误拦截可能临时影响上网；只修改 DHCP DNS 选项及两个新增插件，独立定时回退、校园允许列表和有限检查可覆盖，保留网络/无线/防火墙/管理/账号配置。

范围与产物：DNS 缓存 1000；nlbwmon LAN 统计与 LuCI；adblock-fast 单列表、TLS 验证、下载硬上限、无强制 DNS 重定向；本地私有备份和设备回退脚本。包依赖先核验，不批量升级、不强制不兼容依赖。

非目标：不重启、不改 5 GHz/四路策略/校园账号/管理密码，不启用代理/VNT，不变更宿主机代理，不删除旧校园 cron；缺少满载延迟证据时不安装/启用 SQM。

验收：AC-018 的运行缓存和命中；AC-019 的真实 LAN 统计与页面；AC-020 的阻断/允许 DNS、四路指定出口、原管理绑定和保护哈希。固定次数请求、单请求超时、包安装与下载有界；不做吞吐压力或循环认证。

状态：2026-10-09 已在设备部署；针对性验证通过并保留下面的客户端 DNS 缺口。R1 当前会话自查，无独立审查/推送。证据放 `.local/internet-optimization/`，不提交凭据或完整私有配置。

## 实施结果

- dnsmasq-full 2.93-r1 的持久缓存从 0 改为 1000；运行配置 `cache-size=1000`，语法检查通过。DHCP 上游、DNS 重定向及其他选项保留。首次 SIGUSR1 显示本地回答 13，完成快照转发 127 / 本地回答 425；后续两次连续百度 A 查询均成功，窗口计数从转发 416 / 本地 559 变为转发 417 / 本地 560，符合一次上游请求及重复查询由缓存回答的行为。统计包含客户端和路由器查询，不将累计本地回答数量全部等同于本次测试或纯缓存命中，也未测得网页速度增幅。
- 安装 nlbwmon 2025.06.02~29236be6-r1、luci-app-nlbwmon 和 luci-lib-chartjs；仅 `192.168.0.0/24` 纳入统计，排除校园 WAN 的私网地址。数据库 `/etc/nlbwmon`，刷新 30 秒、持久化 24 小时、保留 3 个周期、压缩启用；一次手动 commit 成功并产生 393 字节数据库。页面显示 6 个活跃统计主机、真实字节/连接数据；月份标签不是此前整月的完整历史，安装时现存连接可能包含此前累计字节。
- nlbwmon 默认接收缓冲 524288 被内核 rmem_max=212992 截小；确认 `/etc/sysctl.d/90-nlbwmon.conf` 不存在后只新增 `net.core.rmem_max=524288`，保留原值供回退。插件进程在新上限下运行，没有新进程的截小告警。供应商 procd.sh 的 shift 提示不影响已验证的进程/ubus/LuCI；没有改公共 procd 脚本。
- 安装 adblock-fast / luci-app-adblock-fast 1.2.4-r4；只启用原生 AdAway Hosts 列表，生成 4289 个阻断域名。`dnsmasq.servers`，force_dns=0，TLS 校验启用，连接 5 秒/下载最长 30 秒/失败重试 0/最大文件 1 MB/并行数量 1；自动配置下载和文件尺寸写回关闭。缓存 `/etc/adblock-fast.dnsmasq.servers.gz` 29358 字节，恢复开机无需首先下载，但整机重启未测试。没有增加定期下载 cron。
- 实际公共配置使用提供商/学校默认认证 IP 与华为 204 探测；允许 `connectivitycheck.platform.hicloud.com`、`connectivitycheck.gstatic.com`、`www.baidu.com` 和原默认 CDN。DNS 查询记录保持关闭；没有记录用户浏览域名或启用 DoH/IP 阻断。
- LuCI 安装脚本附带的可选远程 API 登录条目已移除，新 adblock-fast-api 无 shell 的账户已锁定；root 原管理和 LuCI 插件权限仍正常。令牌保留在私有设备配置，不公开；未来插件更新可能重新创建该可选登录，届时核对。

## 行为验证与限制

- 路由器 DNS 对 `analytics.163.com` 返回 NXDOMAIN；校园 DNS 上游对同名仍返回地址。百度和实际华为探测域名正常解析，百度 HTTPS 返回 200。四次指定 vwan1–4 的实际探测均返回 204，CampusLink 四路 online、mwan3 tracking disabled、balanced 各 25%。未重新认证或故意踢出校园会话。
- 网络、无线、firewall、mwan3、Nikki、uhttpd、Dropbear 和 CampusLink 私有配置哈希全部不变，启动 ID 仍为 `d8fef3f1-467a-4363-b0ae-fb95ecc8e899`。Nikki 主开关 0、无 Mihomo 或代理 nft 表；只存在 fw4/mwan3。网页监听 192.168.0.1:80/443，SSH 仍直接绑定 br-lan；真实 LAN 22/80/443 均成功，使用用户现有密码重新登录 LuCI 后两个服务菜单及实际页面通过。
- 宿主当前路由实际经以太网 192.168.0.115 / ifIndex 22；先前 WLAN 绑定检查当时接口断开，结果不作为设备失败。正确接口的 UDP DNS 三次各 3 秒超时，TCP DNS 三次被 Windows 10013 拒绝，且宿主 Mihomo 接口处于 Up；未证实具体拦截组件，也未改变宿主代理。其他 LAN 到路由器 DNS 的有限 conntrack 样本有实际回包；本机所有端口 53/加密 DNS/宿主代理路径的去广告效果不能追认为通过。域名过滤仅覆盖使用路由器解析的查询，未来 Nikki 接管 DNS 后单独回归。
- 最新空闲负载约 0.10/0.10/0.17，overlay 剩余约 140.0 MiB；没有开展吞吐压力、SQM 限速、循环 ping 或循环登录测试。页面提示缺少可选 GNU 预处理工具，不影响这份小列表运行；没有为消除提示强制覆盖 BusyBox 工具。
- 两次 DNS 变更使用独立 600 秒守护，检查存活后确认并取消；最终无回退守护残留，确认后的正常 rollback 是无操作。只检查了回退脚本语法及确认条件，未故意断网验证定时恢复。自动审批曾阻止未先确认的 sysctl 文件覆盖命令；实际写入前读取确认文件不存在，此拒绝已用安全方案解决。
- adblock 原生只在 UCI 运行缓冲中设置 `dhcp.cfg01411c.serversfile`，持久 dhcp 文件仅改变缓存。该运行条目为插件正常管理，不提交指向 /var/run 的临时文件路径；没有其他待提交 UCI。

## 恢复与证据

设备目录 `/root/campuslink-internet-optimization-20261009/`，目录仅 root 可访问；手动 `sh /root/campuslink-internet-optimization-20261009/rollback.sh --force` 将停用去广告和流量统计、恢复原 DNS/缓冲上限，保留插件包与统计文件，不触碰网络、无线、管理绑定、校园账号或四路策略。日后配置改变时先检查这份基线是否仍适用。

本机私有档案 `campuslink-internet-optimization-evidence-20261009.tar.gz`，SHA256 `2fd5fcdfffa34ada78005a74003acaa259f6f123286488d57c888761533ee735`，与设备哈希匹配；保存前后配置、恢复入口、保护哈希、运行 DNS/四路/管理证据、缓存查询窗口、普通 HTTPS、包差异与统计数据。只新增 5 个包，没有移除或升级原有包。客户端检查另见 `lan-check.json`、`lan-tcp-check.json`，页面证据 `nlbwmon.jpg` / `adblock-fast.jpg`，均留在忽略目录。

配置依据：[nlbwmon 官方配置](https://github.com/openwrt/packages/blob/master/net/nlbwmon/files/nlbwmon.config)、[adblock-fast 维护者文档](https://docs.mossdef.org/adblock-fast/)、[AdAway 列表](https://adaway.org/hosts.txt)；具体版本和效果以本设备记录为准。
