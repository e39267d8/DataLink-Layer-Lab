// 计算机网络实验一 · 数据链路层滑动窗口协议 — 实验报告（Typst）
// 编译：typst compile docs/实验报告.typ
// 预览：typst watch docs/实验报告.typ

#set document(
  title: [数据链路层滑动窗口协议 — 实验报告],
  author: ("张恒基", "尹浩铭", "林旭东"),
)

#set page(
  paper: "a4",
  margin: (x: 2.3cm, y: 2.5cm),
  numbering: "1",
)

#set text(
  size: 11pt,
  lang: "zh",
  region: "cn",
  font: ("Times New Roman", "SimSun", "SimHei"),
)

#set par(justify: true, first-line-indent: 2em, leading: 0.65em)
#set heading(numbering: "1.1")

#show heading: it => {
  it
  par[#text(size: 0pt)[]]
}

// ---------- 封面 ----------
#let 课程名称 = [计算机网络]
#let 实验名称 = [实验一：数据链路层滑动窗口协议的设计与实现]
#let 小组 = [张恒基、尹浩铭、林旭东]
#let 班级 = [（填写班级）]
#let 日期 = [2026 年 5 月]

#align(center)[
  #v(3em)
  #text(size: 22pt, weight: "bold")[#课程名称]
  #v(1.2em)
  #text(size: 18pt, weight: "bold")[#实验名称]
  #v(5em)
  #set par(first-line-indent: 0em)
  #table(
    columns: (1fr, 2.2fr),
    stroke: none,
    inset: 10pt,
    align: (right, left),
    [小组成员], [#小组],
    [班　级], [#班级],
    [日　期], [#日期],
  )
]

#pagebreak()

#outline(title: [目　录], indent: 1.5em)
#pagebreak()

= 11.1 实验内容和实验环境描述

== 实验任务与目标

本实验在教师提供的物理层与网络层仿真库上，自行设计并实现数据链路层协议，使 A、B 两站在#strong[有误码]的全双工信道上仍能向网络层交付无差错分组，并完成指导书要求的#strong[信道利用率]测试与#strong[协议参数]说明。

本组选定协议：#strong[搭载 ACK 的 Go-Back-N（GBN）]。信道与分组参数与库一致（见 `include/protocol.h`、`src/protocol.c`）：

- 带宽 $B = 8000$ bps（全双工）；单向传播时延 $t_p = 270$ ms。
- 网络层分组长度 $N = 256$ 字节（`PKT_LEN`）；默认比特误码率 $P_b = 10^(-5)$（可用命令行 `-b` 调整）。
- 数据帧在内存中为 `struct frame`（`kind`、`seq`、`ack`、`data[256]`），发送时在帧尾再追加 4 字节 CRC-32（与指导书 8.9 一致）。

#strong[复现命令示例]（Linux 下于仓库根目录 `make` 后）：

```text
# 终端 1（A 站）
./datalink -d3 A

# 终端 2（B 站）
./datalink -d3 B
```

无误码洪水、高误码等场景分别叠加 `--flood`、`--utopia`、`-b 1e-4` 等选项；#strong[正式报告中的命令行、运行时长须与你们留存日志一致]。

== 实验环境

- 硬件与系统：（填写主机型号、内存、Windows 版本或 Linux 发行版）。
- 编译器：GCC（`Makefile`）或 Visual Studio（`Lab1-Windows-VS2017` 等工程）。
- 代码版本：（建议填写 `git rev-parse --short HEAD`），便于与附录日志、截图交叉核验。

#strong[与实验库的一致性说明]：下文定时器、`phl_sq_len` 的叙述直接对应本仓库 `src/protocol.c`；滑动窗口状态机与宏常量以你们最终实现为准——#strong[定稿前请对照 `src/datalink.c` 将宏名、数值与行号更新为一致]。

#pagebreak()

= 11.2 软件设计

== （1）数据结构

#align(center)[
  #table(
    columns: (1.1fr, 1fr, 2.5fr),
    inset: 8pt,
    align: (left, left, left),
    stroke: 0.5pt + gray,
    [*字段 / 变量*], [*类型*], [*含义与设计要点*],
    [`kind`], [`unsigned char`], [区分 `FRAME_DATA` / `FRAME_ACK` 等；与组内枚举一致。],
    [`seq`], [`unsigned char`], [发送序号；GBN 发送窗口内序号递增，模 $("MAX_SEQ"+1)$。],
    [`ack`], [`unsigned char`], [累积确认语义须在组内冻结（常见为「期望下一帧序号」）。],
    [`data[PKT_LEN]`], [`unsigned char`], [256 字节载荷；仅数据帧有效。],
    [CRC 区], [4 字节], [CRC-32（IEEE 802.3）校验域：不在 `struct frame` 内重复定义，发送时由 `crc32(buf, FRAME_HDR_LEN + PKT_LEN)` 计算后追加到帧尾 4 字节；接收端以 `recv_frame` 读入长度为 `FRAME_HDR_LEN + PKT_LEN + 4` 的完整帧后，对整帧做 `crc32(...) == 0` 校验。详见 `datalink_recv.c` 中 `validate_and_process_frame`。],
    [`ack_expected`], [序号], [发送窗口下界：最老未确认帧。],
    [`next_frame_to_send`], [序号], [发送窗口上界：下一新帧序号（受窗口宽度约束）。],
    [`frame_expected`], [序号], [接收端按序期望的下一 `seq`。],
    [`out_buf[]`], [帧缓存], [GBN 重传：超时后从 `ack_expected` 起连续重发窗口内帧。],
  ),
  caption: [帧与核心状态变量（与 `include/datalink.h` 及实现保持一致）],
]

