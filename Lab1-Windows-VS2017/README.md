# Lab1-Windows-VS2017（仅教师参考与 VS 工程）

本目录**不包含**组内实现的链路层源码，也**不参与**日常修改。

| 内容 | 说明 |
|------|------|
| `datalink.sln` / `datalink.vcxproj` | Visual Studio 工程；编译 `..\src\`、`..\include\` |
| `Example/` | 教师提供的参考可执行文件与样例日志（stopwait / gobackn / selective） |
| `reference/` | 教师下发的空模板等只读参考（若有） |

**组内开发**请只改仓库根目录：

- `src/datalink.c`、`src/datalink_recv.c`
- `include/datalink.h`

编译输出统一在根目录 **`build/`**（`datalink.exe`、中间 `.obj` 等）。
