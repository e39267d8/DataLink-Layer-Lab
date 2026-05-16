# 实验一：数据链路层滑动窗口协议（北邮指导书对齐版）

本仓库实现与文档对齐课程材料：

- 《计算机网络实验一》（北京邮电大学计算机学院，实验指导书 **第 8 节 编程环境**）
- 《讲义 ch3-Lab》PPT（与指导书配套的第三章实验讲义）

## 仓库布局（重构后）

```
DataLink-Layer-Lab/
├── src/                    # 全部 .c 源码（学生 + 教师库）
├── include/                # 全部头文件
├── build/                  # 编译输出：datalink.exe、obj/（勿提交产物，见 .gitignore）
├── Makefile                # Linux / MSYS2 / MinGW → build/datalink
├── Lab1-Windows-VS2017/    # 仅 VS 工程 + 教师 Example/reference（不含组内实现副本）
│   ├── datalink.sln
│   ├── Example/            # 教师参考程序（stopwait / gobackn / selective）
│   └── reference/          # 教师空模板等只读参考
└── docs/                   # 实验文档与报告
```

**约定**

- **组内实现**只维护：`src/datalink.c`、`src/datalink_recv.c`、`include/datalink.h`
- **教师库**在 `src/protocol.c` 等（与指导书一致，一般不修改）
- **`Lab1-Windows-VS2017/`** 不再存放与根目录重复的 `.c`/`.h`；打开 sln 编译的仍是 `..\src`、`..\include`

## 实验目标（指导书 2、6 节）

在仿真环境下实现**全双工**数据链路层协议：信道 **8000 bps**、**270 ms** 传播时延、默认误码率 **1.0×10⁻⁵**；分组 **256 字节**（`PKT_LEN`）。需完成无误码/有误码正确性、信道利用率测试与参数优化。

## 编译与运行

### Windows（Visual Studio，推荐）

1. 打开 `Lab1-Windows-VS2017\datalink.sln`，**Debug | Win32**，生成。
2. 可执行文件：`build\datalink.exe`
3. 两个命令行窗口：

```text
cd build
datalink -d3 A
datalink -d3 B
```

### Linux / MSYS2

```bash
make
./build/datalink -d3 a
./build/datalink -d3 b
```

## 文件分工

| 角色 | 路径 |
|------|------|
| 学生 | `src/datalink.c`、`src/datalink_recv.c`、`include/datalink.h` |
| 教师库 | `src/protocol.c`、`src/lprintf.c`、`src/crc32.c`、`src/getopt.c`（Windows）及对应 `include/*.h` |

## 文档索引

| 内容 | 位置 |
|------|------|
| 文档总索引 | [`docs/README.md`](docs/README.md) |
| 开发说明 | [`docs/开发说明.md`](docs/开发说明.md) |
| 实验过程 | [`docs/实验过程记录.md`](docs/实验过程记录.md) |
| 主报告 Typst | [`docs/report.typ`](docs/report.typ) |
| 要求对照 | [`docs/实验要求对照检查清单.md`](docs/实验要求对照检查清单.md) |

## 作者

Designed by Bosprimigenious & Team.