#strong[序号空间与窗口]：若序号共 $M = "MAX_SEQ"+1$ 个编号，GBN 一般要求未确认帧个数 $W <= M - 1$（避免收发对窗口解释歧义）。具体 $M$、$W$ 取值在「11.3 参数推导」与代码宏中须一致。

== （2）模块结构

建议用一张「事件 → 处理函数」表或简图说明：`protocol_init` → 主循环 `wait_for_event` → 各 `case` 分支。关键接口来自 `protocol.h`：`get_packet` / `put_packet`、`send_frame` / `recv_frame`、定时器与 `enable_network_layer` / `disable_network_layer`。

#strong[张恒基撰写建议]：在图中标出 `DATA_TIMEOUT` 与 `ACK_TIMEOUT` 的入口，并在正文用「见 `datalink.c` 第 x–y 行」与验收要求对齐（定稿时用真实行号替换占位符 x、y）。

== （3）算法流程与异常路径

#strong[正常路径（示意）]：`NETWORK_LAYER_READY` 时组数据帧、捎带 `ack`、附加 CRC、`send_frame`；对未确认序号 `start_timer(seq, "DATA_TIMEOUT_MS")`。`FRAME_RECEIVED` 且 CRC 正确时，用 `ack` 滑动发送窗口并 `stop_timer`；按序数据 `put_packet`，否则缓存策略按 GBN 丢弃或按序交付。

#strong[异常与边界（评审关注点）]：

+ #emph[CRC 失败]：`recv_frame` 返回后先做 `crc32(...)==0` 判断；失败则#strong[静默丢弃]，不推进 `frame_expected`，不错误调用 `put_packet`（避免网络层坏分组）。可配合 `dbg_event` 记录丢帧。
+ #emph[序号跳变（缺口）]：若收到 `seq != frame_expected`，GBN 丢弃并#strong[重复发送累积 ACK（语义依组内定义）]，促使发送端回退到正确窗口边界。
+ #emph[重复帧]：`seq < frame_expected` 或已交付过的序号：不重复上交网络层，可发重复 ACK 以驱动对端窗口滑动。
+ `DATA_TIMEOUT`：从 `ack_expected` 起重传；#strong[每次有效重传后须重新 `start_timer`]，否则若重传帧再次损坏，可能再无超时事件，形成「静默死锁」（见 11.5 复盘）。

