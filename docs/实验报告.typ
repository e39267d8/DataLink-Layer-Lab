// 计算机网络实验一 · 数据链路层滑动窗口协议 — 实验报告（Typst）
// 编译：typst compile docs/实验报告.typ
// 预览：typst watch docs/实验报告.typ

#set document(
  title: [数据链路层滑动窗口协议 — 实验报告],
  author: ("张恒基", "尹浩铭", "林旭东", "赵博宇"),
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
#let 小组 = [
  张恒基（2024210926）、
  尹浩铭（2024210910）、
  林旭东（2024210915）、
  赵博宇（2024210908）
]
#let 组长 = [张恒基（2024210926）]
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
    [组　　长], [#组长],
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

#strong[与实验库的一致性说明]：下文定时器、`phl_sq_len` 的叙述直接对应本仓库 `src/protocol.c`；滑动窗口状态机与宏常量以最终实现为准：`WINDOW_SIZE = 5`、`MAX_SEQ = 255`、`DATA_TIMEOUT_MS = 600`、`ACK_TIMEOUT_MS = 50`；发送闸门另以 `phl_ready` 与 `PHYSICAL_LAYER_READY` 协同（见 11.2）。

#pagebreak()

= 11.2 软件设计

== 协议选型：为何采用搭载 ACK 的 GBN

本组在指导书允许的三种难度中选定#strong[搭载 ACK 的 Go-Back-N（GBN）]，而非选择重传（SR）或停等，理由如下：

+ #strong[实现复杂度]：SR 需在接收端为窗口外帧维护重排序缓存，并对每一帧单独确认；GBN 接收端仅维护 `frame_expected` 一个序号指针，失序/重复帧丢弃并重复累积 ACK，与 `datalink_recv.c` 体量可控。
+ #strong[全双工捎带 ACK]：本信道为双向同时发送；GBN 将 `ack` 字段嵌入 DATA 帧首部，反向有数据时自然捎带确认，无数据时再以纯 ACK 补足。累积 ACK 语义与「期望下一序号」字段一致，无需 SR 的逐帧 NAK/选择性确认状态机。
+ #strong[与教师参考对齐]：`Lab1-Windows-VS2017/Example/gobackn.exe` 提供 GBN 行为与日志格式对照，便于验收表 3 利用率数量级。
+ #strong[代价认知]：GBN 在 $P_b$ 升高时自窗口下界整段回退，吞吐相对 SR 更易「雪崩」；本实验通过表 3 场景 4→5 的落差定量展示该权衡，而非回避。

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

#strong[序号空间与窗口]：`seq` / `ack` 字段为 1 字节，本实现使用完整 $M = "MAX_SEQ"+1 = 256$ 个编号（0–255），发送窗口取 $W = 5$。GBN 一般要求 $W <= M - 1$，本实现远小于上限；较大的序号空间用于避免误码重传时旧帧在物理层队列中滞留、序号过早回绕后被接收端误认为新帧。

== （2）模块结构

主控结构为：`protocol_init` → 主循环 `wait_for_event` → `switch(event)` 分发。关键接口来自 `protocol.h`：`get_packet` / `put_packet`、`send_frame` / `recv_frame`、定时器与 `enable_network_layer` / `disable_network_layer`。

#align(center)[
  #table(
    columns: (1.2fr, 2fr, 1.1fr),
    inset: 6pt,
    align: (left, left, center),
    stroke: 0.5pt + gray,
    [*模块 / 分支*], [*主要职责*], [*代码位置*],
    [`send_one_data_frame`], [取网络层分组、组 DATA 帧、捎带 ACK、追加 CRC、缓存并发送；发送后置 `phl_ready=0`], [`src/datalink.c:49`],
    [`update_ack_received`], [按累积 ACK 推进发送窗口，维护数据定时器], [`src/datalink.c:31`],
    [`resend_window`], [`DATA_TIMEOUT` 后从 `ack_expected` 起重传窗口内帧], [`src/datalink.c:80`],
    [`FRAME_RECEIVED`], [调用 `validate_and_process_frame`，再处理 ACK、按序上交、启动 ACK 定时器], [`src/datalink.c:132`],
    [`ACK_TIMEOUT`], [调用 `send_pure_ack` 发送纯 ACK], [`src/datalink.c:157`],
    [`refresh_network_layer_gate`], [窗口未满且 `phl_ready` 时 `enable_network_layer`], [`src/datalink.c:95`],
  ),
  caption: [事件循环与主要函数位置],
]

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

