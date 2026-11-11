# ProZip 第一次收尾交接

更新：2026-11-11。**本次为阶段收尾，整体像素级复刻与全量实机验收仍未完成。** 本文件是当前接手入口；旧 doc/13、15、16 中的尺寸、测试数量和“全部完成”勾选属于历史，不作为当前结论。

## 1. 项目、决定与当前产物

- 工程：`/Users/luochuhan/repo/prozip`，Swift Package，SwiftUI + AppKit；本目录没有 Git 仓库，本轮没有 commit、push 或发布。
- 对照目标：正常未重签的 ArcZip 1.2.3（366）。保留 ProZip 黄绿品牌及 P 图标。
- **用户已确认：Pro 密码本、音视频悬浮预览按当前本地实现继续。** 使用本地加密密码本/Keychain 与 AVKit，不再等待正常 Pro 授权；不要重复询问这一决定。
- 构建：`bash scripts/build_app.sh debug`；测试：`swift test`。产物：`/Users/luochuhan/repo/prozip/build/ProZip.app`，当前版本 1.0.0。
- 打包含实体 7zz/7z.so、相应许可、FinderSync 与 Quick Look 两个 appex。先签嵌套代码，再签宿主，最后 strict verify；宿主没有用 `--deep` 重签覆盖扩展权限。
- 本地 ad-hoc 签名通过不等于正式签名、公证、扩展已被系统加载或已具备发行资格。

## 2. 验证基线

| 范围 | 结果及证据 |
|---|---|
| 主程序测试 | 258 项通过 |
| Quick Look 独立测试 | 11 项通过 |
| Finder 扩展独立测试 | 7 项通过 |
| 总计 | **276 项通过，0 失败**；`.qa/test.log`。三个 XCTest target 的数量相加，不能只看日志末尾的 7 项 |
| 构建与签名 | `.qa/build.log`；`codesign --verify --deep --strict build/ProZip.app` |
| 入口/队列回归 | `ExternalActionLifecycleTests.swift` 7 项；`.qa/closing-regression-tests.log`、`.qa/final-lifecycle-tests.log` |
| 打包汇总 | `.qa/first-close-validation.json`，含测试分项、主可执行文件 SHA-256、两个扩展实际 entitlements |
| GUI 证据 | `doc/evidence/2026-11-11/prozip-first-close-*.jpg`，均由 Computer Use 获取 |

最后的外部解压会话索引回填已纳入上述完整276项测试并通过，随后重新构建与strict签名验证成功；`.qa/test.log`、`.qa/build.log`和验证汇总均为本次收尾后的结果。

本轮实机确认：新工作区 900×600；首次创建即有 `Workspace.<UUID>` AX 标识；辅助项目按钮显示正确计数并实际切换行；普通文件备选 Flow 能展开/收起；Mini 560×422 与工作区 900×600 往返后保留选择。原版新窗口、Mini 切回、原生放大后经 Mini 切回均观察到 900×600。

**重要边界：276 项自动化测试不等于 276 个界面功能全部通过原版逐像素对照。** 新增业务队列、系统扩展和硬件能力的完整 GUI/OS 验收仍在下表中。

## 3. 已完成的实现与修复

### 3.1 窗口、浏览与界面

