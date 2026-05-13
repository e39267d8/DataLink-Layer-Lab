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
    align(right)[*文档版本：*], align(left)[2026-05],
  )
]

#pagebreak()

#outline(title: "目录", depth: 2, indent: 1.5em)

#pagebreak()

= 目标与总原则

本方案将指导书第 7 节（熟悉环境 → 设计 → 编码调试 → 测试 → 报告）压缩为 #strong[3 天、3 人并行]，在减少阻塞的前提下保证：#strong[帧格式与窗口语义先冻结]、#strong[事件循环单文件主控]、#strong[每日有可演示增量]。

#strong[共同约定：]
- 代码以仓库根目录 #raw("src/datalink.c")、#raw("include/datalink.h") 为唯一主分支；合并前自测 #raw("-d3") 双站能跑满 5 分钟无网络层报错。
- Git：每人独立分支（如 #raw("feat/zhang-gbn-send")），#strong[每日 17:00 前]向 #raw("main") 发 PR 或 rebase 后 fast-forward；冲突由「改动人」负责解决。
- 文档：#raw("report.typ") 由三人轮流补段落（见下文「文档轮值」），避免最后一日集中誊写。

#pagebreak()

= 角色基线（非排他，可互相支援）

#align(center)[
  #table(
    columns: (1.2fr, 1fr, 2.8fr),
    align: (left, center, left),
    stroke: 0.45pt + gray,
    [*成员*], [*主责域*], [*默认产出物*],
    [张恒基], [协议主控 / 状态机], [#raw("datalink.c") 事件循环、窗口边界、#raw("DATA_TIMEOUT") / #raw("ACK_TIMEOUT") 与定时器协同],
    [尹浩铭], [帧与校验 / 内存安全], [#raw("datalink.h") 定稿、组帧拆帧、#raw("crc32") 与长度一致性、#raw("recv_frame") 缓冲区],
    [林旭东], [构建与测试 / 数据], [根目录 #raw("Makefile") / VS 工程验证、表 3 场景脚本化、日志归档与 #raw("report.typ") 数据表],
  )
]

= 三天日程总览

#align(center)[
  #table(
    columns: (0.9fr, 1.1fr, 1fr, 1fr, 1fr),
    align: center,
    stroke: 0.45pt + gray,
    table.header(
      [*天*], [*阶段目标*], [*张恒基*], [*尹浩铭*], [*林旭东*],
    ),
    [第 1 天], [冻结设计 + 跑通最小路径], [事件骨架 + #raw("NETWORK") / #raw("PHYSICAL") 分支占位], [帧结构 + #raw("put_frame") 草图 + CRC 边界], [双端编译矩阵 + 基线日志命名],
    [第 2 天], [GBN 发送侧闭环], [发送窗口 + 超时重传 + #raw("enable/disable") 策略], [接收校验 + 捎带 ACK + #raw("ACK_TIMER") 触发纯 ACK], [洪水/无误码表 3 前两档 + 数据回填报告],
    [第 3 天], [压测 + 报告定稿], [边界与死锁复盘 + 代码清理], [与报告一致的参数注释 + 代码走查], [高误码长测 + #raw("report.typ") 定稿 + PR 合并],
  )
]

#pagebreak()

= 第 1 天：设计冻结 + 环境对齐

== 上午（约 4 h）

- #strong[全员（0.5 h）]：对照指导书 8.6–8.10，在白板或文档中统一：序号空间、累积 ACK 语义、#raw("MAX_SEQ") 与窗口宽度关系。
- #strong[张恒基]：在 #raw("datalink.c") 中落地 #raw("protocol_init") → #raw("disable_network_layer") → #raw("for (;;)") 骨架；各 #raw("case") 内先用 #raw("dbg_event") 打桩，保证双站能启动并写日志。
- #strong[尹浩铭]：冻结 #raw("struct frame") 字段顺序与「CRC 四字节附加」写法；写出 #raw("put_frame") / #raw("send_data") 空实现或伪实现接口，供张接入。
- #strong[林旭东]：Windows #raw("Lab1-Windows-VS2017") 与 Linux #raw("make") 各编一次；记录可执行路径与默认日志文件名，写入 #raw("docs/开发说明.md") 或个人笔记。

== 下午（约 4 h）

- #strong[张恒基]：实现「停等级」最小闭环：单未确认帧时 #raw("NETWORK_LAYER_READY") → 组帧发送 → #raw("FRAME_RECEIVED") 收 ACK 后释放窗口（为第 2 天扩展为 GBN 留接口）。
- #strong[尹浩铭]：与张结对联调 #raw("crc32") 长度；排查首版段错误（对齐、#raw("recv_frame") 缓冲长度）。
- #strong[林旭东]：整理 Git 分支策略；为表 3 建立 #raw("scripts/") 或 Markdown 命令清单（可选），便于第 2–3 天复制粘贴跑数。

#strong[当日交付物：]可运行的「最小双工」+ 冻结的 #raw("datalink.h") + 更新后的分支与 README 片段（可选）。

#pagebreak()

= 第 2 天：GBN 主体与捎带 ACK

== 上午

- #strong[张恒基]：扩展为 GBN：#raw("next_frame_to_send")、#raw("ack_expected")、流水线发送；#raw("DATA_TIMEOUT") 从 #raw("ack_expected") 起重传窗口内帧并#strong[重启定时器]（避免静默死锁）。
- #strong[尹浩铭]：接收侧按序交付 #raw("put_packet")；解析对端捎带 #raw("ack") 滑动发送窗口；实现纯 ACK 控制帧路径（#raw("ACK_TIMEOUT")）。
- #strong[林旭东]：跑表 3 中「无误码」「默认业务」两档，各 ≥15 min；截取 #raw("lprintf") 利用率行粘贴到草稿表。

== 下午

- #strong[三人联调（1 h）]：双端 #raw("--flood --utopia") 与 #raw("--flood")，观察是否出现网络层坏分组或利用率断崖。
- #strong[张恒基]：修正流量控制：循环末尾 #raw("enable/disable_network_layer") 与物理层就绪标志（指导书 8.8）。
- #strong[尹浩铭]：加固异常路径：CRC 失败、重复帧、失序帧（GBN 丢弃策略）日志可读。
- #strong[林旭东]：将实测数据同步到 #raw("report.typ") 表格；标记与理论值的差距待写分析段。

#strong[当日交付物：]GBN + 捎带 ACK 可长时间运行；表 3 至少完成 4 行数据。

#pagebreak()

= 第 3 天：压测、报告与合并

== 上午

- #strong[林旭东]：#raw("--flood -b 1e-4") 长测（目标 ≥20 min）；备份 #raw("datalink-A.log") / #raw("datalink-B.log")。
- #strong[张恒基]：针对长测暴露的竞态与边界做小步修补；控制单次 PR 体量，便于审查。
- #strong[尹浩铭]：代码走查：魔法数改为宏、注释与 #raw("report.typ") 中参数叙述对齐。

== 下午

- #strong[全员（1 h）]：对照 #raw("docs/实验要求对照检查清单.md") 逐项勾选；补拍关键日志进报告附录。
- #strong[林旭东]：#raw("typst compile report.typ") 出 PDF；检查封面成员与日期。
- #strong[尹浩铭]：完善「研究与探索」段（CRC 与定时器设计二选一深挖）。
- #strong[张恒基]：完善「理论推导与利用率」段，与表 3 数字互证。

#strong[当日交付物：]#raw("main") 合并完成 + #raw("report.pdf") + 可选答辩用一页流程图。

#pagebreak()

= 文档轮值（减轻最后一日压力）

#align(center)[
  #table(
    columns: (1fr, 2.2fr),
    align: left,
    stroke: 0.45pt + gray,
    [*轮值*], [*建议负责段落*],
    [第 1 天末], [林旭东：11.1 环境与命令；尹浩铭：11.2（1）数据结构；张恒基：11.2（3）流程提纲],
    [第 2 天末], [张恒基：11.2（2）模块；尹浩铭：研究与探索（CRC）；林旭东：11.3 表 3 初稿],
    [第 3 天末], [全员：11.5 心得；林旭东统稿 #raw("report.typ") 并编译],
  )
]

= 风险与对策

- #strong[合并冲突频繁：]第 1 天末约定公共结构体字段不再改名；大改先 Issue 通知。
- #strong[定时器与物理层就绪理解偏差：]固定引用指导书 8.8、8.10，并在 PR 描述里写「如何验证」。
- #strong[报告与代码不一致：]表 3 数字旁备注运行时间与 Git commit hash（短哈希即可）。

// 编译：在仓库根目录执行
// typst compile docs/三天三人方案.typ