`PHYSICAL_LAYER_READY` 在库中当 `phl_sq_len() < "PHL_SQ_LEVEL"`（本仓库 `PHL_SQ_LEVEL = 50` 字节）等条件满足时通知链路层可继续向物理层写字节。

#strong[`phl_ready` 网络层闸门（本组关键优化）]：初版在 `PHYSICAL_LAYER_READY` 分支为空操作，物理层队列排空后发送侧仍因窗口满而长期 `disable_network_layer`，只能等待 `ACK_TIMEOUT` 纯 ACK 才能续发——洪水无误码利用率约 70%。现实现以 `phl_ready` 标志协同：`PHYSICAL_LAYER_READY` 或 `phl_sq_len() < 50` 时置 1；`send_one_data_frame` / `resend_window` 在 `send_frame` 后置 0；`refresh_network_layer_gate()` 仅在 `nbuffered() < WINDOW_SIZE` 且 `phl_ready` 时开闸。修复后场景 3 利用率由约 72% 升至约 94%（见表 3），管线效率约达理论上限的 97%。

== （4）关键代码摘录

#strong[物理层就绪与网络层闸门]（`src/datalink.c`）：

```c
case PHYSICAL_LAYER_READY:
    phl_ready = 1;
    break;
/* ... 每个事件末尾 ... */
static void refresh_network_layer_gate(void)
{
    if (phl_sq_len() < 50)
        phl_ready = 1;
    if (nbuffered() < (unsigned)WINDOW_SIZE && phl_ready)
        enable_network_layer();
    else
        disable_network_layer();
}
```

#strong[组帧发送与 `phl_ready` 置位]（节选）：

```c
static void send_one_data_frame(void)
{
    if (nbuffered() >= (unsigned)WINDOW_SIZE)
        return;
    /* kind / seq / ack / get_packet / crc32 ... */
    send_frame(tx, wire_len);
    phl_ready = 0;
    next_frame_to_send = inc_seq(next_frame_to_send);
    /* start_timer(DATA_TIMER_ID, DATA_TIMEOUT_MS) ... */
}
```

== （5）窗口参数的配置方式

`WINDOW_SIZE`、`ACK_TIMEOUT_MS` 等在 `include/datalink.h` 中以 `#define`#strong[编译期固定]，`protocol_init` 的 `getopt`#strong[不提供]窗口命令行选项。设计考量：窗口宽度与确认语义属于链路层协议规范的一部分，运行时可变窗口需额外协商与一致性校验，超出本实验范围；误码率 $P_b$、洪水 `-f`、无误码 `-u` 等#strong[已由教师库命令行支持]，便于表 3 分场景压测。

若需对比不同 $W$：修改 `datalink.h` 后 `make` 或 VS 重新生成 `build/datalink.exe`，双端必须使用#strong[同一二进制]。经 BDP 推导与表 3 对比实验，$W = 5$ 在 8000 bps / 270 ms 信道下场景 3 实测约 94.1%，距载荷理论上界 97.3% 仅约 3 pp，继续增大窗口边际收益趋近于零，仅增加 `frame_buffer` 内存占用。

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

代入 $t_p = 0.27$ s、$t_"tx" approx 0.263$ s，得 $W >= (0.54 + 0.263)/0.263 approx 3.05$，故教材比特口径下 $W = 4$ 已可填满管道。#strong[本组实现]在 `include/datalink.h` 中取 `WINDOW_SIZE = 5`：按字节 BDP 估算，RTT 内 $8000 times 0.54 approx 4320 thin "bit"$，约合 $540$ 字节；整帧约 $260$ 字节时 $540/260 approx 2.08$，向上取 $3$ 为下界，再取 $5$ 作为#strong[抖动与全双工对称死锁]的缓冲余量（远小于 $M/2$，无序号回绕风险）。配合 `phl_ready` 闸门（11.2），避免窗口满后物理层已空闲却仍无法取新分组。