- 独立欢迎窗，每个归档 session 有自己的 Workspace/Mini；key/main 更新活动 session，关闭后按最近使用恢复。
- 创建、密码、保存、重名冲突及解压完成提示分别排队；冻结所属窗口。真实保存成功后才关闭，保存失败保留草稿；取消创建/密码会取消待退出。
- 重名动作等旧 sheet 真正关闭后才继续，避免后一个弹窗覆盖前一个 continuation；关闭所属会话会取消尚未执行的替换，即使已进入 dismissing。
- 单一 WindowAccessor，不再三次延时强制尺寸；仅在值变化时更新 style/title/level/identifier。
- 目前工作区初始/从 Mini 恢复 900×600，代码最小值 880×600；检查器固定270pt。880×600 是现有代码约束，尚未证明与原版最小值完全相同。
- Mini 固定560×422；欢迎页560×390；设置初始900×712；创建面板900×600；进度面板380×260。
- 真正的列表、144×150pt图标格和保留祖先列的分栏；键盘、Command/Shift 选择、真实缩略图、目录导航、搜索及右侧检查器接真实数据。
- 普通目录取消1000项无声截断；排序/日期格式器缓存；表格底部72pt留白；标题不再提前截断。
- 重命名同步选择ID、范围锚点、当前路径和历史，undo/redo/discard同步；成功保存与显式放弃分开处理。
- 辅助项目偏好真正影响查询、搜索及草稿；隐藏时清理不可见选择。新增“已隐藏/已显示 N 项”快捷按钮，按当前目录计数，草稿删除/撤销会更新。
- 检查器读取真实文本、图像和缩略图，目录统计包含隐藏项；显示时忽略文本最后一个EOF换行，避免多一行空白。
- 工具栏只切当前窗口的视图模式；设置默认视图才影响新窗口。应用内打开与系统/Finder打开的 Mini 偏好分开处理。
- 普通文件备选 Flow 已按原版增加上方“解压”，复用已有 Orbit 控件，实机展开/收起通过。

### 3.2 创建、编辑、解压与数据完整性

- ZIP/7z/libarchive 真实创建、索引、解压、成员读取与编辑保存；RAR等只读能力按引擎矩阵处理，不能把所有关联后缀当成已验证可读写格式。
- 合并已有目录、保留用户文件；父路径symlink检查、原子发布、单文件不误剥根。编辑保留目录子树、权限与链接。
- 同名目录 add 按成员合并，replace 才整树替换；来源追踪避免把仅部分保留、被覆盖或包含输出的来源误移入废纸篓。
- 未保存草稿禁止从磁盘旧版本解压；所选项目缺失明确报错，不再以空结果假成功。预览/导出能逆向解析未保存的改名路径。
- 7-Zip密码协议已用真实工具修正：无密码创建不传dummy密码；有密码通过stdin完成输入/确认，不放进进程参数。覆盖body/header加密、编辑新增、错误/混合密码拒绝发布、CR/LF/NUL拒绝等。
- 加密payload编辑的整包完整性校验在mutation循环外，源/结果各最多一次。
- 分卷按完整族检查冲突，安全Keep Both、独占发布及按身份回滚；任务、草稿和回调绑定真实首卷`.001`。
- 按份数先生成完整私有归档再流式均分，严格2–999份；按大小限制每卷上界及总卷数，统一64KiB切片。
- **外部解压入口已收口**：自定义URL、Services、普通导入/剪贴板路径都经过本地文件URL及数量/编码上限验证。拒绝remote host、凭据、query/fragment、NUL、非法动作及重复参数；合法文件名里的字面`%00`保留。
- Finder解压先复用同路径已有会话，无法绕过其未保存检查；新归档注册自己的会话，密码/冲突/完成问题不借用无关窗口。复用本次list结果回填索引，不再额外启动第二次索引操作。
- 解压完成按钮处理当前源包，不再把一次“保留/废纸篓”选择写成全局偏好；批量完成提示排队。
- 源包的inode/mtime/size快照贯穿密码和冲突重试；删除/自动关闭前再次核对，并检查同URL会话的未保存修改。解压后已保存新版本或外部替换时保留新源文件并提示。

### 3.3 成员读取与性能

- Native ZIP 成员改为pull/unfolding、增量inflate/ZipCrypto，每块最多64KiB；完整读取验证长度和CRC。128MiB成员只取4KiB前缀、慢消费者截断、取消等已有回归。
- 7z/libarchive前缀达到请求上界即停止子进程，只落盘所需字节；完整范围保留退出状态和CRC检查。硬预算和真实Task取消不因前缀早停而绕过。
- 内置实体Mach-O引擎及相邻7z.so和三份许可，不依赖外部Homebrew wrapper或symlink；当前测试工具为本机p7zip formula17.06，banner17.05，未升级或做universal发行。

