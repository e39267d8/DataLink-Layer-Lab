# 实验一：数据链路层滑动窗口协议（北邮指导书对齐版）

本仓库实现与文档对齐课程材料：

- 《计算机网络实验一》（北京邮电大学计算机学院，实验指导书 **第 8 节 编程环境**）
- 《讲义 ch3-Lab》PPT（与指导书配套的第三章实验讲义）

## 实验目标（指导书 2、6 节）

在仿真环境下实现**全双工**数据链路层协议：信道模型为 **8000 bps**、**270 ms** 传播时延、默认误码率 **1.0×10⁻⁵**；网络层分组长度固定 **256 字节**（`protocol.h` 中 `PKT_LEN`）。协议类型由组内选择（指导书 6 节）：不搭载 ACK 的 GBN、搭载 ACK 的 GBN、选择重传等，需完成**无误码与有误码**下的正确性，并做**信道利用率**测试与参数优化。

## 文件分工（指导书 8.2 / 8.3 与仓库布局）

| 角色 | 文件 | 说明 |
|------|------|------|
| 学生完成 | `src/datalink.c`、`include/datalink.h` | 链路层状态机与帧格式等自定义数据结构 |
| 教师库 | `src/protocol.c`、`include/protocol.h` | 仿真物理层、网络层、事件与定时器接口 |
| 教师库 | `src/lprintf.c`、`include/lprintf.h` | 带时间戳的日志 |
| 教师库 | `src/crc32.c` | CRC-32（与 IEEE 802.3 相同多项式，指导书 8.9） |
| Windows 工程用 | `src/getopt.c`、`include/getopt.h` | 命令行解析；**Linux  tarball 不含此项**，使用系统 `getopt_long` |

## 三套源码与主开发环境（**本组选用 Windows**）

仓库里对应指导书的三份教师/环境打包，**内容同源、目录不同**，请勿在多处各改一份：

| 目录 | 环境 | 说明 |
|------|------|------|
| **`Lab1-Windows-VS2017/`** | **Visual Studio（推荐）** | 打开 `datalink.sln`：已配置 **`..\include`** 为附加包含目录，**源文件指向仓库根目录 `src\*.c` 与 `include\*.h`**。工具集为 **v143**（VS2022）、Windows SDK **10.0**（本机已装版本）；若你仍用 VS2017，可在项目属性里将平台工具集改回 **v141** 并重定 SDK。日常只改根目录 `include/`、`src/` 即可。 |
| `Lab1-Windows-VS2013/` | Visual Studio 2013 | 旧版工程，可作兼容参考；未改指向根目录源码时与 VS2017 二选一即可。 |
| `Lab1-linux/` | GCC + Makefile | 指导书 Linux 包；队友用 WSL/Ubuntu 时可用根目录 `make`。 |

**约定**：链路层与帧头文件以根目录 **`src/datalink.c`**、**`include/datalink.h`** 为准；Windows 下用 VS 编译、两个 `cmd` 窗口分别跑 `datalink.exe`（指导书 8.2）。

### Windows：编译与运行（指导书 8.2）

1. 用 **Visual Studio** 打开 `Lab1-Windows-VS2017\datalink.sln`，选 **Debug | Win32**，生成解决方案。  
2. 可执行文件默认在 `Lab1-Windows-VS2017\Debug\datalink.exe`（以工程输出目录为准）。  
3. 开两个命令行窗口（建议先 `cd` 到含 `datalink.exe` 的目录），例如：

```text
datalink -d3 A
datalink -d3 B
```

站点名 **`A` / `B` 大小写均可**。日志默认可为 `datalink-A.log`、`datalink-B.log`（见指导书 8.2、8.4）。

### Linux / MSYS2（可选，指导书 8.3）

```bash
make
./datalink [选项] a
./datalink [选项] b
```

根目录 `Makefile` 在类 Unix 下生成 `./datalink`；**不含** `getopt.c` 的链接策略与此前说明一致。

## 编程要点速查（与指导书章节对应）

- **8.5** `main` 中必须先调用 `protocol_init(argc, argv)`。
- **8.6** `enable_network_layer` / `disable_network_layer` 与网络层流量控制；仅在 `NETWORK_LAYER_READY` 后调用 `get_packet`。
- **8.7** 事件驱动：`wait_for_event` 返回五类事件；`DATA_TIMEOUT` 时通过 `arg` 取定时器编号。
- **8.8** `send_frame` / `recv_frame`；物理层发送队列低于 **50 字节**时可能产生 `PHYSICAL_LAYER_READY`；未发送过帧时不会再次收到该事件，需自行记录“物理层可发”状态。
- **8.9** 发送前对帧头与载荷计算 CRC，**追加 4 字节**；接收后用 `crc32(buf, len)` 是否为 **0** 判断整帧（含校验域）是否正确。
- **8.10** `start_timer` / `stop_timer`（数据帧）与 `start_ack_timer` / `stop_ack_timer`（搭载 ACK）；指导书 8.10 对 DATA 定时器编号范围与 8.13 错误提示可能不一致，**以当前 `protocol.c` 实现为准**。
- **8.11** `dbg_event`、`dbg_frame`、`dbg_warning` 与 `-d` / `--debug`。

## 目录结构

- `include/`：头文件
- `src/`：源文件
- `Makefile`：Linux / MSYS2 / MinGW 构建
- **`docs/`**：实验文档（**实验过程**、**实验报告提纲**、**要求对照清单**、开发说明）

### 文档与报告（必读索引）

| 内容 | 位置 |
|------|------|
| 文档总索引 | [`docs/README.md`](docs/README.md) |
| 实验过程（按指导书第 7 节写记录） | [`docs/实验过程记录.md`](docs/实验过程记录.md) |
| **实验报告（Typst → PDF）** | 主文件 [`report.typ`](report.typ)；另见 [`docs/实验报告.typ`](docs/实验报告.typ) · [编写说明](docs/Typst编写说明.md) |
| 实验报告（Markdown 提纲，可选） | [`docs/实验报告-提纲.md`](docs/实验报告-提纲.md) |
| 还差什么、实验是否「够交」 | [`docs/实验要求对照检查清单.md`](docs/实验要求对照检查清单.md) |
| 开发与调试说明 | [`docs/开发说明.md`](docs/开发说明.md) |

课程发的 **Word 版封面 / 性能测试记录表**（若你有 `性能测试记录表.docx` 等）仍建议作为**正式提交表格**；本仓库 Markdown 与之**互补**，便于 Git 里协作与版本管理。

## 作者

Designed by Bosprimigenious & Team.
