#set page(
  paper: "a4",
  margin: (x: 2.5cm, y: 2.8cm),
  header: align(right)[数据链路层实验 · 四天四人协作方案],
  numbering: "1",
)

#set text(font: ("Times New Roman", "SimSun"), size: 11pt)
#set par(justify: true, leading: 1.35em, first-line-indent: 2em)
#set heading(numbering: "1.1")

#show heading: it => {
  it
  par[#text(size: 0pt)[]]
}

#let 张 = [张恒基（2024210926）]
#let 尹 = [尹浩铭（2024210910）]
#let 林 = [林旭东（2024210915）]
#let 赵 = [赵博宇（2024210908）]

#align(center)[
  #v(3em)
  #text(size: 22pt, weight: "bold", font: ("Times New Roman", "SimHei"))[四天 · 四人协作方案]

  #v(1em)
  #text(size: 14pt)[实验一：数据链路层滑动窗口协议（搭载 ACK 的 Go-Back-N）]

  #v(5em)
  #grid(
    columns: (100pt, 260pt),
    row-gutter: 1.4em,
    align(right)[*小组成员：*], align(left)[#张、#尹、#林、#赵],
    align(right)[*组长 / 调度：*], align(left)[#张（协议主控、难点攻关、每日合并节奏）],
    align(right)[*适用周期：*], align(left)[连续 4 个工作日（可顺延为 4 个「实验日」）],
    align(right)[*文档版本：*], align(left)[2026-05（v4：四人编制 + 学号）],
  )
]

#pagebreak()

#outline(title: "目录", depth: 2, indent: 1.5em)

#pagebreak()

= 目标与总原则

本方案将指导书第 7 节压缩为 #strong[4 天、4 人并行]，并与第 11 节报告、第 9 节表 3、第 10 节探索及 #raw("docs/实验要求对照检查清单.md") 对齐。

#strong[张恒基]职责不变：#raw("src/datalink.c") 事件循环与 GBN 发送侧（窗口、定时器、物理层闸门、对称死锁修复）；#strong[整体进度调度]（每日 17:00 前合并窗口、PR 审阅、难点拍板）。其余三人按域并行，#strong[赵博宇]主责构建/过程记录/联调环境，减轻林旭东在「跑测 + 统稿」上的单点压力。

== 2026-05 收尾状态（代码口径）

- #strong[学生代码]：#raw("src/datalink.c")、#raw("src/datalink_recv.c")、#raw("include/datalink.h")。
- #strong[当前宏]：#raw("WINDOW_SIZE=5")、#raw("MAX_SEQ=255")、#raw("NR_BUFS=256")、#raw("DATA_TIMEOUT_MS=600")、#raw("ACK_TIMEOUT_MS=50")（对称死锁优化后）。
- #strong[构建]：VS 与 #raw("make") 输出统一在 #raw("build/datalink.exe") 或 #raw("build/datalink")。

#pagebreak()

= 库接口语义备忘

+ #raw("phl_sq_len()")：物理层发送队列未离站字节数。
+ #raw("start_timer(nr, ms)")：超时 = 当前时刻 + 排队发送时间 + #raw("ms")。
+ #raw("PHYSICAL_LAYER_READY")：队列低于 #raw("PHL_SQ_LEVEL")（50 字节）时通知可继续发送；与 #raw("phl_ready") 及循环末尾闸门协同。

#strong[接收侧与纯 ACK（避免与张恒基重复）：]
- #strong[#尹]：#raw("FRAME_RECEIVED") 上 CRC、按序 #raw("put_packet")、捎带 #raw("ack")；#raw("send_pure_ack") 组帧接口。
- #strong[#张]：#raw("wait_for_event") 与各 #raw("case")；#raw("ACK_TIMEOUT") 调用尹的纯 ACK；#raw("refresh_network_layer_gate") 与 #raw("phl_ready")。

#pagebreak()

= 角色基线

