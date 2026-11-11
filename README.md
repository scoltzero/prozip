# ArcZip 行为资料库（用于开源重实现）

> 目标：给"从零写一个完全开源的 ArcZip 等价物"提供**行为参考 + 实现上限**。
> 这里描述的是**可观察行为与内部契约**，不是原版源码，也不含原版资源、证书、私有密钥或安装包。

- 样本版本：**ArcZip 1.2.3 (build 366)**，`com.maczhang.ArcZip`
- 架构：Universal（arm64 + x86_64），arm64 slice `14,898,368` B，SHA-256 `b2dff34b59c099ddc55263d8313a79c6fb7dbd5e94d3cf56af93d0f3fa8aa529`
- 安装包：`ArcZip-1.2.3-366.dmg`，SHA-256 `d194af66932c8fa6bcfa09884e9606a3d81e002c6f8d16e148024f3b6da73fd8`
- 最低系统：macOS 14.0；构建 SDK：macOS 27.0；签名：Developer ID + Hardened Runtime（**未开 App Sandbox**，entitlements 只有 App Group 与 Keychain Group）
- 三语本地化：en / zh-Hans / zh-Hant，`Localizable.strings` 各 **1640** 条
- 技术栈：Swift + SwiftUI（少量 AppKit）；ZIPFoundation 0.9.20、libdeflate 1.26、内置 7-Zip `7zz 26.04`（+ 静态链入的 LZMA2 编码子集）、系统 libarchive、Sparkle 2.9.4

## 怎么用这份资料

| 你想做的事 | 先读 |
|---|---|
| 定产品范围、抄交互骨架 | [01-产品与交互模型](01-产品与交互模型.md) |
| 写"打开压缩包"这条主链路 | [02-浏览与索引](02-浏览与索引.md) |
| 决定用哪个引擎、支持哪些格式 | [03-引擎与格式矩阵](03-引擎与格式矩阵.md) |
| 写压缩/解压功能 | [04-创建压缩包](04-创建压缩包.md)、[05-解压](05-解压.md) |
| 写密码、密码本 | [06-密码与密码本](06-密码与密码本.md) |
| 写编辑保存（最容易翻车） | [07-编辑与保存](07-编辑与保存.md) |
| 写 DMG 浏览、装 App/字体 | [08-磁盘映像与安装](08-磁盘映像与安装.md) |
| 写 Flow、Finder/QL/Services/Box | [09-Flow与系统集成](09-Flow与系统集成.md) |
| 写设置、持久化、试用/授权/更新 | [10-设置-持久化-商业-更新](10-设置-持久化-商业-更新.md) |
| 直接开工 | [11-开源实现蓝图](11-开源实现蓝图.md) → [12-验收测试矩阵](12-验收测试矩阵.md) |
| 复核证据 | [90-证据与方法](90-证据与方法.md) + `data/` |

## 十条最值得先抄的行为

1. **三种窗口形态同源**：Workspace（完整）/ Mini（560×422 浏览态）/ Box（菜单栏暂存架），同一个会话模型，切换时要求"保存或放弃"。
2. **目录索引落盘**：每次打开压缩包在 `~/Library/Caches/com.maczhang.ArcZip/Temporary/Sessions/<pid>-<uuid>/Indexes/index-<uuid>.sqlite` 建索引，UI 只查库，不反复读压缩包。
3. **索引有明确阶段**：`preliminary`（可浏览、可全部解压）→ 索引完成（可搜索/预览/拖出/解压所选）。未完成时相关入口显示"等待文件列表读取完成"。
4. **"进入目录"而不是展开树**：双击目录整体替换列表，行层级恒为 0；这决定了行↔条目映射必须靠"当前目录 + 排序"重建。
5. **排序固定**：目录优先，再 `localizedCaseInsensitiveCompare`（SQL 侧 `is_directory DESC, sort_name COLLATE NOCASE`）。
6. **引擎四层分工**：原生 ZIP writer（ZIPFoundation 容器 + libdeflate 编码 + 结构校验）→ 内置 7zz（7z/rar/宽格式/增量修改）→ 系统 libarchive（大量兼容格式/单文件流）→ `hdiutil`（DMG/ISO），另有独立 Lzip 解析器。
7. **压缩是事务**：输出先在临时区写完、校验 manifest、再原子发布；发布登记表 `archive_publications` 有 `prepared/backingUp/committed/rollingBack/recoveryUncertain` 状态，崩溃后可恢复。
8. **临时文件有登记表**：`temporary_artifacts` 记录 device/inode/birthtime/size + 所有权 token，清理前逐项核对身份，避免误删用户文件。
9. **密码绝不出现在进程参数里**：7zz 用 `-p__ARCZIP_NO_PASSWORD__` 占位，真实密码走安全管道（`writePassword(_:to:)`）。
10. **Pro 门是"效果级"的**：每个动作先过一个商业策略判定（`decide()`），而不是在 UI 里藏按钮；免费版仍保留打开、浏览、预览、完整解压、ZIP+通用+均衡创建。

