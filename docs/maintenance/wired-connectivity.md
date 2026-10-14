# NET-09 Windows 有线联网提示诊断

日期：2026-10-12。路线：维护诊断，短任务，R1。状态：诊断完成；没有实施网络或代理配置变更，没有发布或独立审查。

## 目标与边界

用户反馈 Windows 以太网显示“无法访问 Internet”。区分物理链路/路由器转发故障与客户端 DNS、代理及联网检测异常。继续保留四 WAN、CampusLink 联动、LAN 管理及关闭的路由器 Nikki；不重启、不改无线或宿主代理/路由，不运行循环或压力测试。

预期行为：有线客户端经 192.168.0.1 正常解析域名并访问外网。Windows 联网提示是诊断信号，不能单独作为全部网络流量断开的证据。依赖：当前 Windows 网络状态、路由器 SSH、有限次数的联网请求。

## 验证与证据

- 以太网 ifIndex 22，192.168.0.115/24，千兆；Wi-Fi ifIndex 8，192.168.0.139；本机 Mihomo ifIndex 2，198.18.0.1/30。以太网手动 DNS 为 1.1.1.1/8.8.8.8，Wi-Fi DNS 为 192.168.0.1，TUN DNS 为 198.18.0.2。
- 13 个固定请求，最多并发 2，每个套接字超时 2.5 秒。物理接口同时绑定源地址和 Windows IP_UNICAST_IF；HTTPS 使用路由器刚解析的真实 IP，保留服务器主机名与证书校验，因此该项证明转发/TLS，不证明 Windows 域名解析。
- 强制以太网访问 www.baidu.com 的 HTTPS 返回 200（约 0.20 秒）；微软 connecttest.txt 返回 200 且正文符合 Microsoft Connect Test（约 0.29 秒）。Wi-Fi 对照同样成功。
- 以太网和 Wi-Fi 分别向 192.168.0.1、1.1.1.1、8.8.8.8 发 UDP DNS 均超时；分别向路由器发 TCP DNS 均立即收到 WinError 10013（本机套接字访问被拒绝）。默认路径向 TUN DNS 198.18.0.2 查询成功，约 0.034 秒。
- 本机 mihomo PID 18244 的父进程是 Sparkle.exe PID 14024。Sparkle 的 work/config.yaml 在本日 12:59:46 更新，含 tun.enable=true、strict-route=true、dns-hijack=any:53；当天核心日志在 12:59:51 确认 mihomo TUN、auto route=true、Mixed 栈已启动。旧 Clash Verge 配置显示 TUN 关闭，与当前进程不符，不能用它判断实时状态。
- 路由器 CampusLink 四路 online，mwan3 四路 online、各 25%、tracking disabled；绑定 vwan1–4 的校园探测均为 204。路由器能解析百度与微软探测域名，直接访问微软探测页为 200 且正文正确。adblock-fast 正常，Nikki enabled=0 且没有核心。
- 本次只读到的路由器 boot ID 为 b20c943d-c190-4411-961c-dcb0827fbba8；不同于 10 月 9 日的历史证据。本次没有重启。
- 用户补充：之前小米路由器有线可用，电脑配置没有改；尚未确认本次是网页实际失败还是仅 Windows 提示异常，当前 Wi-Fi 仍连接。该对照需要保留，不能仅凭 TUN 开启认定它造成新回归。
- 随后检查当前 Mihomo 已建立的公网 TCP 连接：11 条均使用有线地址 192.168.0.115，没有使用 Wi-Fi 地址 192.168.0.139 的公网连接。路由器确认 192.168.0.115 的邻居 MAC 与有线卡一致，LAN eth1 carrier=1、speed=1000。Wi-Fi 连接状态本身不能证明当前出网经过 Wi-Fi。
- 追加两次普通系统域名解析：百度与微软探测域名均成功返回 TUN fake-IP。追加两次按域名正常访问（没有固定目的 IP，也没有强制物理接口）：百度 HTTPS 为 200，微软探测页面为 200、22 字节且正文正确。核心日志确认两类域名使用 DIRECT。请求各有 4 秒套接字超时和 7 秒子进程总时限。

测试脚本与原始 JSON 保存在本机忽略目录 .local/wired-diagnosis-20261012/，不提交宿主配置、认证信息、订阅或完整代理日志。

## 结论与限制

有线物理链路、DHCP、网关转发及实际 HTTP/TLS 请求正常；当前核心公网连接也已经使用有线地址。普通系统域名解析和按域名访问成功。截图显示的 Windows 接口联网状态与实际可用性不一致，尚无“当前有线不能传输外网流量”的证据。物理接口端口 53 受限与普通应用解析失败不是同一结论，不能混用。

Sparkle TUN 的严格路由/DNS 防泄漏机制符合物理接口端口 53 受限现象，也是 Windows 联网状态异常的候选解释；它不能单独证明换路由器后出现实际访问回归。没有关闭 TUN 做因果对照，也未读取核心实时控制 API，没有原小米路由器的同条件证据。没有证明所有浏览器/应用都正常，也没有核验用户所说“用不了”是否仅指 Windows 提示。不能把推断写成已确认的唯一原因。

参考：[Mihomo TUN / strict-route](https://wiki.metacubex.one/config/inbound/tun/#strict-route)说明 Windows 严格路由会添加防止多网卡 DNS 泄漏的防火墙规则；[Microsoft NCSI](https://learn.microsoft.com/en-us/windows-server/networking/ncsi/ncsi-overview)说明联网状态依赖探测，探测失败可能出现错误提示。

## 下一步

当前普通域名请求已经正常，不为 Windows 提示先修改正在使用的代理或 DNS。若用户能提供具体访问失败的网站/应用，针对该请求定位；若之后需要有线单独连接的验收，安排不依赖当前远程连接的安全窗口。普通直连可考虑使用自动获取的路由器 DNS；保留 TUN 时则检查其接口探测与 DNS 接管，不能声称只改 DNS 就能消除物理接口限制。不关闭 Windows 防火墙或 NCSI 来掩盖问题。

本次没有已验证的修复，不加入“已修复待复查”队列。恢复时复用上述正向转发证据，只复查发生变化的宿主设置；不重跑四 WAN 压力或断线测试。