#align(center)[
  #table(
    columns: (1.35fr, 0.95fr, 2.7fr),
    align: (left, center, left),
    stroke: 0.45pt + gray,
    [*成员*], [*主责域*], [*默认产出物*],
    [#张], [协议主控 / 组长], [#raw("datalink.c") 全事件循环；GBN 窗口与重传；#raw("phl_ready") 闸门；报告 11.2（2）（3）、11.3 公式与宏；11.5 复盘；#strong[每日合并节奏与难点拍板]],
    [#尹], [帧与校验 / 接收], [#raw("datalink_recv.c")；#raw("datalink.h") 帧布局与常量（与张核对）；11.2（1）；11.4 探索一（CRC）、探索二（定时器）；调试复盘],
    [#林], [表 3 统稿 / 报告 PDF], [表 3 数据汇总与 #raw("docs/实验报告.typ") 回填；11.3 理论对比表与曲线；#raw("typst compile")；检查清单；#strong[不写] #raw("datalink.c") 接收逻辑],
    [#赵], [构建 / 过程 / 联调], [#raw("Makefile")、#raw("build/")、VS 双端可编；#raw("docs/实验过程记录.md") 7.x；表 3 #strong[场景 1、2、4] 实测与日志归档；11.1 环境、11.6 小结；Git 分支与双站命令清单；#strong[四人联调主持]],
  )
]

= 与检查清单对应

#align(center)[
  #table(
    columns: (1.2fr, 2.2fr, 2.3fr),
    align: (left, left, left),
    stroke: 0.45pt + gray,
    [*检查项*], [*交付物*], [*主责*],
    [全双工无差错（2、6）], [双站无 bad packet], [#张 + #赵 联调环境 + 全员],
    [利用率与表 3（9）], [五场景 + 11.3 对比], [#林 统稿 + #赵 部分跑测 + #张 公式],
    [过程记录（7）], [#raw("docs/实验过程记录.md")], [#赵 主笔 + 全员补观测],
    [探索题（10）], [11.4 两题], [#尹 + #林 可选脚本],
    [提交与演示], [纸质 / 平台 / 演示], [#赵 清单 + #林 PDF + 全员],
  ),
)

#pagebreak()

= 四天日程总览

#set par(first-line-indent: 0em)

== 第 1 天 · 设计冻结 + 环境

- #strong[#张]：#raw("datalink.c") 事件骨架；停等最小闭环。
- #strong[#尹]：#raw("struct frame") + CRC 边界；组帧接口签名。
- #strong[#林]：#raw("docs/实验报告.typ") 目录与表 3 表头草稿。
- #strong[#赵]：#raw("Makefile") / VS → #raw("build/")；#raw("docs/实验过程记录.md") 7.1–7.2；Git 分支策略；更新 #raw("docs/开发说明.md")。

== 第 2 天 · GBN + 表 3 数据

- #strong[#张]：GBN 窗口、#raw("DATA_TIMEOUT") 重传、#raw("phl_ready") 闸门；#raw("ACK_TIMEOUT") 调纯 ACK。
- #strong[#尹]：#raw("FRAME_RECEIVED") 全链路 + #raw("send_pure_ack")；11.4 探索一草稿。
- #strong[#林]：表 3 场景 3、5 长测；回填 #raw("docs/实验报告.typ")。
- #strong[#赵]：表 3 场景 1、2、4 各 $>= 10$ min；日志命名 #raw("table3-*.log")；#strong[四人联调 1 h]（#raw("--flood") / #raw("--utopia")）。

== 第 3 天 · 长稳 + 探索定稿

- #strong[#张]：根据日志修复死锁/利用率；11.3 有误码叙述；行号表给林、赵。
- #strong[#尹]：11.4 探索二正文；定时器走查。
- #strong[#林]：高误码长测 $>= 20$ min；11.3 理论曲线。
- #strong[#赵]：附录日志切片与归档；过程记录 7.3–7.4；11.1 环境节定稿。

== 第 4 天 · 报告合并 + 提交

- #strong[#张]：11.2（3）流程图行号终稿；11.5 心得。
- #strong[#尹]：全仓魔法数→宏；审阅 PDF 中 11.4。
- #strong[#林]：#raw("typst compile docs/实验报告.typ")；对照检查清单；#raw("main") 合并。
- #strong[#赵]：11.6 小结；院系提交项勾选；演示路径文档；备份 #raw("build/datalink.exe") 与表 3 命令一页纸。

#set par(first-line-indent: 2em)

#pagebreak()

= 文档轮值（对齐 #raw("docs/实验报告.typ")）

#align(center)[
  #table(
    columns: (1fr, 2.4fr),
    align: left,
    stroke: 0.45pt + gray,
    [*节点*], [*负责段落*],
    [第 1 天末], [#赵：11.1 环境与 Git；#尹：11.2（1）；#张：11.2（2）（3）提纲],
    [第 2 天末], [#张：11.3 推导；#尹：11.4 探索一；#林：表 3 汇总；#赵：过程记录 7.3],
    [第 3 天末], [#尹：11.4 探索二；#张：11.5；#林：11.3 图表；#赵：附录日志],
    [第 4 天末], [#林：全文 PDF + 清单；#赵：11.6；#张：终检发送侧与宏一致],
  )
]

= 张恒基（组长）调度要点

+ #strong[合并窗口]：每日 17:00 前各员向 #raw("main") 提 PR；冲突由改动人解决，张恒基仲裁 #raw("datalink.c")。
+ #strong[不抢活]：张不实现 #raw("FRAME_RECEIVED") 内部 CRC/去重；不独占表 3 跑数（交林、赵）；不独自改 #raw("typst") 全书。
+ #strong[对外接口]：向林旭东提供宏表 + 行号表；向赵博宇提供可复现的双站命令与 #raw("git rev-parse --short HEAD")。

= 风险与对策

- #strong[四人改同一文件：]#raw("datalink.h") 字段冻结后仅尹提议、张合入发送侧引用。
- #strong[构建路径不一：]统一在 #raw("build/") 运行 #raw("datalink.exe")，过程记录中写清路径。
- #strong[报告与代码宏不一致：]以 #raw("include/datalink.h") 为准，张恒基终检发送侧与 11.3。

// typst compile docs/四天四人方案.typ