## 原版已知的"实现上限"（照着做时可以少走弯路）

这些是原版**自己写在错误文案里**的能力边界，说明 1.2.3 并没有做到"全格式全功能"：

| 边界 | 原文 |
|---|---|
| 不写加密 ZIP | "ZIP AES 写入将在授权加密引擎接入后启用；不会回退到泄露命令行密码的实现" |
| 不预览加密 ZIP | "此预览版尚未接入 ZIP AES 解密" |
| 不支持 GBK ZIP 编辑 | "自动识别为 GBK 的 ZIP 暂不支持编辑保存；请先解压后重新创建压缩包" |
| 拼接/分卷 ZIP 不编辑 | "拼接 ZIP 暂不支持编辑保存"、"分卷压缩包暂不支持原位编辑" |
| 单文件流不编辑 | "单文件压缩流不支持归档式编辑" |
| RAR 只读 | 无 RAR 写入器；RAR 只做浏览/解压（含 `.partN.rar` 识别） |
| Lzip 只读 | "Lzip 创建尚未开放" |
| TAR 不能调压缩级别 | "TAR 仅打包，不支持调整压缩强度" |
| 分卷只支持 ZIP/7Z | "仅 ZIP 和 7Z 支持分卷" |
| ISO 能力受限 | "ISO 回退引擎不支持应用程序提取"/"不支持提取"（只能挂载后复制） |
| ZIP 密码只支持 ASCII | "为保证跨平台可解压，创建 ZIP 时密码仅支持 ASCII。中文密码请使用 7Z" |

## 目录结构

```
prozip/
├── README.md
├── 01-产品与交互模型.md
├── 02-浏览与索引.md
├── 03-引擎与格式矩阵.md
├── 04-创建压缩包.md
├── 05-解压.md
├── 06-密码与密码本.md
├── 07-编辑与保存.md
├── 08-磁盘映像与安装.md
├── 09-Flow与系统集成.md
├── 10-设置-持久化-商业-更新.md
├── 11-开源实现蓝图.md
├── 12-验收测试矩阵.md
├── 90-证据与方法.md
└── data/
    ├── localizable.tsv          # 1640 条 × 3 语对照
    ├── defaults-keys.tsv        # 全部 UserDefaults 键
    ├── formats.tsv              # 格式 × 能力矩阵
    ├── flow-ids.txt             # Flow 标识符
    ├── allowed-open-formats.txt # Flow「打开文件」32 种白名单
    ├── entry-index.sql          # 目录索引 schema（从二进制提取）
    ├── publish-registry.sql     # 临时文件/发布事务 schema
    ├── types-by-module.txt      # 类型清单（按模块）
    ├── swift-sources.txt        # 源码文件清单（101 个）
    ├── engine-strings.txt       # 引擎错误/边界原文
    ├── third-party.tsv          # 第三方组件/版本/许可
    ├── README.md                # data 目录用途与可再分发性说明
    └── screenshots/             # Mini / Workspace / 设置 4 个面板
```

## 标注约定

- `[实证]`：二进制字符串、plist、SQLite、AX 树、截图、实际运行可直接确认。
- `[推断]`：由类型名、字段名、文案、调用关系推出，未逐条动态验证。
- `[上限]`：原版明确未实现或受限。
- 行内 `0x…` 是 arm64 slice 的文件偏移，便于复核。

## 边界说明

本资料用于**互操作与重实现**：描述文件格式、交互契约、错误语义和数据结构。开源版请使用自己的代码与素材，不要复用原版的图标、`Assets.car`、本地化文案原文和品牌名。详见 [11-开源实现蓝图](11-开源实现蓝图.md) 的"清洁室"一节。