#strong[流量控制：`enable_network_layer` / `disable_network_layer`]

网络层是否产生 `NETWORK_LAYER_READY`，受 `enable` 标志与仿真库内业务模型共同影响；链路层侧应在#strong[发送窗口已满]、#strong[待发队列过长]或#strong[协议状态不允许取新分组]时 `disable_network_layer()`，在窗口有空间且逻辑允许发送新帧时 `enable_network_layer()`。

#strong[与物理层队列 `phl_sq_len()` 的关系]：本仓库 `src/protocol.c` 中，数据帧重传定时器的到期时刻为

$ t_"expire" = t_"now" + "phl_sq_len"() dot 8000 slash "CHAN_BPS" + "ms" $

其中第二项把#strong[当前物理层发送队列中尚未离站的字节数]按信道速率折算为排队发送所需时间（与 `src/protocol.c` 中 `start_timer` 一致：`CHAN_BPS` 为 8000 时，系数为 1，量级上「每字节约 1 ms」发送时间）。这样 `start_timer` 在本地排队较长时会自动推迟超时点，减少#strong[虚假超时重传]。验收报告应写清：你们在 `datalink.c` 中何时调用 `start_timer` / `stop_timer`，以及是否与上述库语义一致。

`PHYSICAL_LAYER_READY` 在库中当 `phl_sq_len() < "PHL_SQ_LEVEL"`（本仓库 `PHL_SQ_LEVEL = 50` 字节）等条件满足时通知链路层可继续向物理层写字节；链路层应利用该事件把积压帧写出，避免队列逼近 `SQ_SIZE` 上限时触发 `ABORT("... overflow")`。

#pagebreak()

= 11.3 实验结果分析

== 有误码下的正确性与长稳

+ 有误码时，网络层不应出现指导书 8.13 中的 #emph[bad packet] 异常退出（若出现，须记录场景与日志并说明修复）。
+ 长稳：建议单场景连续运行 $>= 10$ 分钟（报告可写 20 分钟量级），附录贴 `datalink-A.log` / `datalink-B.log` 首尾时间戳与末次 `put_packet` 统计。

== 协议参数：定量推导（与指导书 11.3(3)(5) 对齐）

设一帧在信道上的比特长度为 $L_"bit"$（含首部与 CRC）。工程上常取：首部 3 字节 + 载荷 256 字节 + CRC 4 字节 $=>$ $L_"byte" = 263$，$L_"bit" = 2104$。

#strong[（1）单帧发送时间]

$ t_"tx" = L_"bit" / B $

代入 $B = 8000$ bps，得 $t_"tx" = 2104/8000 approx 0.263$ s（约 263 ms）。若报告中用「仅载荷 2048 bit」近似，则 $t_"tx"' = 0.256$ s；须在表格脚注中声明采用了哪种口径，#strong[全文口径一致]。

#strong[（2）带宽时延积（单向）]

$ "BDP" = B dot t_p = 8000 times 0.27 = 2160 " bit" $

约合 $2160 / L_"bit" approx 1.03$ 帧（在途「管道」可容纳的未完成传播比特量）。

#strong[（3）窗口下界（填满管道）]

GBN 在持续发送时，为在首个 ACK 返回前不因窗口阻塞而空等，常采用（与指导书及教材等价的）必要条件：

$ W dot t_"tx" >= 2 t_p + t_"tx" quad "即" quad W >= (2 t_p + t_"tx") / t_"tx" $

