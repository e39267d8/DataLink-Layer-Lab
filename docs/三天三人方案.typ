#set page(
  paper: "a4",
  margin: (x: 2.5cm, y: 2.8cm),
  header: align(right)[数据链路层实验 · 三天三人协作方案],
  numbering: "1",
)

#set text(font: ("Times New Roman", "SimSun"), size: 11pt)
#set par(justify: true, leading: 1.35em, first-line-indent: 2em)
#set heading(numbering: "1.1")

#show heading: it => {
  it
  par[#text(size: 0pt)[]]
}

#align(center)[
  #v(3em)
  #text(size: 22pt, weight: "bold", font: ("Times New Roman", "SimHei"))[三天 · 三人协作方案]

  #v(1em)
  #text(size: 14pt)[实验一：数据链路层滑动窗口协议（搭载 ACK 的 Go-Back-N）]

  #v(5em)
  #grid(
    columns: (100pt, 220pt),
    row-gutter: 1.4em,
    align(right)[*小组成员：*], align(left)[张恒基、尹浩铭、林旭东],
    align(right)[*适用周期：*], align(left)[连续 3 个工作日（可顺延为 3 个「实验日」）],
    align(right)[*文档版本：*], align(left)[2026-05（v3：补充 2026-05-15 收尾状态与实测结论）],
  )
]

#pagebreak()

#outline(title: "目录", depth: 2, indent: 1.5em)

#pagebreak()

= 目标与总原则

本方案将指导书第 7 节（熟悉环境 → 设计 → 编码调试 → 测试 → 报告）压缩为 #strong[3 天、3 人并行]，并与 #strong[第 11 节实验报告结构]、#strong[第 9 节表 3]、#strong[第 10 节研究与探索]及仓库内 #raw("docs/实验要求对照检查清单.md") 的勾选项对齐。

在减少阻塞的前提下保证：#strong[帧格式与窗口语义先冻结]、#strong[事件循环单文件主控]（#raw("src/datalink.c")）、#strong[每日有可演示增量]、#strong[报告叙述与 #raw("src/protocol.c") / 自研宏一致]（尤其 #raw("start_timer")、#raw("phl_sq_len")、#raw("PHL_SQ_LEVEL")）。

== 2026-05-15 收尾状态

- #strong[代码]：搭载 ACK 的 GBN 主体已完成；根目录 #raw("src/datalink.c")、#raw("src/datalink_recv.c")、#raw("include/datalink.h") 为准。最终宏为 #raw("WINDOW_SIZE=3")、#raw("MAX_SEQ=255")、#raw("NR_BUFS=256")、#raw("DATA_TIMEOUT_MS=600")、#raw("ACK_TIMEOUT_MS=200")。
- #strong[关键修正]：早期 #raw("MAX_SEQ=7") 在默认误码长跑中暴露旧重传帧跨序号周期误收风险；已改用 1 字节完整序号空间，窗口大小不变。
- #strong[测试]：表 3 五场景均按 #raw("-t 600") 跑满 10 分钟，日志名为 #raw("table3-*.log")；所有场景自然 #raw("Quit")，未出现 #raw("bad packet") / #raw("Abort")。数据已回填 #raw("docs/实验过程记录.md")、#raw("docs/实验报告.typ") 与根目录 #raw("report.typ")。
- #strong[仍属流程外]：纸质封面、课程平台上传、现场演示按院系通知执行；若老师要求更长稳态证据，可把表 3 命令中的 #raw("-t 600") 改为 #raw("-t 1200") 复跑。

#pagebreak()

= 库接口语义备忘（写入 #raw("datalink.c") 注释或组内 Wiki）

以下与 #raw("src/protocol.c") 一致，避免表格格内挤成一团后语义丢失：

