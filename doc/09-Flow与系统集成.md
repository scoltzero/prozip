# 09 · Flow、Finder、Quick Look、Services、Box

## 1. Flow 是什么

Flow 是"**根据当前上下文推荐下一步动作**"的按钮条，不是普通工具栏。它同时承担：

- 主操作（Open File / Extract All / Install Application）
- 上下文推断（选中单个 app → 推荐安装；选中目录 → 推荐解压目录）
- 商业门（Pro 动作带角标，点击走购买/试用）
- 进度与完成回执（同一条位置切换成进度/结果）

核心类型：`FlowActionRouter`、`FlowCompletionPresenter`、`FlowOrbitControl`、`CommercialEffectGateway`。

## 2. Flow 目录（实测标识符，13 个）

| ID | 触发条件 | 动作 | 免费 |
|---|---|---|---|
| `app.arczip.open.file` | 选中普通文件（在白名单内） | 解到临时目录 → 系统默认应用打开 | ❌ Pro |
| `app.arczip.archive.add-files` | 创建态/可编辑包 | 添加文件到包 | ❌ Pro |
| `app.arczip.archive.extract-all` | 任意包 | 全部解压 | ✅ |
| `app.arczip.archive.extract-selection` | 选中多个条目 | 解压所选 | ✅（需索引完成） |
| `app.arczip.archive.extract-directory` | 选中目录 | 解压该目录 | ✅ |
| `app.arczip.install.application` | 选中 `.app`（包内或 DMG） | 安装到 /Applications | ❌ Pro |
| `app.arczip.install.font` | 选中字体文件 | 安装到用户字体库 | ❌ Pro |
| `app.arczip.install.package` | 选中 `.pkg` | 交给系统安装器 | ❌ Pro |
| `app.arczip.open.disk-image-application` | DMG 内选中 app | 打开（含安装指引） | ✅ |
| `app.arczip.disk-image.application.prefers-open` | 同上，开发者偏好直接打开 | 直接打开 | ✅ |
| `app.arczip.open.installed-application` | 刚安装完成的 app | 安装后直接打开 | ✅ |
| `app.arczip.open-file.allowed-extensions` | —— | 白名单策略（非动作） | —— |
| `app.arczip.unavailable` | 上下文不满足 | 显示不可用原因 | —— |

> `[实证]` 13 个 ID 全部来自 `__cstring`；`[实证]` 免费/Pro 归属来自 `commercial.pro.feature_requires_pro` 文案与设置页。

## 3. Flow 决策顺序（推断，但与文案高度一致）

```
1. 有选中吗？没有 → 隐藏/降级为 Extract All
2. 选中是多个？→ extract-selection
3. 选中是目录？→ extract-directory
4. 选中是 .app？
     ├ 在 DMG 里 → open.disk-image-application（或 prefers-open）
     └ 在压缩包里 → install.application
5. 选中是字体 → install.font
6. 选中是 .pkg → install.package
7. 选中是普通文件且扩展名在白名单 → open.file（Pro 门）
8. 兜底 → unavailable（说明原因，如"没有可用应用打开"）
```

商业门的位置：**动作执行前**（`CommercialEffectGateway.decide()`），不是渲染时。所以"按钮可见但点击弹 Pro"是预期行为；原版还给按钮加 Pro 角标。

## 4. 「打开文件」白名单（32 种，实测 `openFile.allowedFormats.v1`）

```
文档  pdf plain-text markdown rtf csv word excel powerpoint epub
图像  jpeg png gif webp heif tiff bmp svg
音频  mp3 m4a ogg-audio wav flac
视频  mp4 m4v mov mkv avi webm
其它  html css json xml yaml
```

（共 32 个逻辑格式；底层映射到 34 个扩展名，`jpeg/jpg`、`tiff/tif`、`heif/heic` 合并显示。）

行为：

- 未在白名单 → 不出现"打开文件"，或提示"系统找不到可以打开 `%@` 的默认应用"。
- 打开流程：解到 `$TMPDIR/arczip-open-<pid>/` → `NSWorkspace.open` → 记录"已打开文件"。
- 文件盒/Flow 设置页可全选/全不选；默认 32/32 全开。

## 5. Finder Sync

菜单（按选中内容动态出现）：

| 菜单项 | 条件 |
|---|---|
| `用 ArcZip 浏览` | 选中 1 个压缩包 |
| `快速解压到当前目录` | 选中压缩包 |
| `快速解压到指定目录…` | 选中压缩包 |
| `压缩为…` | 选中普通文件/文件夹 |
| `压缩为 "<名字>"` | 单个文件夹，直接以其名命名 |
| `将 N 个文件解压到当前目录` | 多选压缩包 |
| `将 N 个文件解压到指定目录…` | 多选压缩包 |