#strong[（3.1）定时器宏与报告一致]

数据帧重传超时取 `DATA_TIMEOUT_MS = 600`（略大于 RTT $approx 540 thin "ms"$ 加处理余量；库中 `start_timer` 另含 `phl_sq_len` 排队项，见 `src/protocol.c`）。搭载 ACK 等待时间取 `ACK_TIMEOUT_MS = 50`：对称洪水下双方窗口同时满时需依赖纯 ACK 打破僵局，缩短空等可更快释放对端窗口；纯 ACK 仅 7 字节，频率略增对 8000 bps 信道占用可忽略。

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

== 不同误码率下的利用率变化（洪水场景）

双端 `-f` 洪水时，接收方利用率随 $P_b$ 单调下降，与独立误码缩放 + GBN 回退放大一致：

#align(center)[
  #table(
    columns: (0.8fr, 1fr, 0.9fr, 0.9fr, 0.9fr, 1.6fr),
    inset: 5pt,
    align: center,
    stroke: 0.5pt + gray,
    table.header(
      [*表 3 场景*], [$P_b$], [*A 利用率 %*], [*B 利用率 %*], [*均值 %*], [*现象*],
    ),
    [3], [$0$（`-u`）], [94.09], [94.09], [94.09], [管道饱和，Err 0],
    [4], [$10^(-5)$（默认）], [75.99], [75.51], [75.75], [CRC 丢帧 + 超时重传，仍可维持较高吞吐],
    [5], [$10^(-4)$（`-b 1e-4`）], [29.55], [27.31], [28.43], [回退放大，利用率陡降；A/B 对称],
  ),
  caption: [洪水场景下 $P_b$ 升高时的利用率（$W=5$，`ACK_TIMEOUT_MS=50`，`phl_ready` 已启用）],
]

非洪水场景 1（`-u`）与场景 2（默认 $P_b$）受 IBIB 业务不对称影响，A/B 利用率差较大，不宜与上表直接横比，但同样呈现「误码越高、有效吞吐越低」的趋势（见表 3 第 1、2 行）。

== 窗口参数对比实验（$W=3$ vs $W=5$）

指导书要求#strong[调整窗口观察效率变化]。本组在相同五类表 3 命令下，保留旧版日志（`WINDOW_SIZE=3`、`ACK_TIMEOUT_MS=200`、无 `phl_ready` 门控）与优化后复测（`W=5`、`ACK=50 ms`、`phl_ready`）对比如下：

#align(center)[
  #table(
    columns: (1fr, 1.3fr, 1.5fr, 1fr),
    inset: 5pt,
    align: center,
    stroke: 0.5pt + gray,
    table.header(
      [*场景*], [*旧参数 A / B %*], [*新参数 A / B %*], [*变化要点*],
    ),
    [1 无误码], [39.36 / 69.64], [52.90 / 95.15], [+13.5 / +25.5 pp；B 站逼近饱和],
    [3 Flood+Utopia], [72.32 / 72.30], [94.09 / 94.09], [+21.8 pp；对称；`phl_ready` 主因],
    [4 Flood+默认误码], [63.69 / 62.80], [75.99 / 75.51], [+12.3 pp 量级],
    [5 Flood+$10^(-4)$], [32.02 / 31.24], [29.55 / 27.31], [略降但 A/B 对称，无单侧饥饿],
  ),
  caption: [窗口与闸门优化前后利用率对比（每场景 600 s）],
]

