#set page(
  paper: "a4",
  margin: (x: 2.5cm, y: 3cm),
  header: align(right)[计算机网络实验报告 - 数据链路层滑动窗口协议],
  numbering: "1",
)

// 设置中英文字体与段落
#set text(font: ("Times New Roman", "SimSun"), size: 12pt)
#set par(justify: true, leading: 1.5em, first-line-indent: 2em)
#set heading(numbering: "1.1")

// 修复 Typst 标题后第一段不缩进的问题
#show heading: it => {
  it
  par[#text(size: 0pt)[]]
}

// 封面设计
#align(center)[
  #v(4em)
  #text(size: 26pt, weight: "bold", font: ("Times New Roman", "SimHei"))[计算机网络实验报告]

  #v(2em)
  #text(size: 18pt, weight: "bold", font: ("Times New Roman", "SimHei"))[实验一：数据链路层滑动窗口协议的设计与实现]

  #v(8em)
  #grid(
    columns: (120pt, 200pt),
    row-gutter: 2em,
    align(right)[*小组成员：*], align(left)[张恒基、尹浩铭、林旭东],
    align(right)[*协议类型：*], align(left)[搭载 ACK 的 Go-Back-N 协议],
    align(right)[*日　　期：*], align(left)[2026 年 5 月],
  )
]

#pagebreak()

// 目录
#outline(title: "目录", depth: 2, indent: 1.5em)

#pagebreak()

= 实验内容和实验环境描述

== 实验任务与目标
本实验的核心任务是利用数据链路层基本原理，设计并实现一个滑动窗口协议。实验要求在仿真环境下，完成有噪音信道下的两站点（A 站与 B 站）间的无差错全双工通信。通过本次实验，我们旨在深刻理解 CRC 校验技术以及滑动窗口的流量控制与差错恢复机理。

实验给定的信道模型如下：
- #strong[信道带宽]：8000 bps 全双工卫星信道。
- #strong[传播时延]：单向传播时延 270 ms。
- #strong[信道误码率]：默认 $10^(-5)$（即 $1 times 10^(-5)$）。
- #strong[物理层与网络层接口]：网络层分组长度固定为 256 字节；数据链路层通过 #raw("send_frame") / #raw("recv_frame") 与物理层交互（物理层仿真实现 8000 bps 与传播时延等）。

本小组综合评估了实现难度与传输效率，最终选择实现的协议类型为：#strong[使用搭载 ACK 技术的 Go-Back-N（后退 N 帧）协议]。

== 实验环境
- #strong[硬件配置]：Intel Core i7-12700H，16GB RAM。
- #strong[操作系统与开发环境]：Ubuntu 22.04 LTS，GCC 11.4.0（Linux 仿真环境）；Windows 下亦可使用 Visual Studio 打开 `Lab1-Windows-VS2017/datalink.sln` 编译同一套 `src/` 源码。
- #strong[工程结构]：仓库根目录采用 `Makefile` 进行自动化构建。
- #strong[启动方式]：分别在两个终端执行 #raw("./datalink -d3 A") 与 #raw("./datalink -d3 B") 启动双端进程（调试输出可用 #raw("-d3")）。

= 软件设计

== 数据结构
为了在网络层和物理层之间可靠地传递数据，我们定义了帧结构（与实现中 `struct frame` / `FRAME` 命名一致即可）。为便于组帧与 CRC 计算，字段顺序需与发送缓冲区布局一致：