代入 $t_p = 0.27$ s、$t_"tx" approx 0.263$ s，得 $W >= (0.54 + 0.263)/0.263 approx 3.05$，故教材口径下取 $W = 4$ 更保守。#strong[本组实现]在 `include/datalink.h` 中取 `WINDOW_SIZE = 3`：按字节 BDP 估算，RTT 内比特量 $8000 times 0.54 approx 4320 thin "bit"$，约合 $540$ 字节；若整帧约 $260$ 字节则 $540/260 approx 2.08$，向上取 $3$，与代码一致；误码场景下较小窗口可略减 GBN 回退跨度（与「取 4 提高无误码利用率」的折中须在正文写清）。

#strong[（3.1）定时器宏与报告一致]

数据帧重传超时取 `DATA_TIMEOUT_MS = 600`（略大于 RTT $approx 540 thin "ms"$ 加处理余量；库中 `start_timer` 另含 `phl_sq_len` 排队项，见 `src/protocol.c`）。搭载 ACK 等待时间取 `ACK_TIMEOUT_MS = 200`，避免大 RTT 下过久等待捎带而导致对端不必要的超时重传。

#strong[（4）停等与滑动窗口的理论利用率（简化模型）]

- 停等（$W=1$）：$ eta_1 approx t_"tx" / (t_"tx" + "RTT")$，若取 $"RTT" approx 2 t_p + t_"tx"$（忽略短 ACK），则 $ eta_1 approx t_"tx" / (2 t_p + 2 t_"tx")$。代入 $t_p=0.27$、$t_"tx"=0.263$ 得约 $32%$ 量级（与「管道极空」直觉一致）。
- 窗口为 $W$ 的流水线（无误码、ACK 不阻塞的理想化）：当 $W$ 足够大时，上限趋近于 $t_"tx" / (t_"tx" + "RTT"/W)$ 等形式；一种便于制表的近似为

$ eta_W approx min(1, (W dot t_"tx") / (t_"tx" + "RTT")) $

或按指导书给定公式推导。建议#strong[林旭东]做一张「$W in {1,2,4,8}$ → 理论 $eta$」小表，并与洪水场景实测利用率同图对比（Excel / Python 出图后插入 PDF）。

#strong[（5）有误码时的利用率上界与雪崩]

设比特误码率为 $P_b$，帧长 $L_"bit"$ 较大时，一帧无错概率可近似

$ P_"ok" approx (1-P_b)^(L_"bit") approx e^(-L_"bit" P_b) $

平均每成功一帧所需发送次数约 $1/P_"ok"$。在#strong[独立误码]假设下，有效吞吐量约按 $P_"ok"$ 比例缩放。

当 $P_b$ 升高时，GBN 一旦发生 CRC 失败或丢 ACK，往往要从窗口下界重传多帧，重传帧再次出错的概率叠加，利用率随 $P_b$ 上升呈#strong[陡降]（俗称相对 SR 的「雪崩」效应）。报告须用一两段话把该因果链写清，并与表 3 中场景 4 vs 5 的落差对照。

== 性能测试记录（指导书表 3）

#align(center)[
  #table(
    columns: (0.45fr, 1.2fr, 1.1fr, 1.1fr, 0.65fr, 0.65fr, 1fr),
    inset: 5pt,
    align: center,
    stroke: 0.5pt + gray,
    table.header(
      [*序号*], [*场景*], [*A 命令*], [*B 命令*], [*A 利用率 %*], [*B 利用率 %*], [*运行时长 / 备注*],
    ),
    [1], [无误码], [（填写）], [（填写）], [ ], [ ], [$>= 10$ min],
    [2], [默认业务], [（填写）], [（填写）], [ ], [ ], [ ],
    [3], [双端洪水+无误码], [（填写）], [（填写）], [ ], [ ], [ ],
    [4], [双端洪水（默认误码）], [（填写）], [（填写）], [ ], [ ], [ ],
    [5], [洪水+高误码], [（填写）], [（填写）], [ ], [ ], [ ],
  ),
  caption: [表 3 实测数据（#strong[勿直接照抄他组或旧版参考表]；利用率公式须与 `put_packet` 打印的 bps 与 8000 bps 定义一致）],
]