### 3.4 密码本、设置、音视频与文件盒

- 密码本V2：随机AES-256文件密钥，无主密码时密钥存Keychain；主密码PBKDF2-HMAC-SHA256 600,000轮，AAD认证元数据；保守V1迁移/轮换，失败保留旧库，损坏/未知版本不得覆盖为空。
- 快捷解锁显式opt-in，真正取钥并成功解密才解锁；晚到认证结果不能重新打开已锁定或重置的库。测试使用fake钥匙库和临时文件。
- 音视频悬浮预览使用AVKit；本地4秒样本视频已实机播放。原版Pro的外形和全部规则不声称逐项相同。
- 移除原版不存在的设置卡和重复选项；Flow保留原版安装3项及32格式白名单。语言/CPU自定义popover、重启提示；English重启生效及恢复跟随系统已实测。
- 格式关联23组/1228后缀、partial/fully状态、后台批量去重查询、原handler还原和8项fake回归；引导只有明确点击应用所选才写系统。未执行真实默认关联开关或推荐批量变更。
- 文件盒：独立NSPanel、空态、真实缩略图、图钉、闲置关闭、颜色/浓度、四动作弧形展开与hover接力；状态栏右键按原版保留打开/退出。
- 原生文件承诺支持文件/目录/多选；provider真实写入、取消、不覆盖有测试。**Finder作为接收方的实际拖出仍未通过，不能用provider测试替代。**

### 3.5 系统扩展

- FinderSync：`org.prozip.ProZip.FinderSync`，真实动态菜单、选中URL交主App执行；默认监控home，外部本地卷按偏好及mount/unmount更新，无轮询；只读同步一项主App偏好。
- Quick Look：`org.prozip.ProZip.QuickLook`，ZIP/7Z/TAR，与原版三项UTI声明一致。后台系统libarchive，不启动Process/Homebrew；不提取链接或特殊文件。
- 预览预算：最多500项、文件128MiB、源读取64MiB、解码16MiB、单成员8MiB、名称4096字节、协作检查3秒；达到限制明确说明列表可能不完整。不能抢占正在执行的单次libarchive C调用。
- CArchive只vendor Apple官方公开头文件与BSD许可，链接系统库，不包含libarchive实现。
- 两扩展使用SDK `_NSExtensionMain`，分别以`-application-extension`编译、独立只读沙盒签名后嵌入。独立fixture验证过错误host拒绝、版本/资源/入口/entitlements；Quick Look stage失败保留旧扩展。
- **未主动注册、启用或运行两个系统扩展；本地宿主启动和包签不代表扩展OS验收完成。**

## 4. 尚未完整校验：16组

计数口径是以下16个验收组，每组可含多个操作或环境组合；不是“只剩16个按钮”，也不能据此给出完成百分比。