实现要点：

- 扩展是 `com.apple.FinderSync`，principal class `ArcZipFinderSync.FinderSync`。
- 移动存储监听默认**关**：开启会改外接设备图标（macOS 的 Finder 扩展行为），设置页有专门确认弹窗。
- 提供「修复访达菜单项」：清理过期注册、`pluginkit` 重注册、重启 Finder。
  - 错误："未在"应用程序"文件夹中找到当前 ArcZip"、"Untrusted signature"、"Registration incomplete"。
- Finder 请求通过 `arczip://finder-action?...` 或 XPC 转到主 app。

> `[实证]` 菜单文案、扩展 Info.plist、`pluginkit`/`codesign` 字符串。

## 6. Quick Look

- 扩展：`com.apple.quicklook.preview`，`QLIsDataBasedPreview = false`。
- 支持类型：`public.zip-archive`、`org.7-zip.7-zip-archive`、`public.tar-archive`。
- 生成缩略图时**只解少量条目**：有独立预算（"Quick Look 缩略图提取内容超过安全上限"）。
- 不提取符号链接/特殊文件（"Quick Look 不提取链接或特殊文件"）。
- 暂存文件写在 `Temporary/.../QuickLook` 下，系统回收。

> `[实证]` 扩展 plist 与错误文案。

## 7. Services（服务菜单，6 项）

Info.plist `NSServices`，消息 `performArcZipService:userData:error:`，`userData` 区分动作：

| userData | 菜单 |
|---|---|
| `browseArchive` | Browse with ArcZip / 用 ArcZip 浏览 |
| `extractHere` | ArcZip: Quick Extract Here / 快速解压到当前目录 |
| `extractTo` | ArcZip: Quick Extract To… / 快速解压到指定目录… |
| `compressDefault` | ArcZip: Quick Compress (Default Settings) / 快速压缩（使用默认设置） |
| `compressConfigured` | ArcZip: Compress… / 压缩为… |
| `sendToArcZip` | Send to ArcZip / 发送到 ArcZip（进 Box） |

约束：`NSRequiredContext = com.apple.finder`、`NSSendFileTypes = public.item`。

## 8. URL Scheme

```
arczip://finder-action?…      # Finder 扩展 → 主 app
```

- `CFBundleURLTypes` 声明 `arczip`，role `Viewer`。
- 参数包含动作与文件引用（bookmark/路径），主 app 校验来源后执行。
- 未授权/参数无效 → "访达请求文件无效"。

> `[推断]` 查询参数格式未从字符串确认；实现时自定义并在扩展/主 app 间保持一致即可。

## 9. Box（菜单栏暂存架）

| 项 | 行为 |
|---|---|
| 启用 | 显示菜单栏图标，接受拖入 |
| 收集 | 拖文件到图标/弹层；从 Finder 拖入；"发送到 ArcZip" 服务 |
| 持久化 | 条目只在内存；退出即清空（磁盘无暂存目录） |
| 悬停动作 | 放入工作区 / 放入文件夹 / 压缩 / 快速压缩 |
| 保存到… | 把结果保存到用户选择位置；记住上次位置；同名自动编号 |
| 限制 | 保存目标不能在被保存结果内部；不能在 Box 临时目录里 |
| 访问 | 读不到来源文件 → 引导去"隐私与安全性 → 文件与文件夹"授权 |

> `[实证]` 文案与窗口行为；`[推断]` "只在内存"来自 AX/文件系统探测记录。

## 10. 拖放总表

| 来源 → 目标 | 行为 |
|---|---|
| Finder → 窗口 | 加入压缩包 / 新建压缩包 |
| Finder → Dock 图标 | 新建压缩包 |
| Finder → Box | 收集 |
| 列表条目 → Finder | file promise 解包 |
| 条目 → 其他 app | 同上（`NSPasteboard` 文件 promise） |
| 窗口内条目 → 目录行 | 移动到目录（编辑态） |
| DMG 卷内图标拖动 | 只改显示位置（只读卷，不复制） |

## 11. 权限与隐私

- 非沙箱（Developer ID），首次访问桌面/文稿/下载会触发 TCC 提示。
- `NSAppDataUsageDescription` 原文说明"需要读取您拖入的其他应用中的文件，以生成预览、暂存、压缩或解压。这不会更改来源文件。"
- 完全磁盘访问是**可选**的，只为读取微信等来源目录。
- 剪贴板：受 macOS 隐私限制，读 `NSPasteboard.general` 可能为空；不要依赖"从剪贴板拿文件"。