#strong[根因分析写法]：每个场景写 2–3 句——现象（利用率高低）、机制（窗口 / 停发 / 误码 / GBN 回退）、与理论表或上界的差距来源（ACK 捎带延迟、物理层 1 ms 间隔、`start_timer` 排队项、CPU 调度等）。

== 实测与理论对比（示例表头）

#align(center)[
  #table(
    columns: (1fr, 1fr, 1fr, 1.2fr, 2fr),
    inset: 6pt,
    align: center,
    stroke: 0.5pt + gray,
    table.header(
      [*场景*], [*理论参考 %*], [*实测 %*], [*差距*], [*原因分析要点*],
    ),
    [3 洪水无误码], [（计算）], [（填写）], [ ], [ ],
    [5 洪水 $10^(-4)$], [（计算）], [（填写）], [ ], [GBN 回退、重传放大],
  ),
  caption: [理论值须注明公式与近似条件；若与参考可执行文件对标，另起一行说明版本与参数是否一致],
]

#pagebreak()

= 11.4 研究和探索的问题（至少 2 题深度展开）

== 探索一：CRC-32 漏检概率与工程意义（尹浩铭）

CRC-32（IEEE 802.3 标准，生成多项式 $G(x) = x^32 + x^26 + x^23 + x^22 + x^16 + x^12 + x^11 + x^10 + x^8 + x^7 + x^5 + x^4 + x^2 + x + 1$）在实验中的使用方式为：发送端在帧末尾追加 4 字节 CRC 校验值，接收端对整帧（含 CRC 字段）计算 `crc32(...)`，若结果不为 0 则判定帧已损坏。

#strong[漏检概率的理论估计]。CRC-32 的漏检概率 ≈ $2^(-32) ≈ 2.33 × 10^(-10)$（假设错误模式均匀随机）。设链路利用率为 $eta$，信道速率 $B = 8000$ bps，帧长 $L_"bit" = 2104$，则每秒发送帧数约 $eta B / L_"bit"$。取 $eta = 0.5$ 得：

$ N_"day" ≈ (0.5 × 8000 × 86400) / 2104 ≈ 1.64 × 10^5 "帧/天" $

漏检一帧所需的平均天数约为：

$ T_"漏检" ≈ 1 / (N_"day" × 2^(-32)) ≈ 1 / (1.64 × 10^5 × 2.33 × 10^(-10)) ≈ 2.62 × 10^4 "天" ≈ 72 "年" $

这意味着在 $P_b = 10^(-5)$ 的随机误码模型下，#strong[CRC-32 漏检在统计上可忽略]；实际运行中观察到的 `bad packet` 几乎全部来自 CRC 校验正确而实现的逻辑错误（如缓冲区长度不对、`put_packet` 调用条件错误）。

#strong[与 $P_b$ 导致的 CRC 可检出错误率的对比]。默认误码率 $P_b = 10^(-5)$ 时，一帧（2104 bit）至少出现 1 bit 错误的概率为：

$ P_"err" = 1 - (1 - P_b)^(L_"bit") ≈ 1 - e^(-L_"bit" P_b) ≈ 1 - e^(-0.02104) ≈ 0.0208 ≈ 2.08% $

即约每 48 帧中就有 1 帧被 CRC 检测出错误并丢弃。相比之下，漏检概率 $~ 2.33 × 10^(-10)$ 比可检出错误概率低约 8 个数量级。因此 CRC-32 在本实验场景中足够可靠。

#strong[更高误码的退化]。当 $P_b$ 升至 $10^(-4)$ 时，$P_"err" ≈ 1 - e^(-0.2104) ≈ 0.189$，约 18.9% 的帧被 CRC 标记为损坏。GBN 协议下 CRC 错误帧导致回退重传整窗口，利用率急剧下降（见表 3 场景 4→5 的落差），但这属于协议层面的「雪崩」效应，而非 CRC 校验本身的不足。