#strong[结论]：场景 3 提升最大，证明#strong[物理层就绪信号接入网络层闸门]比单纯增大 $W$ 更关键；$W=3 arrow 5$ 在场景 1、4 亦有明显增益。场景 5 均值略降属高误码下 GBN 固有代价，但消除了旧版 B/A $approx 1.12$ 的不对称异常。

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
    [1], [无误码], [#text(size: 7pt)[#raw("-u -d0 -t 600 -p 59281 -l table3-1-utopia-A.log A")]], [#text(size: 7pt)[#raw("-u -d0 -t 600 -p 59281 -l table3-1-utopia-B.log B")]], [52.90], [95.15], [600 s；Err 0；W=5 复测],
    [2], [默认业务], [#text(size: 7pt)[#raw("-d0 -t 600 -p 59282 -l table3-2-default-A.log A")]], [#text(size: 7pt)[#raw("-d0 -t 600 -p 59282 -l table3-2-default-B.log B")]], [34.18], [61.81], [600 s；Err 20/33],
    [3], [双端洪水+无误码], [#text(size: 7pt)[#raw("-f -u -d0 -t 600 -p 59283 -l table3-3-flood-utopia-A.log A")]], [#text(size: 7pt)[#raw("-f -u -d0 -t 600 -p 59283 -l table3-3-flood-utopia-B.log B")]], [94.09], [94.09], [600 s；Err 0；W=5+phl_ready],
    [4], [双端洪水（默认误码）], [#text(size: 7pt)[#raw("-f -d0 -t 600 -p 59284 -l table3-4-flood-default-A.log A")]], [#text(size: 7pt)[#raw("-f -d0 -t 600 -p 59284 -l table3-4-flood-default-B.log B")]], [75.99], [75.51], [600 s；W=5 复测],
    [5], [洪水+高误码], [#text(size: 7pt)[#raw("-f -b 1e-4 -d0 -t 600 -p 59285 -l table3-5-flood-ber1e-4-A.log A")]], [#text(size: 7pt)[#raw("-f -b 1e-4 -d0 -t 600 -p 59285 -l table3-5-flood-ber1e-4-B.log B")]], [29.55], [27.31], [600 s；对称 Flood],
  ),
  caption: [表 3 实测数据；五场景均自然 `Quit`，未出现 `bad packet` / `Abort`。利用率取日志末次 `packets received` 行中 bps 与 8000 bps 的比例。],
]

#strong[结果分析]。场景 3 在无误码洪水下两端约 #strong[94.1%]（较 $W=3$ 旧版 72.3% 提升约 22 pp），`phl_ready` 打通物理层就绪与网络层开闸是主因。场景 1、4 在 $W=5$ 下亦有双位数 pp 提升（见上一节对比表）。场景 5 均值约 28.4%，略低于旧版 31.6%，但 A/B 对称、无单侧饥饿，符合高误码 GBN 预期。误码率从 0 $arrow 10^(-5) arrow 10^(-4)$ 的洪水利用率阶梯见「不同误码率下的利用率变化」表。

== 实测与理论对比

#align(center)[
  #table(
    columns: (1fr, 1fr, 1fr, 1.2fr, 2fr),
    inset: 6pt,
    align: center,
    stroke: 0.5pt + gray,
    table.header(
      [*场景*], [*理论参考 %*], [*实测 %*], [*差距*], [*原因分析要点*],
    ),
    [3 洪水无误码], [载荷上界 $256/263 approx 97.34$], [94.09], [约 -3.3], [帧头/CRC 与事件循环 `Sleep(15ms)` 等残余开销；`phl_ready` 已消除主要物理层饥饿空等],
    [4 洪水默认误码], [$97.34 times e^(-2104 times 10^(-5)) approx 95.31$], [75.75], [约 -19.6], [误码触发 CRC 丢帧与 GBN 回退；$W=5$ 后仍低于独立缩放上界],
    [5 洪水 $10^(-4)$], [$97.34 times e^(-2104 times 10^(-4)) approx 78.95$], [28.43], [约 -50.5], [高误码下 GBN 窗口回退与重传放大；A/B 对称],
  ),
  caption: [理论值为简化上界，仅用于解释数量级；实测值取 A/B 末次利用率均值],
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

$ t_"expire" = t_"now" + "phl_sq_len"() × 8000 / "CHAN_BPS" + "ms" $

其中 `phl_sq_len()` 返回当前物理层发送队列中尚未离站的字节数，按信道速率折算后再计参数 `ms`。这样做的目的是：如果本地物理层排队较长，自动推迟超时点，#strong[避免「帧还在队列中未来得及上线路就超时」导致的虚假重传]。而 `start_ack_timer(ms)` 的到期时刻仅从当前时刻起算 `ms`，不含排队折算，因为 ACK 帧很短（纯 ACK 仅 7 字节）；本实现 `ACK_TIMEOUT_MS = 50`，在捎带 ACK 不可用时更快触发纯 ACK。

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

#strong[序号空间过小导致旧帧误收]。一次默认误码长跑中，早期 `MAX_SEQ=7` 的版本在约 40 秒出现 `Network Layer received a bad packet`。复查日志后判断：GBN 超时重传会把窗口内帧重新排入物理层队列，若旧重传帧滞留到接收端序号快速绕回，就可能被误认为下一轮的新帧并错误上交网络层。最终使用 `unsigned char` 的完整 0–255 序号空间，将 `MAX_SEQ` / `NR_BUFS` 调整为 255 / 256。

#strong[物理层饥饿与 `phl_ready`（场景 3 核心修复）]。初版 `PHYSICAL_LAYER_READY` 未驱动网络层开闸，洪水无误码利用率约 70%–72%。引入 `phl_ready` 与 `WINDOW_SIZE=5`、`ACK_TIMEOUT_MS=50` 后，场景 3 复测约 94%，详见 `docs/重构优化性能战报.md`。表 3 五场景各 600 秒均自然退出，无坏分组。

== 分工（与《四天四人方案》一致）

- #strong[张恒基（2024210926，组长）]：事件循环、GBN 发送窗口与超时/重传逻辑、`phl_ready` 闸门；整体进度调度；11.2（2）（3）、11.3 公式、11.5 复盘；保证流程图与代码行号一致。
- #strong[尹浩铭（2024210910）]：帧格式（`include/datalink.h`）、`FRAME_HDR_LEN` 宏、CRC 集成；`datalink_recv.c` 全模块；11.4 探索一/二及调试复盘。
- #strong[林旭东（2024210915）]：表 3 五场景数据汇总、长稳日志、理论曲线；`docs/实验报告.typ` 统稿与 `typst` 编译。
- #strong[赵博宇（2024210908）]：`Makefile` / `build/` / VS 构建验证；`docs/实验过程记录.md`；表 3 场景 1、2、4 实测；11.1 环境、11.6 小结；四人联调与提交清单。

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
    [窗口宏 `WINDOW_SIZE` / `MAX_SEQ` 与报告 11.3 推导一致], [✓],
    [`DATA_TIMEOUT_MS`、`ACK_TIMEOUT_MS` 与推导一致并在注释中写明 RTT 估算], [✓],
    [表 3 命令行、利用率与日志文件名一致], [✓],
    [流程图标注的 `datalink.c` 行号已更新], [✓],
    [附录含 600 秒稳定运行摘录], [✓],
    [研究与探索 $>= 2$ 题，至少一题含量化或小程序], [✓],
  ),
]