| ID | 待验收组 | 已有证据与剩余工作 |
|---|---|---|
| V01 | 全量像素与动画 | 有关键状态截图和部分hover对照；全部弹簧时序、展开/收起/按压/退出逐帧、深色及不同缩放下的像素差异未全量验收；含下方辅助目录日期差异 |
| V02 | 高级窗口行为 | 900×600与Mini往返已实机通过；绿色全屏当前未观察到生效，Option缩放、原版最小尺寸、跨屏/分辨率/恢复状态未闭环 |
| V03 | Finder双向拖放 | provider回归通过；Finder拖入文件盒、从列表/图标/Mini拖出文件/目录/多选到Finder、取消和冲突的系统接收未通过 |
| V04 | 文件盒完整交互 | 空态、图钉、动作展开有实机证据；文件数胶囊的原版行为及完整接力/闲置/多文件操作组合未全量对照 |
| V05 | FinderSync系统运行 | 7项策略与包签通过；系统启用后动态菜单、六类主App动作、移动卷监控及冷启动实际端到端未验收 |
| V06 | Quick Look系统运行 | 11项真实格式/预算/取消测试和包签通过；宿主展示、沙盒授权、快速切换/取消、打开主App未验收。当前系统只显示通用ZIP预览 |
| V07 | Services/URL真实入口与并发 | 六项声明、codec及业务队列测试通过；OS菜单派发、自定义URI冷启动、多个窗口/任务相互切换的完整GUI流程未验收 |
| V08 | 真实系统格式关联 | 只读状态及fake写入/还原通过；真实设置、推荐七组批量操作、部分失败、恢复原handler未在用户系统执行 |
| V09 | 密码本真实认证 | fake库/算法与并发测试通过；真实Keychain升级、主密码GUI全流程、Touch ID/Apple Watch和稳定签名下的ACL未验收 |
| V10 | 音视频边界 | 单段本地视频实播通过；多格式音频/视频、静音/自动播放/停止、超限、损坏及关闭释放未做全量实机矩阵 |
| V11 | 国际化与所有设置 | 通用页及English重启通过；全部页、动态弹窗、长文本、语言切换后的所有布局未全量验收 |
| V12 | DMG/ISO及安装 | SLA检测/系统挂载交接有证据；加密映像、普通/多卷ISO、app/pkg/font安装/替换、退出卸载及隔离属性流程未完整实机验证 |
| V13 | 罕见原版弹窗与错误 | 正常保存确认等有对照；更新概览唤出失败、索引问题缺样本、应用自定义TCC引导缺样本；并发冲突与最新完成队列尚未逐像素复验 |
| V14 | 格式/异常/崩溃矩阵 | 核心ZIP/7Z及安全用例有回归；所有格式变体、多密码/损坏/不完整分卷/非UTF8组合、真实保存/发布中强杀恢复未全量验收 |
| V15 | 大规模性能与发行环境 | 有增量读取/前缀/预算回归；5GB实测峰值、10万条目搜索、并发大任务、Intel/多系统版本、稳定签名/公证分发尚未验收 |
| V16 | 更新、帮助和商业交付 | 在线更新后端/签名安装闭环未实现；正式帮助/发行地址未确定；原版购买/授权界面是否保留未定。受限密码本/AVKit本地方案已确认，不在此重复提问 |

## 5. 已知差异、限制与未实现

1. **绿色按钮**：已经接`toggleFullScreen`、Option分支接zoom，AX名为“全屏幕”；但本次AX点击及实际鼠标点击后截图仍1800×1200，未观察到全屏生效。原版同入口能进入原生全屏。原因未确认，应先检查目标window/NSApp.keyWindow及borderless/fullScreen条件，不能宣称功能通过。
2. **辅助虚拟目录日期**：开启辅助项目后，ProZip的`__MACOSX`虚拟目录显示当前时间，原版显示“—”。这是实机已观察到的像素/元数据差异，尚未修。
3. **分卷原地替换**：已有分卷族或同名base不能Replace，须Keep Both或新名称。没有跨文件崩溃恢复journal；已明确拒绝，不是假替换成功。
4. **系统集成边界**：未改默认关联，未做扩展启用，未复制到Applications。需要验收时先准备可审查的具体包，再处理必要的系统设置/安装授权。
5. **正式交付缺口**：更新服务未接，当前检查更新明确提示服务尚未提供；帮助地址仍是待确认的项目地址。没有购买、开启原版试用、输入许可证或实现商业授权服务。
6. **当前引擎与平台**：测试使用本机旧p7zip及arm64环境；未把已验证格式子集夸为全部格式、全部平台兼容。
7. **拖放工具边界**：CUA事件曾到beginDraggingSession/pasteboard/outside.copy，但未提交落下；Escape后才结束为operation.none，无writePromise。Finder自身用同工具拖动也未移动，保留`.qa/drag-events.log`，不能据此断言实际产品必然坏或已通过。

## 6. 证据、样本与源码地图

