# data/ 说明

本目录是**分析证据**，用于复核结论，不是发行素材。

| 文件 | 性质 | 能否进开源发行版 |
|---|---|---|
| `localizable.tsv` | 原版 UI 文案全文（1640×3 语） | **不能**。仅作行为对照；开源版必须重写自己的文案 |
| `defaults-keys.tsv` | 键名与语义整理 | 键名本身是实现细节，可参考；建议用自己的命名 |
| `formats.tsv` | 能力矩阵整理 | 可以（事实性数据） |
| `flow-ids.txt` | 原版内部标识符 | 不建议照抄；用你自己的 ID |
| `allowed-open-formats.txt` | 32 种格式白名单 | 可以（格式清单是事实） |
| `entry-index.sql` | 从二进制提取的 schema | 参考结构，SQL 请自己写 |
| `publish-registry.sql` | 同上 | 参考结构，SQL 请自己写 |
| `types-by-module.txt` | 类型清单 | 仅研究 |
| `swift-sources.txt` | 源码文件名清单 | 仅研究 |
| `engine-strings.txt` | 引擎错误原文 | 仅研究；错误文案要重写 |
| `third-party.tsv` | 第三方组件/版本/许可 | 可以（事实性数据） |
| `screenshots/` | 原版界面截图 | **不能**进发行版；仅作布局参考 |

## 使用原则

1. 用这些材料**理解契约**（字段、状态机、排序、边界），不要复制表达（文案、图标、视觉）。
2. 开源版对外文案自己写；错误提示至少换一种说法。
3. 不要打包原版 `7zz`、`Assets.car`、字体、截图。
4. 不要把 `com.maczhang.ArcZip` 的任何标识符用于你的 bundle id / App Group / Keychain group。

详见 [../11-开源实现蓝图.md](../11-开源实现蓝图.md) 第 10 节"清洁室边界"。