== 探索二：`start_timer` 与 `start_ack_timer` 的设计差异（尹浩铭，结合 `protocol.c`）

根据本仓库 `src/protocol.c` 中的实现，两种定时器的设计存在以下关键差异：

#strong[（1）超时基准不同]。`start_timer(nr, ms)` 的超时时刻为：

$ t_"expire" = t_"now" + "phl_sq_len"() × 8000 / "CHAN_BPS" + ms $

其中 `phl_sq_len()` 返回当前物理层发送队列中尚未离站的字节数，按信道速率折算后再计参数 `ms`。这样做的目的是：如果本地物理层排队较长，自动推迟超时点，#strong[避免「帧还在队列中未来得及上线路就超时」导致的虚假重传]。而 `start_ack_timer(ms)` 的到期时刻仅从当前时刻起算 `ms`，不含排队折算，因为 ACK 帧很短（纯 ACK 仅 7 字节），在等待 ACK_TIMEOUT 的 200 ms 内通常已完成发送。

#strong[（2）触发和重置策略不同]。`start_timer` 在发送一帧或收到有效 ACK 后#strong[无条件更新]定时器（见 `datalink.c` 中 `send_one_data_frame` 和 `update_ack_received`）。但 `start_ack_timer` 的实现（`protocol.c` 第 560 行）为：

```c
if (timer[ACK_TIMER_ID] == 0)
    timer[ACK_TIMER_ID] = now + ms;
```

即#strong[仅当 ACK 定时器未运行时才启动]，对已运行的定时器不重置。这样在连续收到数据帧的场景下，ACK 定时器只启动一次，不会因每次 `FRAME_RECEIVED` 都重置而无限推迟。当捎带 ACK 随下一个数据帧返回对端后，停止 ACK 定时器即可。

#strong[（3）设计意图的工程意义]。

| 定时器类型 | 触发条件 | 核心语义 | 防止的问题 |
|-----------|---------|---------|-----------|
| `start_timer` | 发出数据帧后 | 排队延迟后计时，确保真实超时 | 虚假重传 |
| `start_ack_timer` | CRC 正确且收到有效 DATA 帧后 | 一次启动，不频繁重置，确保最终发送纯 ACK | 捎带 ACK 无限拖延 |

#strong[（4）错误使用场景推演]。若在 ACK_TIMEOUT 分支中错误调用 `start_timer` 代替 `start_ack_timer` 来管理纯 ACK 发送，`phl_sq_len` 的排队项将导致 ACK 超时被人为推迟；在全双工洪水业务下，发送队列可能持续非空，纯 ACK 超时可能被大幅延迟，甚至造成对端发送窗口停滞。若对 `start_ack_timer` 频繁手动重置（即去掉 `if (timer[ACK_TIMER_ID] == 0)` 的条件），则在洪水场景下 ACK 定时器可能被不断推后，纯 ACK 始终不发送，窗口滑动完全依赖反向数据帧的捎带，一旦反向数据暂停，确认信息将无法回传。

#strong[（5）在本实现中的体现]。本组代码 `datalink_recv.c` 实现了 `validate_and_process_frame`，当收到有效 DATA 帧（`rc == 1` 或 `rc == 2`）时调用 `start_ack_timer(ACK_TIMEOUT_MS)`，由库保证不重置已运行的定时器。`datalink.c` 的 `ACK_TIMEOUT` 分支调用 `send_pure_ack` 发送纯 ACK 后 `stop_ack_timer`，二者分工清晰。

#pagebreak()

= 11.5 实验总结和心得体会

== 调试复盘（尹浩铭记录）

#strong[CRC 校验与帧长问题]。首版编译后运行出现段错误，定位为 `recv_frame` 的缓冲区不足：接收缓冲区仅 256 字节，但含 CRC 的完整 DATA 帧为 3（首部）+ 256（载荷）+ 4（CRC）= 263 字节。将 `rxbuf` 扩大为 512 字节后解决。后续又将帧结构中的魔术数 3 替换为宏 `FRAME_HDR_LEN`，避免在全文件范围硬编码。