- 正常原版来自`.qa/arczip-original/ArcZip.app`只读挂载；运行会AppTranslocation，已有resigned/unlocked同bundle副本，必须核对实际可执行路径。
- `doc/evidence/2026-11-11/`保存正常原版与ProZip的工作区、Mini、设置、语言、文件盒、Flow、Pro gate、视频和本次收尾图片。此前`doc/evidence/`旧图仅作历史参考。
- `.qa/layout-sample.zip`：Documents/说明.txt、39字节config.json、readme.txt。
- `.qa/aux-sample.zip`：visible.txt、.DS_Store、__MACOSX/._visible.txt。
- `.qa/hover-motion.zip`：4秒无音轨视频；`.qa/drag-probe.zip`为拖放公开文本样本。
- `.qa/finder-isolated-*.log`、`.qa/quicklook-isolated-*.log`保存子任务独立测试和fixture包签记录，避免只依赖`/tmp`日志。
- `.qa/baseline/before-first-close-*`保存改写前HANDOFF/doc17。该目录不是完整源码快照。

| 位置 | 责任 |
|---|---|
| `Sources/ProZipApp/ProZipApp.swift` | 窗口工厂/归属、sheet关闭回调、Services/URL入口、打包后应用入口 |
| `Sources/ProZipUI/AppViewModel.swift` | 会话、创建/保存/解压、密码/冲突/完成队列和任务 |
| `Sources/ProZipCore/ArchiveBrowsingSession.swift`、`EntryIndex.swift` | 索引、草稿覆盖、选择/导航、源版本及辅助计数 |
| `Sources/ProZipUI/WorkspaceWindowView.swift`、`MiniArchiveView.swift` | 工作区/Mini布局、交通灯、三种浏览方式 |
| `Sources/ProZipUI/ArchiveFileDrag.swift`、`MenuBarShelfView.swift` | 文件承诺、命中视图、文件盒与四动作 |
| `Sources/ProZipUI/ArchiveHoverContent.swift`、`WorkspaceFlowButton.swift` | 悬浮预览及Flow控件 |
| `Sources/ProZipCore/PasswordBook.swift`及相关钥匙库文件 | 本地密码本、迁移、认证保护 |
| `Sources/ProZipShared/FinderActionRequest.swift`、`FileAssociations.swift` | 本地URL协议及格式关联模型 |
| `Sources/ProZipFinderSync`、`Sources/ProZipQuickLook`、`Sources/CArchive` | 两个系统扩展及只读C桥接 |
| `scripts/build_app.sh`、`scripts/build_*_extension.sh` | 实体依赖、嵌套签名、stage打包 |
| `Tests/ProZipTests/ExternalActionLifecycleTests.swift` | 本次入口/窗口队列/源文件保全回归 |

## 7. 下次接手与本次停止位置

1. 先看本文件和`.qa/first-close-validation.json`，必要时检查源码/产物mtime与运行进程路径；不要重复已完成的276项测试来代替GUI工作。
2. 首先处理V02绿色按钮，再处理V01辅助目录日期；二者已有可复现样本，不需要先购买Pro。
3. 之后分批做V03拖放、V05/V06系统扩展、V07新队列GUI等，按V01–V16逐项留下证据。只有代码/环境发生实质变化或出现新失败，才扩大回归。
4. 继续保留黄绿品牌，不为原版没有的设置补后端。分卷Replace限制、更新服务和正式签名边界保持明确。
5. 本次CUA最后停在`aux-sample.zip`的Workspace，visible.txt选中、备选Flow收起、辅助项目已恢复关闭；没有未保存的真实用户草稿。
6. GUI核对后的最后业务补丁是“外部解压会话索引回填”，自动化回归覆盖；它的外部入口GUI仍属于V07。屏幕上的旧进程不会自动换成重建后的二进制，下一次业务验证必须退出并启动最终`build/ProZip.app`。

已按caveman保持交流简短，按ponytail做最小完整修改和相连代码审阅，使用Computer Use核对实际界面。`stop that shit`未在技能目录及SKILL.md内容中找到，没有声称调用或自行安装替代。Skill是工作方法，不能代替上述测试和实机证据。