#align(center)[
  #table(
    columns: (2fr, 2fr, 4fr),
    align: center,
    [*变量名*], [*类型*], [*作用说明*],
    [#raw("kind")], [unsigned char], [标识帧类型：如 #raw("FRAME_DATA") 与 #raw("FRAME_ACK")],
    [#raw("seq")], [unsigned char], [数据帧发送序号（取值范围由序号位数与窗口大小共同约束）],
    [#raw("ack")], [unsigned char], [捎带确认序号：表示该序号及以前的帧已被接收端正确接收（语义需在组内统一为「下一期望序号」或「累积 ACK」）],
    [#raw("data")], [unsigned char\[256\]], [载荷，与 #raw("PKT_LEN") 一致，由 #raw("get_packet()") 填充],
    [#raw("padding") / CRC 区], [unsigned int 或附加 4 字节], [CRC-32：实现中常在帧尾附加 4 字节校验域；若放在结构体末尾字段，须与 #raw("put_frame") 长度计算一致],
  )
]

#strong[核心状态变量说明：]
- #raw("next_frame_to_send")：发送窗口上界，下一个待发新帧序号。
- #raw("ack_expected")：发送窗口下界，已发送尚未被确认的最老帧序号。
- #raw("frame_expected")：接收端按序期望的下一帧序号。
- #raw("out_buf[]")：发送缓存，用于在 #raw("DATA_TIMEOUT") 时从窗口下界起回退重传（GBN）。

== 模块结构与算法流程
本协议基于事件驱动模型，核心是一个运行在 #raw("wait_for_event()") 上的状态机。

+ #strong[初始化（#raw("protocol_init")）]：建立 TCP 连接、初始化日志与时间基准；链路层在准备好流量控制策略前可调用 #raw("disable_network_layer()")，避免过早 #raw("get_packet")。
+ #strong[事件分发（#raw("switch (event)")）]：
  - #raw("NETWORK_LAYER_READY")：调用 #raw("get_packet()") 取分组，组帧、捎带 #raw("ack")、计算 CRC32 并 #raw("send_frame()")；对未确认帧启动 #raw("start_timer(seq, ...)")。
  - #raw("PHYSICAL_LAYER_READY")：物理层发送队列低于约 50 字节；若仍有待发帧应继续发送，并维护「物理层可发」标志（指导书 8.8：本事件不会在未发送时重复投递）。
  - #raw("FRAME_RECEIVED")：#raw("recv_frame()") 读入整帧；#strong[先做 CRC 校验]，失败则丢弃。成功则根据 #raw("ack") 滑动发送窗口并 #raw("stop_timer")；对按序到达的 DATA 调用 #raw("put_packet()")；根据策略 #raw("start_ack_timer") / 立即发纯 ACK。
  - #raw("DATA_TIMEOUT")：GBN 从 #raw("ack_expected") 起重传窗口内帧并重启相应定时器（须保证重传路径上定时器被重新启动，否则易出现「静默死锁」）。
  - #raw("ACK_TIMEOUT")：无数据可捎带时发送纯 ACK 控制帧，避免对接收方确认长期滞留。
+ #strong[流量控制]：每次循环末尾根据「窗口是否已满」与物理层是否就绪，在 #raw("enable_network_layer()") 与 #raw("disable_network_layer()") 之间切换。

= 实验结果分析

我们在不同模式与误码率下进行长时压力测试；在实现完整 GBN 逻辑后，程序应能在高误码下持续运行数十分钟而不出现网络层「坏分组」中止（指导书 8.13）。下表为一次 15 分钟量级运行末段 #raw("lprintf") 统计的示例数据，#strong[具体数值以你们当时日志为准]。

== 性能测试记录与参数选择
#align(center)[
  #table(
    columns: (auto, auto, auto, auto, auto),
    align: center,
    table.header(
      [*序号*], [*测试场景*], [*命令选项*], [*A 站利用率*], [*B 站利用率*],
    ),
    [1], [无误码数据传输], [#raw("--utopia")], [51.6%], [97.0%],
    [2], [默认平缓业务], [(无附加参数)], [47.7%], [86.9%],
    [3], [双端洪水 + 无误码], [#raw("--flood --utopia")], [97.0%], [97.0%],
    [4], [双端洪水 + 默认误码], [#raw("--flood")], [88.1%], [87.7%],
    [5], [洪水 + 高误码 $(10^(-4))$], [#raw("--flood -b 1e-4")], [23.1%], [46.8%],
  )
]

#emph[（注：上表为示例数据，用于与理论数量级对照；正式报告须替换为你们自己的命令行、时长与利用率。）]

== 理论推导与差距分析
#strong[1. 窗口大小与定时器（定量草算）]

设数据载荷 256 字节，若帧头与校验共 7 字节，则一帧长度 $L approx 263$ 字节，合 $2104$ bit。在 8000 bps 下，发送一帧所需传输时间 $T_x = 2104 / 8000 approx 0.263 thin "s"$（约 263 ms）。单向传播时延 $T_p = 270 thin "ms"$。若 ACK 帧很短，其发送时间可近似忽略，则往返时间量级为：
$ "RTT" approx 2 T_p + T_x approx 540 thin "ms" + 263 thin "ms" = 803 thin "ms" $

GBN 要保持「管道不空」，窗口内未确认数据在途时间应覆盖一次往返：粗略有 $W * T_x >= T_x + "RTT"$，代入得 $W >= (T_x + "RTT") / T_x approx 810 / 263 approx 3.08$。故序号空间至少需覆盖约 4 个并发未确认帧以上；工程中常取更充裕的窗口（如序号 0～7 共 8 个编号），并注意区分 #raw("MAX_SEQ") 与「允许未确认帧个数」等定义。

重传定时器 #raw("DATA_TIMEOUT") 应略大于「正常往返 + 排队发送」时间。示例取 $2800 thin "ms"$：既减少过早超时造成的无效重传，又能在连续丢 ACK 时触发回退。

#strong[2. 利用率上界与实测对比]

无误码且载荷占主导时，线路利用率上界近似为数据字节占帧长比例：$256 / 263 approx 97.34%$。表中情景 3 的 97.0% 与该上界同量级，说明无误码洪水下实现接近「吃满」有效载荷。

在误码 $10^(-4)$ 的洪水情景（表 5），GBN 的「一处出错、退回重传」会丢弃大量本已正确到达的后续帧，利用率显著下降（示例 A 端 23.1%）。这与理论预期一致，也说明在恶劣信道上选择重传（SR）往往更划算——可作为报告中的对比讨论。

= 研究和探索的问题

#strong[问题：CRC 能否支撑「无差错传输」的客户预期？]

理论上不存在能检测所有错误的有限长度校验；但 CRC-32（与 IEEE 802.3 相同生成多项式）在实际链路误码模型下漏检概率极低：可检测所有奇数位错误、所有长度 $<= 32$ 的突发错误；更长突发错误的漏检概率量级约为 $2^(-32) approx 2.3 times 10^(-10)$。在比特误码率 $10^(-5)$ 量级、帧长数百字节的条件下，未检出错误导致错误上交网络层的概率极低。工程上还可叠加端到端校验（如 TLS、应用层摘要）换取额外可靠性，代价是 CPU 与带宽开销。

= 实验总结和心得体会

- #strong[实际上机时间]：约 15 小时（含阅读指导书、编码、联调与写报告）。
- #strong[团队协作与分工]：
  - #strong[张恒基]：状态机主循环与窗口边界条件；处理 #raw("start_timer") / #raw("stop_timer") 与物理层就绪的协同。
  - #strong[尹浩铭]：帧结构与 CRC 集成；排查结构体布局、长度与 #raw("recv_frame") 缓冲区导致的内存问题。
  - #strong[林旭东]：长时压测与数据记录；维护 `Makefile` / CI 脚本；整理日志并与理论曲线对照。
- #strong[协议死锁调试经历]：
  早期曾出现运行数分钟后双方利用率归零：分析 #raw("datalink-A.log") 发现 #raw("DATA_TIMEOUT") 重传路径未重新 #raw("start_timer")，若重传帧再次因误码被丢弃，发送端将不再超时唤醒，窗口卡死。补齐重传后定时器重启逻辑后，长时间高误码洪水测试恢复稳定。
- #strong[总结]：
  通过实现搭载 ACK 的 GBN，我们把教材中的流量控制与差错控制落实为可观测的日志与时间线，体会到协议软件中「边界条件」与「定时器语义」对正确性的决定性影响。

= 源程序文件

本仓库核心自研文件为 #raw("src/datalink.c")、#raw("include/datalink.h")；教师仿真库位于 #raw("src/protocol.c") 等。以下为与报告描述一致的帧结构与接收分支示意（正式提交以仓库实际代码为准）：

```c
/* include/datalink.h 与 src/datalink.c 节选示意 */
#define MAX_SEQ 7
typedef struct {
    unsigned char kind;
    unsigned char seq;
    unsigned char ack;
    unsigned char data[256];
    unsigned int  padding; /* 或与 crc32 追加 4 字节二选一，须与 send 一致 */
} FRAME;

/* 核心接收逻辑片段 */
case FRAME_RECEIVED:
    len = recv_frame((unsigned char *)&r_frame, sizeof(r_frame));
    if (len < 5 || crc32((unsigned char *)&r_frame, len) != 0) {
        dbg_event("Bad CRC Checksum, packet dropped.\n");
        break;
    }
    /* 根据 ack 滑动发送窗口、按序交付 data ... */
    break;
```
