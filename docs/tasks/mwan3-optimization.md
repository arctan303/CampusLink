# MWAN-04：四路吞吐优化调查

目标：根据 MWAN-03 的四路约 383 Mbps、WLAN 260–365 Mbps 及连接超时反馈，给出有证据、可回退的优化方案。

依据：用户在测速过程中追加“根据反馈需要你看看有没有优化方案”。

范围：读取无线、CPU、收发丢包、mwan3 策略与当前版本上游资料；做有限时长局域网对照以区分无线/测试端与外网路径。必要的低风险可逆设置先记录原值。校园网插件另处维护，不改其代码、设置或账号；代理/VNT 留待后续，不刷机。

预期行为：用实际观察支持优化优先级，不将协商速率当有效吞吐，不将相关性当根因。已有四路等权与认证出口保留。

依赖：MWAN-02 四路策略与 MWAN-03 测量证据；目前仅 WLAN 连到此路由器，本机有线属于另一网段。用户回复“暂时不接，先继续现有诊断”，因此保留有线对照缺口，继续无线和路由器侧检查。

规模与风险：短任务，R1。局域网服务只绑定路由器 LAN 地址、静态测试文件置于 /tmp，进程有时限并由本任务清理；不改管理服务、路由、防火墙和无线配置。

验证：局域网 HTTP 下载有效载荷、错误、CPU/无线和接口计数前后差值；实际版本的策略与源码对应。提出方案时分别标明已验证、候选和仍需对照的部分。

状态：调查及优化建议完成；未修改长期网络配置或插件。局域网测试、并发对照及后检查完成；DNS 的短时故障自行恢复，未确定根因、未声明修复。R1 自查完成，无独立审查或发布。

## 已验证事实

- 已有 packet_steering=1，eth0/eth1 的 RPS mask=2；四路均衡是 `numgen inc mod 4`，sticky=0，真实 8 条测试连接各 WAN 恰为 2 条，不存在权重配错证据。连接跟踪 152/31232，软网络 backlog 丢包计数为 0，没有表满证据。
- 无线为 5 GHz、信道 36、80 MHz、双空间流 HE，RSSI 约 -59 至 -63 dBm；协商速率随无线条件在约 865–1201 Mbps 变化。历史信道忙碌率约 5.8%，不能据此证明当前存在或不存在干扰。
- 使用现有 uhttpd 的独立临时实例，只绑定 `192.168.0.1:18080`、`-c /dev/null`、禁用目录列表及外部符号链接，提供 /tmp 内 16 MiB 静态文件。8 条连接、12 秒、扣除 2 秒起始阶段后，实际 HTTP body 平均 **468.41 Mbps**，705.69 MB，48 次请求全部 HTTP 200、无异常。实例退出、监听已消失、测试文件已删除，没有修改原管理服务。
- 该局域网结果证明此无线连接能传输超过 400 Mbps；它不经过 WAN/NAT，不能单独证明外网转发没有任何瓶颈。
- 同一外网节点、相同小文件与连接复用方式，8 条连接、20 秒得到 **220.91 Mbps**；各 WAN 2 条连接，出现 1 次下载超时（wan2）。此前 32 条连接测得 **365.39 Mbps**，出现 2 次超时。并发变化、路径延迟及外部节点波动均可能影响结果，不能把一次对照当长期固定收益。
- 空闲/该轮负载下，四路到 223.5.5.5 的平均 RTT 分别约 14.41→14.74、12.27→12.97、36.33→37.83、36.40→37.89 ms；空闲各 6 包、负载各 24 包均 0% 丢包，没有严重队列膨胀的本轮证据。此 ICMP 节点不是下载服务器，且 8 流测试未跑满四路，不以此排除满负载拥塞。
- 8 流轮次网口 rx_dropped 小幅增长（eth0 +23，四个 vwan 各 +19），硬件 rx_errors=0；各 vwan 同步增长可能包含共享广播/控制流量，不直接解释为四路下载分别丢了 19 个包。无线计数在局域网测试也增长而 HTTP 无超时，未把这些累计计数等同于 TCP 丢包率。

## 优化优先级