+ #raw("phl_sq_len()")：返回**物理层发送队列**中尚未离站的字节数（本地排队深度）。
+ #raw("start_timer(nr, ms)")：超时时刻为「当前时刻 + #raw("phl_sq_len()")×8000/#raw("CHAN_BPS") + #raw("ms")」；即在排队发送时间**之后**再计 #raw("ms")，减轻「帧还在队列里未上线路就超时」的假重传。（注释里写清公式来源：#raw("protocol.c") 中 #raw("start_timer") 实现。）
+ #raw("start_ack_timer(ms)")：与数据定时器分离；搭载 ACK 的「最晚发纯 ACK」语义以库实现为准（见 #raw("start_ack_timer") / #raw("ACK_TIMEOUT")）。
+ #raw("PHYSICAL_LAYER_READY")：队列长度低于 #raw("PHL_SQ_LEVEL")（本仓库 50 字节）等条件时通知可继续 #raw("send_frame")；与链路层「待发积压」策略配合，避免队列溢出。

#strong[接收侧与纯 ACK 分工（避免与张恒基事件分支重复表述）：]
- #strong[尹浩铭]：#raw("FRAME_RECEIVED") 路径上的 CRC、序号合法性、按序 #raw("put_packet")、捎带 #raw("ack") 字段的维护；提供「组纯 ACK 帧 / 写发送缓冲」等**可调用函数**；异常路径用 #raw("dbg_event") 打标（如 CRC 错、重复帧丢弃）。
- #strong[张恒基]：#raw("wait_for_event") 分发与各 #raw("case")（含 #raw("ACK_TIMEOUT") 内调用尹提供的纯 ACK 发送、#raw("DATA_TIMEOUT") 重传窗口）；#raw("enable_network_layer") / #raw("disable_network_layer") 与 #raw("PHYSICAL_LAYER_READY") 协同。

#strong[共同约定：]
- 代码以仓库根目录 #raw("src/datalink.c")、#raw("include/datalink.h") 为唯一主分支；合并前自测：双站 #raw("-d3") #strong[首日 smoke $>= 5$ min] 无网络层坏分组；填写表 3 的各场景建议各 #strong[$>= 10$ min]；附录长稳证据目标 #strong[$>= 20$ min]（与 #raw("docs/实验报告.typ") 11.3 一致）。
- Git：每人独立分支（如 #raw("feat/zhang-gbn-send")），#strong[每日 17:00 前]向 #raw("main") 发 PR 或 rebase 后 fast-forward；冲突由「改动人」负责解决；报告表 3 旁备注 #raw("git rev-parse --short HEAD") 便于验收对照。
- 文档：主报告源文件为 #raw("docs/实验报告.typ")（`typst compile docs/实验报告.typ`）；根目录 #raw("report.typ") 若保留，须与前者 #strong[章节与数据同步]，避免两份 PDF 内容分叉。过程记录填 #raw("docs/实验过程记录.md")；交表可用课程 #raw("docs/性能测试记录表.docx")。

#pagebreak()

= 与检查清单、报告章节的对应关系

