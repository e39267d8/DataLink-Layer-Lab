# 用 Typst 写实验报告

主文件：

- **根目录 [`../report.typ`](../report.typ)**：小组版式（封面成员名、表 3 等），推荐日常编译。
- **[`实验报告.typ`](./实验报告.typ)**：与指导书第 11 节对齐的另一套模板，可选。

## 安装 Typst

- 官网：<https://typst.app/>  
- Windows：可用 `winget install --id Typst.Typst`，或从 GitHub Release 下载 `typst.exe` 并加入 `PATH`。

## 编译与预览

在**仓库根目录**执行。

**小组主报告（推荐）：**

```bash
typst compile report.typ
```

生成 **`report.pdf`**（与 `report.typ` 同目录；已加入 `.gitignore`，勿误提交）。

```bash
typst watch report.typ
```

**另一模板：**

```bash
typst compile docs/实验报告.typ
```

默认生成 **`docs/实验报告.pdf`**。

指定输出文件名示例：

```bash
typst compile report.typ build/实验一-小组名.pdf
```

## 中文字体

`实验报告.typ` 内默认字体栈包含 **SimSun / SimHei**（常见于 Windows）。若编译警告缺字，请把文件开头的 `#set text(font: (...))` 改为本机已装字体，例如：

```typst
#set text(font: ("Times New Roman", "Microsoft YaHei", "SimSun"))
```

## 与 Markdown 提纲的关系

- [`实验报告-提纲.md`](./实验报告-提纲.md)：纯文本提纲，可快速改结构。  
- **`实验报告.typ`**：正式排版、目录、表格；**以 Typst 为提交源**时，以 `.typ` 为准，Markdown 可作备忘。

若课程**强制要求 Word**：可从 PDF 再转 Word（版式可能需微调），或在 Word 中仅贴正文、版式用手调。