1. **先完善故障分类与健康联动。** ICMP 可达不能证明校园认证和 HTTP 可用。应保留绑定设备及源 IP 的认证请求，使用多个外网探测来源、明确 HTTP 状态及连续失败阈值；DNS 失败、检查中、单站点失败和“门户已登录但探测不明”不应直接等同于认证失效，也不应据此同时剔除四路。CampusLink 公共状态与 mwan3 的联动属于后续实现，尚未部署。
2. **下载使用足够的连接数和连接复用。** 现有 1:1:1:1 与非 sticky 的总吞吐策略保持；本轮 32 流比 8 流更能利用四路。浏览器单 TCP 连接仍只能用一路，多线程/分段下载或多客户端并发才有机会接近 400 Mbps。遇到要求固定公网 IP 的应用时单独做有限范围规则，不把所有 HTTPS 全局 sticky 到一个 WAN。
3. **用另一节点继续区分路径与测速服务影响。** 此时 WAN1/2 到同一 ICMP 目标比 WAN3/4 延迟低，单个测速节点不足以决定应降低后两路权重。四路单测都约 100 Mbps，当前没有容量不同的证据，因此保留等权。有线对照按用户决定暂不做。
4. **软件流量卸载与 all-CPU packet steering 为候选 A/B 项，不作为本轮已优化。** 当前 CPU 没有持续跑满，packet steering 已开启；all-CPU 模式不保证比当前模式更快。实际 mwan3-nft init 脚本存在软件卸载启动时清理旧连接的逻辑，上游也描述了该路径，但这不构成本机 macvlan/NAT/故障切换兼容证明。若后续测试软件卸载，须设置自动回退，核验四路 NAT 出口、认证绑定、故障与恢复、CPU 和实际吞吐，避免只看一个数字；硬件卸载需要额外验证，当前仍为 0。

上游依据：[实际 nft 版本机制](https://github.com/dl12345/mwan3/blob/openwrt-25.12/README.md)、[内核 flowtable](https://docs.kernel.org/6.12/networking/nf_flowtable.html)、[packet-steering 实现](https://git.openwrt.org/openwrt/openwrt/tree/?path=package%2Fnetwork%2Fconfig%2Fnetifd%2Ffiles%2Fusr%2Flibexec%2Fnetwork%2Fpacket-steering.uc)。不从旧 iptables 版或别的芯片经验直接推断此机型兼容性。

## 解析失败的专项观察

18:46 左右，四路插件均为 backoff / authenticated_no_connectivity；逐路 curl 的同一域名均在约 3 秒返回 name lookup timed out，mwan3 的 ICMP 仍在线。这证明“插件未确认联网”与“mwan3 online”可同时出现，但不能断言认证会话已丢失。

后续 nslookup 通过 127.0.0.1 解析成功；默认 DNS 上游来自原 WAN 的 202.202.160.2、61.128.128.68、218.201.4.3。IPv4 curl、固定真实 IP 的 curl 成功，随后不强制 IPv4的同样绑定也成功；插件自行回到 already_online。没有只因增加 `-4` 一次成功就认定 IPv6 为根因，更没有修改 DNS 路由或重启 DNS 来掩盖现象。

curl 的 `--interface` 控制 HTTP 出口，不保证 DNS 查询跟随；本机 libcurl 没有 c-ares，不能直接使用要求该后端的 `--dns-interface`。依据见 [curl 官方说明](https://curl.se/docs/manpage.html#--dns-interface)。因此后续完整健康验证还应包含 DNS 的可用性及故障分类。

测速脚本直接使用真实节点 IP，**此次 DNS 故障不能直接解释之前的下载连接超时或吞吐差距**。两类问题分别保留证据，根因均未完全定位。

18:53:17 最后回读：CampusLink 0.3.0 四路 online / already_online；同一 `ifhost!设备!源IP` 绑定加 IPv4 域名访问四路均 HTTP 204（约 70–105 ms）。network/firewall/mwan3 的 UCI 缓冲为空，配置哈希保持本轮读取值，测试服务和测速进程均已退出。

## 证据与恢复

- 本机私有目录：`C:\git\CampusLink\.local\mwan3-speed`；LAN 对照 `wlan-local-throughput.json`，8 流对照 `wlan-throughput-8-keepalive.json`；路由器记录含 wifi-local/load 前后、ping-idle/load、lan-8、optimization-post-check。
- 最终核验档案：`campuslink-speed-results-verified-20261008.tar.gz`，本机/路由器 SHA256 为 `ad10090366357cdf4af70e8dffd0876559c355f9cb3b1d5df0f1b25d0c67de8f`；原 final 档案记录短时 backoff 现场，保留其历史事实。
- 没有部署配置优化，无需回退生产配置。通用 WLAN 测量脚本为 [measure-wlan-throughput.py](../../scripts/measure-wlan-throughput.py)，有并发/时长上限；临时静态测试服务已经清理，下一次需要重新启动。
