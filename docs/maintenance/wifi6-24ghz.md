# NET-06：2.4 GHz 启用 Wi-Fi 6

目标：按用户“2.4 改成 wifi6”将试用路由器 radio0 从 HT20 改为 HE20，保持 20 MHz、信道、SSID、加密及原密码。

范围：仅无线 radio0.htmode，启用并核对 AP 运行配置；5 GHz、WAN/mwan3、CampusLink 核心与账号均保留。不刷机，不改宿主网络设置。

预期：2.4 GHz AP 启用 802.11ax，5 GHz 管理连接仍正常。既有客户端能否协商 ax 取决于其能力；启用 AX 不代表已测所有终端。

依赖：当前 radio0 为 2g/HT20，iw phy0 具有 HE AP 能力，iwinfo 明确支持 HT20/HT40/HE20/HE40；radio1 为 HE80，宿主正在使用其 802.11ax 连接。

规模/风险：维护短任务 R1。radio0 应用时可能短暂断开其客户端；root 私有配置备份、只恢复此选项的脚本和独立定时回退界定影响。

状态：2026-10-08 23:06–23:08 已实施并完成 R1 针对性验证与自查；radio0 已为 HE20，维护项待批次复查，无独立审查。没有修改插件代码或发布软件包。

附带诊断：用户标注“门户显示已登录，但联网探测未成功；不重复认证”。provider 只有外网返回 204 才确认 online；门户显示已登录而探测未确认时返回 authenticated_no_connectivity 并退避。2026-10-08 23:05 后台四路已自行恢复 online/already_online，用户也确认页面恢复；没有证据确定该次 DNS、外部服务或路径中的具体根因，没有修改插件或宣称修复该根因。

## 验证与证据

- `uci get wireless.radio0.htmode` 和 iwinfo 实际模式均为 HE20；运行 hostapd-phy0.conf 含 ieee80211ax=1，netifd radio0 up=true/pending=false，信道 1/20 MHz 保留。
- 将当前 UCI 导出中的唯一 HE20 值规范回原 HT20 后，与私有备份导出逐字一致；证明 SSID、密码、加密、信道与其他无线配置未变。radio1 仍 HE80，宿主仍连 5 GHz/802.11ax/1201 Mbps，SSH 和 LuCI 登录入口正常。
- 四路按当前设备/IP 绑定域名 HTTP 探测均 204；CampusLink 和联动四路都 online，配置 generation=15。network/firewall/CampusLink/mwan3 哈希与本次修改前一致，UCI 缓冲为空。
- 宿主四个 HTTP 请求均 204，额外 HTTPS 200 且证书验证通过；未改宿主路由/DNS。报告 `.local/wifi6-24ghz-client.json` 由 Git 忽略。
- 已启动 300 秒独立回退保护；验证通过后写 confirmed，核对进程归属并停止定时器，confirmed 后普通回退为无操作。原始无线备份仅保存在路由器 root 私有目录，不公开其中密码。

验证边界：未切换宿主到 2.4 GHz 做客户端 ax 协商/吞吐对照，未测所有旧终端，未重新启动整机或强制执行完整回退。AP 已实际开启 AX，不能把这些未测项写成通过。

## 恢复入口

路由器私有目录 `/root/campuslink-wifi6-20261008` 保存 wireless、before.sha256、verification.json、bound-http.txt、final-check.txt、rollback.sh 与 confirmed。恢复旧 2.4 模式：`sh /root/campuslink-wifi6-20261008/rollback.sh --force`，仅将 radio0.htmode 恢复 HT20 并执行原生 wifi reconf radio0，不覆盖其他无线/网络或账号设置。

最终无线配置 SHA256 为 `fd46b31f351017a235c6b9c60ca9618dc36b786035f245e95e628b4f8b185fc3`。此项已加入 [待复查维护队列](batch.md)；不把页面自行恢复解释成已定位/修复外网探测根因。