#strong[纯 ACK CRC 遗漏]。调试初期观察到对端偶发收到纯 ACK 帧后 CRC 校验失败：原因是 `send_pure_ack` 中仅填充了 3 字节的首部就直接调用了 `send_frame`，未附加 CRC。修复后在帧尾计算并追加 4 字节 CRC。

#strong[CRC 校验与 `recv_frame` 长度的关系]。一个较隐蔽的问题是：`recv_frame` 返回的长度参数需要包含末尾 CRC 的 4 字节，才能对整帧做 `crc32(...)==0` 校验。早期版本在 `validate_and_process_frame` 中未拉长 `recv_frame` 的 `size` 参数，导致 `len` 不包含 CRC 域，CRC 校验始终失败。修正后接收路径恢复正常。

#strong[失序帧处理]。GBN 协议要求接收端仅接收按序到达的帧，失序/重复帧应丢弃并重复发送 ACK。初始实现中失序帧虽然未调用 `put_packet`，但错误地推进了 `frame_expected`，导致序号持续偏移、`put_packet` 全部失败。修正后在 `validate_and_process_frame` 中增加 `return 2` 分支：失序帧保持原 `frame_expected` 不变，调用方（`datalink.c` 的 `FRAME_RECEIVED` 分支）仍会处理捎带的 `ack_seq` 并启动 ACK_TIMEOUT，确保对端能收到重复的确认。

== 分工（与《三天三人方案》一致）

- #strong[张恒基]：事件循环、GBN 发送窗口与超时/重传逻辑；保证流程图与代码行号一致。
- #strong[尹浩铭]：帧格式（`include/datalink.h`）、`FRAME_HDR_LEN` 宏、CRC 集成；`datalink_recv.c` 全模块（CRC 校验、重复/失序检测、按序交付 `put_packet`、纯 ACK 组帧与携带 ACK 维护）；排查结构体布局与缓冲区内存问题；撰写 11.4 探索一（CRC 漏检）、探索二（定时器设计差异）及调试复盘。
- #strong[林旭东]：表 3 五场景数据、长稳日志、曲线与 `Makefile`/运行矩阵。

== 对实验库的建议

（简述希望改进的日志接口、统计项等，1–2 段即可。）

#pagebreak()

= 11.6 源程序文件

列出提交的自写文件：`src/datalink.c`、`include/datalink.h` 等；教师库 `src/protocol.c`、`include/protocol.h` 勿算作自研行数但须在报告中引用其接口语义。

#strong[关键宏与代码一致性检查清单]（实现完成后逐项打勾）：

#align(center)[
  #table(
    columns: (2.2fr, 0.5fr),
    inset: 8pt,
    align: (left, center),
    stroke: 0.5pt + gray,
    [窗口宏 `MAX_WINDOW_SIZE` / `MAX_SEQ` 与报告 11.3 推导一致], [□],
    [`DATA_TIMEOUT_MS`、`ACK_DELAY_MS`（或等价名）与推导一致并在注释中写明 RTT 估算], [□],
    [表 3 命令行、利用率与日志文件名一致], [□],
    [流程图标注的 `datalink.c` 行号已更新], [□],
    [附录含 $>= 20$ 分钟量级稳定运行摘录], [□],
    [研究与探索 $>= 2$ 题，至少一题含量化或小程序], [□],
  ),
]

= 附录

== 关键日志摘录

（粘贴 `datalink-A.log` / `datalink-B.log` 中带时间戳的 `put_packet` 输出；说明场景与总时长。）

// 如需插图：将 PNG 放在 docs/assets/ 下
// #figure(image("assets/利用率曲线.png", width: 85%), caption: [理论 vs 实测利用率])