#align(center)[
  #table(
    columns: (1.2fr, 2.2fr, 2.2fr),
    align: (left, left, left),
    stroke: 0.45pt + gray,
    [*检查清单 / 指导书*], [*交付物*], [*主责（可支援）*],
    [一：全双工有误码无差错（2、6）], [双站长时间无 #emph[bad packet]；#raw("datalink.c") 逻辑完整], [张恒基 + 全员联调],
    [一：利用率与参数（2、6、9）], [11.3 定量推导 + 表 3 五场景 + 理论对比表], [林旭东（数据/图）+ 张恒基（公式与宏一致）],
    [三：过程记录、表 3、报告 11 节（7、9、11）], [#raw("docs/实验过程记录.md")、表 3、#raw("docs/实验报告.typ") 全文], [林旭东统稿时间表；三人按轮值填段],
    [三：第 10 节研究与探索], [11.4 至少 2 题；其一宜含量化或小程序（CRC 漏检等）], [尹浩铭（CRC/定时器）+ 林旭东（可选脚本）],
    [清单「核心得分点」4], [11.3 与表 3 互证，勿照抄他组参考数], [林旭东],
    [清单「核心得分点」5], [演示路径与纸质/电子版按院系通知], [林旭东 + 全员],
  ),
  caption: [与 #raw("docs/实验要求对照检查清单.md") 及 #raw("docs/实验报告.typ") 标题（11.1–11.6）对齐],
]

#pagebreak()

= 角色基线（非排他，可互相支援）

#align(center)[
  #table(
    columns: (1.2fr, 1fr, 2.8fr),
    align: (left, center, left),
    stroke: 0.45pt + gray,
    [*成员*], [*主责域*], [*默认产出物*],
    [张恒基], [协议主控 / 状态机], [#raw("datalink.c") 事件分发（含 #raw("ACK_TIMEOUT") 调纯 ACK 发送）；窗口、#raw("DATA_TIMEOUT") 重传与 #raw("start_timer")；#raw("enable/disable_network_layer") 与 #raw("PHYSICAL_LAYER_READY")；#raw("phl_sq_len") 语义注释；报告 11.2（3）、11.3 宏与推导],
    [尹浩铭], [帧与校验 / 接收路径], [#raw("datalink.h")；#raw("send_frame")/#raw("recv_frame") 与 CRC；#raw("FRAME_RECEIVED") 全链路；**提供**纯 ACK 组帧接口；异常 #raw("dbg_*")；报告 11.2（1）、11.4 **探索一** CRC],
    [林旭东], [构建 / 表 3 / 报告统稿], [#raw("Makefile") / VS；**独占**表 3 五场景跑数与回填 #raw("docs/实验报告.typ")；理论曲线与 11.3 表；附录日志；#raw("typst") 与检查清单；**不写** #raw("datalink.c") 接收分支逻辑],
  )
]

= 三天日程总览

下列按人分列，#strong[避免五列表格内换行错位]；与下文「第 1/2/3 天」详述一致。

#set par(first-line-indent: 0em)

== 第 1 天 · 冻结设计 + 最小双工

- #strong[张恒基：]#raw("protocol_init") → 事件循环骨架；#raw("NETWORK_LAYER_READY") / #raw("PHYSICAL_LAYER_READY") 占位；停等最小闭环。
- #strong[尹浩铭：]#raw("struct frame") + #raw("send_frame") 组帧与 CRC 四字节边界；#raw("recv_frame") 缓冲长度。
- #strong[林旭东：]#raw("Makefile") / VS 双端编译；#raw("docs/实验过程记录.md") 7.1–7.2；表 3 命令模板草稿。

== 第 2 天 · GBN + 表 3 全场景数据

- #strong[张恒基：]发送窗口、#raw("DATA_TIMEOUT") 重传且每次重开 #raw("start_timer")；#raw("enable/disable_network_layer")；#raw("ACK_TIMEOUT") 分支里**调用**尹提供的纯 ACK 组帧发送；在 #raw("datalink.c") 顶部或定时器旁写 #raw("phl_sq_len") / #raw("start_timer") 语义注释（见上文「库接口备忘」）。
- #strong[尹浩铭：]**仅接收与 ACK 载荷侧**：#raw("FRAME_RECEIVED") 上 CRC、重复/失序处理、按序 #raw("put_packet")、捎带 #raw("ack")；**不写**表 3 数字、**不跑**长测；异常路径 #raw("dbg_*") 日志可读；**下午**开始 11.4 **探索一**（CRC）草稿或小程序提纲。
- #strong[林旭东：]**仅测试与回填**：表 3 五场景各 $>= 10$ min；把命令、时长、利用率写入 #raw("docs/实验报告.typ")；与张合写 11.3 **理论表初稿**（$W$、$t_"tx"$ 口径一致）。**勿**把「跑表」写进尹格。

== 第 3 天 · 长稳证据 + 报告定稿 + 清单

- #strong[张恒基：]死锁/静默超时复盘；宏与 11.3 正文一致；小步 PR；**下午**定稿 11.2（3）流程图行号 + 11.5 真实心得。
- #strong[尹浩铭：]**上午**将第 2 天已收集的素材整理为 11.4 **第二题**（#raw("start_timer") vs #raw("start_ack_timer")）正文；**下午**全仓走查（魔法数、#raw("struct") 与报告 11.2（1）表一致）；**不再**与第 2 天下午的 CRC 题重复开工——CRC 探索一应在第 2 天末前收口。
- #strong[林旭东：]**上午**只做高误码长测（$>= 20$ min）与日志切片（附录素材）；**下午**再执行一次 #raw("typst compile docs/实验报告.typ")、对照 #raw("docs/实验要求对照检查清单.md") 全勾选、#raw("main") 合并与 PR。**typst 与清单集中在第 3 天下午**，避免与第 2 天「表 3 回填」职责打架。

#set par(first-line-indent: 2em)

#pagebreak()

= 第 1 天：设计冻结 + 环境对齐

== 上午（约 4 h）

- #strong[全员（0.5 h）]：对照指导书 8.6–8.10 与 #raw("docs/实验报告.typ") 11.2（3），在白板或文档中统一：序号空间、累积 ACK 语义、#raw("MAX_SEQ") 与窗口宽度关系；确认物理层 API 为 #raw("send_frame") / #raw("recv_frame")（勿与教材笔误混用）。
- #strong[张恒基]：在 #raw("datalink.c") 中落地 #raw("protocol_init") → #raw("disable_network_layer") → #raw("for (;;)") 骨架；各 #raw("case") 内先用 #raw("dbg_event") 打桩，保证双站能启动并写日志。
- #strong[尹浩铭]：冻结 #raw("struct frame") 字段顺序与「CRC 四字节附加」写法；写出组帧辅助函数签名，供张接入 #raw("send_frame")。
- #strong[林旭东]：Windows #raw("Lab1-Windows-VS2017") 与 Linux #raw("make") 各编一次；记录可执行路径与默认日志文件名，更新 #raw("docs/开发说明.md")；打开 #raw("docs/实验过程记录.md") 填写环境与会话信息。

== 下午（约 4 h）

- #strong[张恒基]：实现「停等级」最小闭环：单未确认帧时 #raw("NETWORK_LAYER_READY") → 组帧 #raw("send_frame") → #raw("FRAME_RECEIVED") 收 ACK 后释放窗口（为第 2 天扩展为 GBN 留接口）。
- #strong[尹浩铭]：与张结对联调 #raw("crc32") 长度；排查首版段错误（对齐、#raw("recv_frame") 缓冲长度）。
- #strong[林旭东]：整理 Git 分支策略；为表 3 建立可复制命令清单（#raw("--flood")、#raw("--utopia")、#raw("-b 1e-4") 等），写入 #raw("docs/实验过程记录.md") 或 #raw("scripts/")。

#strong[当日交付物：]可运行的「最小双工」+ 冻结的 #raw("datalink.h") + 过程记录已开笔 + 分支策略说明。

#pagebreak()

= 第 2 天：GBN 主体与捎带 ACK

== 上午

- #strong[张恒基]：扩展为 GBN：#raw("next_frame_to_send")、#raw("ack_expected")、流水线发送；#raw("DATA_TIMEOUT") 从 #raw("ack_expected") 起重传窗口内帧并#strong[每次重传后重新 #raw("start_timer")]；#raw("case ACK_TIMEOUT") 中调用尹提供的纯 ACK 组帧并发 #raw("send_frame")。
- #strong[尹浩铭]：实现 #raw("FRAME_RECEIVED") 全链路（CRC、重复/失序、按序 #raw("put_packet")、维护捎带 #raw("ack")）；实现「纯 ACK 帧」组帧接口供张在 #raw("ACK_TIMEOUT") 调用；异常路径打 #raw("dbg_event")，**不负责**表 3 跑数与 #raw("typst")。
- #strong[林旭东]：独占表 3：五场景各 $>= 10$ min；草稿表 → 回填 #raw("docs/实验报告.typ")；**勿照抄** #raw("docs/性能测试记录表-参考数据.docx")。

== 下午

- #strong[三人联调（1 h）]：双端 #raw("--flood --utopia") 与 #raw("--flood")，观察是否出现网络层坏分组或利用率断崖。
- #strong[张恒基]：循环末尾 #raw("enable/disable_network_layer") 与 #raw("PHYSICAL_LAYER_READY") 协同；在 #raw("start_timer") 调用处旁写注释，引用「库接口语义备忘」中 #raw("phl_sq_len") 项。
- #strong[尹浩铭]：收紧异常日志文案；**开始** 11.4 **探索一**（CRC 漏检量级或小程序提纲），**不**与第 3 天的探索二混写。
- #strong[林旭东]：与张核对 11.3 理论表（$W$、$t_"tx"$ 口径）；表 3 五行在 #raw("docs/实验报告.typ") 中填齐命令与利用率。

#strong[当日交付物：]GBN + 捎带 ACK 可长时间运行；表 3 #strong[五行]均有真实命令、时长与利用率；报告 11.3 表格非空。

#pagebreak()

= 第 3 天：压测、报告与合并

== 上午

- #strong[林旭东]：场景 5 / #raw("--flood -b 1e-4") 长测 $>= 20$ min；备份日志并截取附录用时间线（**本时段不做** #raw("typst compile")，避免与下午统稿重复）。
- #strong[张恒基]：根据长测日志做小步修复；补齐 11.3 有误码「雪崩」叙述与表 3 数字对照段落。
- #strong[尹浩铭]：根据第 2 天下午笔记，撰写 11.4 **探索二**（#raw("start_timer") vs #raw("start_ack_timer")）正文初稿；走查定时器相关调用是否与 #raw("protocol.c") 语义一致。

== 下午

- #strong[全员（1 h）]：对照 #raw("docs/实验要求对照检查清单.md") 与 #raw("docs/实验报告.typ") 文末检查清单逐项勾选。
- #strong[林旭东]：**仅此一次**执行 #raw("typst compile docs/实验报告.typ")、核对 PDF 表 3 与附录、#raw("main") 合并与 PR。
- #strong[尹浩铭]：全仓走查：魔法数→宏、#raw("struct frame") 与报告 11.2（1）表一致；审阅 PDF 中 CRC/探索章节表述。
- #strong[张恒基]：11.2（3）流程图行号终稿；11.5 心得替换为真实案例。

#strong[当日交付物：]#raw("main") 合并完成 + #raw("docs/实验报告.pdf")（及院系要求的纸质/电子版）+ 检查清单可勾为「已完成」状态。

#pagebreak()

= 文档轮值（对齐 #raw("docs/实验报告.typ") 章节）

#align(center)[
  #table(
    columns: (1fr, 2.2fr),
    align: left,
    stroke: 0.45pt + gray,
    [*轮值*], [*建议负责段落*],
    [第 1 天末], [林旭东：11.1 环境、命令、#raw("git") 短哈希；尹浩铭：11.2（1）数据结构表；张恒基：11.2（2）（3）提纲与异常路径要点],
    [第 2 天末], [张恒基：11.3 参数推导与窗口公式；尹浩铭：11.4 **仅探索一**（CRC）；林旭东：11.3 表 3 与理论对比表 + 过程记录 7.3–7.4],
    [第 3 天末], [尹浩铭：11.4 探索二（定时器）；张恒基：11.5 复盘与心得；林旭东：11.6、附录日志、全文 #raw("typst") 编译与检查清单],
  ),
]

= 风险与对策

- #strong[合并冲突频繁：]第 1 天末约定公共结构体字段不再改名；大改先 Issue 通知。
- #strong[定时器与物理层就绪理解偏差：]先读上文「#strong[库接口语义备忘]」再改代码；并对照 #raw("src/protocol.c") 中 #raw("start_timer")、#raw("start_ack_timer")、#raw("PHL_SQ_LEVEL")；PR 描述写清验证步骤。
- #strong[报告与代码不一致：]表 3 旁备注运行时间、命令行与 #raw("git rev-parse --short HEAD")；报告中的宏名与 #raw("datalink.c") 完全一致。
- #strong[两份 Typst 报告分叉：]若同时使用 #raw("report.typ") 与 #raw("docs/实验报告.typ")，指定一人每次合并后同步关键表格与探索题段落。

// 编译：在仓库根目录执行
// typst compile docs/三天三人方案.typ