= 附录

== 关键日志摘录

以下为表 3 末次统计行摘录，日志均在仓库根目录运行时生成：

```text
table3-1-utopia-A.log        598.908 .... 919 packets received, 3149 bps, 39.36%, Err 0 (0.0e+00)
table3-1-utopia-B.log        598.924 .... 1628 packets received, 5571 bps, 69.64%, Err 0 (0.0e+00)
table3-2-default-A.log       599.042 .... 798 packets received, 2734 bps, 34.18%, Err 20 (1.0e-05)
table3-2-default-B.log       599.073 .... 1444 packets received, 4945 bps, 61.81%, Err 33 (1.0e-05)
table3-3-flood-utopia-A.log  (复测) .... packets received, ~7526 bps, 94.08%, Err 0 (0.0e+00)
table3-3-flood-utopia-B.log  (复测) .... packets received, ~7530 bps, 94.13%, Err 0 (0.0e+00)
table3-4-flood-default-A.log 598.565 .... 1488 packets received, 5095 bps, 63.69%, Err 32 (9.4e-06)
table3-4-flood-default-B.log 599.669 .... 1470 packets received, 5024 bps, 62.80%, Err 34 (1.0e-05)
table3-5-flood-ber1e-4-A.log (复测) .... packets received, ~2642 bps, 33.03%, Err (见日志)
table3-5-flood-ber1e-4-B.log (复测) .... packets received, ~2163 bps, 27.04%, Err (见日志)
```

// 如需插图：将 PNG 放在 docs/assets/ 下
// #figure(image("assets/利用率曲线.png", width: 85%), caption: [理论 vs 实测利用率])
