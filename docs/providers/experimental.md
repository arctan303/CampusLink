# 实验性校园网协议适配

2026-10-15，[CL-PROVIDER-02](../tasks/provider-variants-rsa.md)承接 [CL-PROVIDER-01](../tasks/additional-providers.md)。代码基于公开学校工具的协议分析独立实现；离线行为验证通过不代表已在对应学校登录。v0.4.2 为实验性试用构建；稳定 v0.4.1 与原路由器只验证 Dr.COM HTTP。

扩大搜索的 [32 个仓库调研](research-20261015.md)另列大学掌、天翼、H3C 和原生客户端候选；仅深澜变体和锐捷 RSA 已承接，其余仍为建议。

## 参考项目与原理

| 资料（核对的提交） | 用途与观察 | 许可证 / 使用边界 |
| --- | --- | --- |
| [BITNP/bitsrun](https://github.com/BITNP/bitsrun/tree/8567edc17a1570be7804b1f87c1a78514f20e210)，`src/bitsrun/user.py`、`utils.py` | 北京理工大学：先查 `rad_user_info`，再 `get_challenge`、SRBX1 编码和 `srun_portal`；该版本 HMAC 消息为空 | WTFPL；参考协议公式，未捆绑其 Python 客户端或依赖 |
| [Miyamiz39/pumc-net-auth](https://github.com/Miyamiz39/pumc-net-auth/tree/99fd8a42418f7f9b5573996a5c95b863a616f668)，`srun.go` | 协和校园网参考：HMAC-MD5 以挑战为 key、密码为消息；与北理实现存在明确变体 | MIT；用于交叉核对请求字段、算法与变体 |
| [Aurorp1g/Auto_Connect](https://github.com/Aurorp1g/Auto_Connect/tree/776242341b9304b56165a109cdb7402795ef2e83)，`post/body.js` | 锐捷 ePortal 表单及浏览器零填充 RSA：反转 `password>mac`，按小端 16 位字打包、模幂、每字 4 位 hex | MIT；独立实现 Montgomery 算法，参考纯算术仅用于交叉验证，不捆绑客户端或日志策略 |
| [jerry-yuan/RPi-BigQtFace](https://github.com/jerry-yuan/RPi-BigQtFace/blob/00b1502169776e72de807897cee32dab351d352c/NetworkMonitor.cpp) | 同源 POST pageInfo 与 `validCodeUrl` 验证码字段 | 协议事实参考，未复制 Qt 实现；不发送或识别验证码 |
| [FFspiky/campus-network-auto-login](https://github.com/FFspiky/campus-network-auto-login/tree/458b98c15023b1d4a46b5c1bfd21367e66a77a00) | 中国石油大学工具：pageInfo 公钥字段、RSA、双重表单编码 | 未发现明确许可证，不复制实现；仅核对请求格式 |
| [Georgeupup/szu-network-guardian](https://github.com/Georgeupup/szu-network-guardian/tree/44554ac5396abd977b3563f64ae3dc633d5cd988) 与 [BUAASubnet/srun-login-py](https://github.com/BUAASubnet/srun-login-py/tree/8bfd3f23e899fa874d286f6509df659eb99f7480) | 深澜 error/res、无状态挑战及 AC ID 跳转发现 | 仅参考协议差异；不采用关闭 TLS 校验、默认猜 1 或以页面 IP 替换 WAN 的策略 |
| [Turris-Babel/school_ruijie](https://github.com/Turris-Babel/school_ruijie/tree/7cff056a3185545c2bca84b11f330a84ae4bb4fa) | 集美大学与通用示例，交叉确认探测重定向→表单的流程，以及多次失败后验证码限制 | GPL-3.0；调研资料，未复制/翻译其代码到 MIT 插件 |

也核对了 [spencerwooo/bitsrun-rs](https://github.com/spencerwooo/bitsrun-rs/tree/9ca281154aab4157db2e588b7c1b0400a0a7d43e)。其 xencode 注释指向另一个 GPL 项目，因此没有以该实现作为代码移植来源。宜宾学院工具 Gloridust/RuijieWIFI-AutoLogin 未找到仓库许可证文件，也未复制其源码。没有执行下载项目的安装脚本、登录循环或携带真实账号的示例。

上述内容证明存在可分析的参考实现；各学校今天的门户版本与兼容性仍未知，不把上游的兼容承诺作为 CampusLink 实测证据。

错误分类另交叉核对 [vouv/srun 的错误码表](https://github.com/vouv/srun/blob/57727d48a60ff5b69446fd0d0c7c5fd0c559e5eb/core/errors.go)和 [GuoYingLong/eportal-login 的密码不匹配响应](https://github.com/GuoYingLong/eportal-login/blob/c8f1ad27d43eb940531f21808713049b5c9bfe75/login-eportal.py)。仅使用已知响应事实，不捆绑客户端源码；深澜 `login_error` 中的 E2531/E2553 归为凭据拒绝，E2532/E2533 归为限流，未知码保留未知状态，不通过宽泛的错误文案推断永久拒绝。

## 深澜 SRBX1（实验性）

在插件设置选择“深澜 SRBX1（实验性）”，填写认证服务器的**来源 URL**（例如 `http://portal.example:8080`，不带路径/查询）。AC ID 可手填或留空：留空仅从服务器根路径返回的唯一同源 Location / 明确 meta refresh，解析 `srun_portal_pc`、`srun_portal_phone` 或 `index_1.html` 的唯一 `ac_id`，范围 1–65535；不跟随页面、不猜默认值，无法获取时提示手填。账号保存完整用户名，包括学校要求的域后缀。高级 HMAC 变体默认“使用密码”；北理参考版本使用“空消息”，应按自己学校的工具选择，不自动尝试两次。

适配请求顺序：外网 204 探测 → `/cgi-bin/rad_user_info` 的明确 `not_online_error` → 必要时发现 AC ID → `/cgi-bin/get_challenge` → `/cgi-bin/srun_portal` → 重新探测 204。error/res 单字段或一致值按已知状态处理，冲突/未知不自动登录。挑战仅接受固定回调 `campuslink` 或 JSON；无状态挑战须明确返回当前 WAN IP，合法 token 且无负面 ecode；新挑战的地址不一致时不提交认证。SRBX1 为自定义 Base64 的 xencode JSON、HMAC-MD5 和 SHA-1 校验和；JSON 包含当前 WAN IP，不从别的网口发现地址。

只覆盖 SRBX1 的这两种 HMAC 分支，`n=200`、`type=1`；不包含其它深澜旧版/第三方单点登录或强制验证码。MD5/SHA-1 是校园门户既有协议的一部分，不用于插件密码存储。退出与专用心跳能力关闭。

## 锐捷 ePortal（实验性）

填写认证服务器的来源 URL（含所需端口），按门户选项填写服务/运营商，账号使用学校要求的完整值。“密码模式”默认非 RSA，保持旧配置行为；明确选择 RSA 时才获取公钥，不自动降级或尝试其它算法。

探测必须得到配置来源的 `/eportal/index.jsp?...wlanuserip=...` HTTP 重定向，或整页仅含 `top.self/window/self/top.location.href` 的字面 `<script>` 跳转。接受同源绝对地址或以 `/` 开始的相对地址；不执行脚本，不跟随跳转。登录前再次获取当前出口的新 queryString，向固定同源 `/eportal/InterFace.do?method=login` POST。百分号解码字段名/值进行校验，重复 `wlanuserip`（含大小写/编码别名）或可辨认的明文地址与本路 IP 不一致时拒绝；发送时保留原 queryString 内容。未知页面、任意 JS、跨源跳转不触发认证。

RSA 使用固定同源 POST `InterFace.do?method=pageInfo`，请求只含当前 queryString；校验 `publicKeyExponent` / `publicKeyModulus`。支持 1024/2048 位奇数模数、指数 3/65537，ASCII 可打印密码和唯一非空 MAC（从新 queryString 解码）。`password>mac` 必须在单块范围内：1024 位总长 ≤126 字节，2048 位 ≤254 字节。缺 MAC、公钥不合法、字符/长度不支持或 pageInfo 明确提供 `validCodeUrl` 时停止，不发送登录密码；服务器在登录响应中要求验证码时暂停。仅支持已有网页零填充协议，不支持 PKCS#1/OAEP 或多块格式。密文仍视为秘密材料。

高级“表单编码”默认按模式：非 RSA 一次、RSA 双重；可按该校工具明确选择一次或双重。双重表示先百分号编码各字段，再交给 curl 编码一次；不改写 queryString 的内部含义。`result=success` 只代表请求接受，核心仍做联网复查；`wait` 不算在线。配置 HTTP 时，非 RSA 仍传明文表单；RSA 公钥也经该 HTTP 来源获取，不能替代 HTTPS 的服务器认证。Cookie/CAS、运营商第二密码、验证码识别及其它脚本流程未适配。

## 试用与反馈

新线路默认禁用且自动登录关闭。先配置单路 WAN，启用线路并手动登录；确认该校可用后再打开自动登录或测试多 WAN。线上原 Dr.COM 配置不会自动切换。

反馈建议包含：学校/登录系统名称、参考工具链接及提交、服务器类型/端口、插件与固件版本、失败的原因码、手动或自动、单/多 WAN，以及已脱敏的响应结构。不要发密码、Cookie、挑战、加密密码、SRBX1 info、完整 queryString、完整配置或浏览器原始 HAR；这些仍可能含凭据/会话材料。插件不会转发新模块的原始服务器消息。

## 离线验证与复现

用独立 Python 标准库生成 MD5、SHA-1、HMAC、SRBX1 及 RSA `pow` 向量；RSA 另与固定 MIT 参考的纯算术在隔离 Node VM 交叉验证。覆盖哈希边界、Unicode/特殊字符、两种 HMAC、两种 RSA 位数/指数、单块边界、公钥/状态/参数拒绝。ucode VM 执行实际模块函数体，排队传输检查目标、方法、字段和状态；真实 worker 验证检查→认证→联网复查。真实 curl 向回环 HTTP 服务发送生成配置，验证 GET/POST 及双重编码。最终 IPK 解包后复跑同一 worker/算法/传输冒烟。

本次测试 runtime 是 ucode 官方 [WebAssembly REPL](https://try.ucode-lang.org/) 提供的解释器，版本 `2f62a446 2026-10-07`；文件仅在忽略目录 `.local/provider-research/`。下载 `https://try.ucode-lang.org/ucode.js` 与同目录 `ucode.wasm` 后先核对 SHA256：

```text
ucode.js   ffcb7199908a5edfafd71fed3674d49bcfe10ddb0d1998bdba1127559d5e941c
ucode.wasm f0474e5fd662eaabc53c425ee9cad1f596b5fc07d3a51859edbbdc7470305e86
```

源站可能更新，不匹配时记录新版本并重新核对，不静默接受。运行：

```sh
python tests/generate_provider_vectors.py
node tests/run_provider_tests.cjs .local/provider-research/ucode.js
node tests/rsa_reference.cjs .local/provider-research/auto-body.js
node tests/settings_config.cjs
node tests/ui_view.cjs
```

参考 JS 下载上述固定版本的 `post/body.js`（SHA256 `ae0a4592916e33daf626cfec5c65ccae10dddebd46db3190773973d02921557f`）；测试只提取 RSA 闭包，不执行客户端或安装代码。

运行器将 Linux 原生 `fs` 静态导入改为 WASM 的 `require('fs')`，替换 transport 为排队夹具；worker 仅把命令行上下文路径改成测试路径。生产算法与 worker 函数体不改写。真实传输的 request_options 保留并用于 curl 测试；Windows 回环测试移除了 Linux `ifhost` 绑定行，因此**未验证 Linux 原生模块加载、进程取消、目标固件、多 WAN 出口、原生 RSA 性能或真实学校认证**。这些缺口不能由语法通过或向量数量替代。结果及独立审查见[任务](../tasks/provider-variants-rsa.md)。
