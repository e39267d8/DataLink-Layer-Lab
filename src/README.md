# 源码目录（`src/` + `include/`）

所有参与编译的 `.c` 均在 `src/`，头文件在 `include/`。**日常只改本目录，不要改 `Lab1-Windows-VS2017/` 下的工程目录。**

| 文件 | 角色 |
|------|------|
| `datalink.c` | **学生**：GBN 主循环与发送侧 |
| `datalink_recv.c` | **学生**：接收、CRC、纯 ACK |
| `protocol.c` | **教师**：仿真物理层/网络层 |
| `lprintf.c` | **教师**：日志 |
| `crc32.c` | **教师**：CRC-32 |
| `getopt.c` | **教师**（Windows 链接；Linux 用系统库） |

编译产物输出到根目录 **`build/`**（`datalink.exe`、`build/obj/*.o`），勿将 `.o` 留在 `src/`。
