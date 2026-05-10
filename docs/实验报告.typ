// 计算机网络实验一 · 数据链路层滑动窗口协议 — 实验报告（Typst）
// 编译：在仓库根目录执行  typst compile docs/实验报告.typ
// 预览：typst watch docs/实验报告.typ

#set document(
  title: [数据链路层滑动窗口协议 — 实验报告],
  author: ("", "", ""),
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
  // Windows 常见中文字体；若编译报缺字，可改为 "Microsoft YaHei" 或安装「思源宋体」后改为 "Source Han Serif SC"
  font: ("Times New Roman", "SimSun", "SimHei"),
)

#set par(justify: true, first-line-indent: 2em, leading: 0.65em)
#set heading(numbering: "1.1")

// ---------- 封面信息（请修改） ----------
#let 课程名称 = [计算机网络]
#let 实验名称 = [实验一：数据链路层滑动窗口协议的设计与实现]
#let 姓名 = [　　　　　　　　　]
#let 学号 = [　　　　　　　　　　　　]
#let 班级 = [　　　　　　　　　]
#let 日期 = [　　　年　　　月　　　日]

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
    [姓　名], [#姓名],
    [学　号], [#学号],
    [班　级], [#班级],
    [日　期], [#日期],
  )
]

#pagebreak()

// ---------- 正文目录 ----------
#outline(title: [目　录], indent: 1.5em)
#pagebreak()

= 11.1 实验内容和实验环境描述

== 实验任务与目标

（对照指导书第 2、6 节撰写：全双工、8000 bps、270 ms 时延、默认误码率、#raw("PKT_LEN", lang: "none") 等；说明本组选择的协议类型：停等 / 搭载 ACK 的 GBN / 选择重传等。）

== 实验环境

（硬件配置、操作系统、Visual Studio 或 GCC 版本、工程路径、可执行文件位置、双终端启动方式。）

#pagebreak()

= 11.2 软件设计

== （1）数据结构

（说明 #raw("struct frame", lang: "none") 或等价结构中各字段含义；发送/接收缓冲区与窗口变量；定时器编号与发送序号的对应关系。）

#figure(
  table(
    columns: (1fr, 1.2fr, 2.2fr),
    inset: 8pt,
    align: (left, left, left),
    stroke: 0.5pt + gray,
    [*变量名*], [*类型*], [*作用*],
    [（示例）], [ ], [ ],
    [ ], [ ], [ ],
  ),
  caption: [重要全局变量 / #raw("main", lang: "none") 内主要变量],
)

== （2）模块结构

（列出自写函数：功能、参数、返回值；可在此处插入调用关系图 #raw("figure", lang: "none") 或引用导出的 PNG/SVG。）

== （3）算法流程

（给出从 #raw("protocol_init", lang: "none") 到事件循环的流程图；标出 #raw("NETWORK_LAYER_READY", lang: "none")、#raw("FRAME_RECEIVED", lang: "none")、#raw("DATA_TIMEOUT", lang: "none")、#raw("ACK_TIMEOUT", lang: "none") 及 #raw("enable_network_layer", lang: "none") / #raw("disable_network_layer", lang: "none") 的条件。）

#pagebreak()

= 11.3 实验结果分析

+ 有误码信道下是否实现无差错分组传输（网络层是否异常退出）。
+ 长时间运行稳定性（建议不少于指导书第 9 节所述量级，并写明实际运行时长）。
+ 协议参数：窗口大小、重传定时器、ACK 定时器（若有）的取值及定量推导（指导书第 6、11.3 节）。
+ 理论分析：无误码时最大信道利用率；有误码下简化模型的利用率上界（指导书 11.3(5)）。
+ 实测与理论对比：表 3 数据、差距原因、改进设想。
+ 失败用例与问题：现象、是否已修复。

#figure(
  table(
    columns: (0.5fr, 1.3fr, 1.4fr, 1.4fr, 0.7fr, 1fr),
    inset: 6pt,
    align: center,
    stroke: 0.5pt + gray,
    [*序号*], [*场景*], [*A 命令*], [*B 命令*], [*利用率 %*], [*备注*],
    [1], [无误码], [ ], [ ], [ ], [ ],
    [2], [默认业务], [ ], [ ], [ ], [ ],
    [3], [双端洪水+无误码], [ ], [ ], [ ], [ ],
    [4], [双端洪水], [ ], [ ], [ ], [ ],
    [5], [洪水+高误码], [ ], [ ], [ ], [ ],
  ),
  caption: [性能测试记录（指导书表 3，可按 PDF 增删行）],
)

#pagebreak()

= 11.4 研究和探索的问题

（从指导书第 10 节中选若干题：如 CRC 检错能力、#raw("start_timer", lang: "none") 与 #raw("start_ack_timer", lang: "none") 设计差异、测试方案目的、与 LAPB 对比等。每题：结论 + 推导/引用。）

#pagebreak()

= 11.5 实验总结和心得体会

（按指导书 11.5：实际上机时间；工具问题；C 语言与调试；协议与死锁、参数调整；对实验库的建议；收获。）

#pagebreak()

= 11.6 源程序文件

（列出提交的自写文件，如 #raw("src/datalink.c", lang: "none")、#raw("include/datalink.h", lang: "none") 等；若课程要求附录源码，可说明「见附件」或粘贴关键片段。）

= 附录（可选）

== 关键日志摘录

（从 #raw("datalink-A.log", lang: "none") / #raw("datalink-B.log", lang: "none") 摘抄带时间戳片段。）

// 如需插入截图：将图片放在 docs/assets/ 下，取消下一行注释并改文件名
// #figure(image("assets/表3截图.png", width: 90%), caption: [表 3 或利用率截图])
