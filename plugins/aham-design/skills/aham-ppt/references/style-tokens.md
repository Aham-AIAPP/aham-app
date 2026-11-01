# 固定数值

全部文稿类型适用，全册不变。本文件定字号、颜色、线宽、圆角、字体和页面框架。
取值只在 aham-design 插件根目录的 `tokens.json` 定义，组件、预览、检查和导出都经 `assets/html2pptx/tokens.js` 读取。
本文件的表格写明每个常量对应的 tokens.json 键名和当前取值。插件测试 `tests/test_ppt_tokens.py` 检查两处一致。
改取值时先改 tokens.json，再同步本文件。
构图按 `design-principles.md`，元素按 `style-elements.md`。画布 1920 × 1080 像素，1px 等于 0.5pt。

## 一、字号

| 字号 | 常量 | tokens.json | 用途 |
| --- | --- | --- | --- |
| 18px | `FS.body` | `size.ppt.body` | 正文、标注、表格、页眉章名、页脚、图例。全册最小字号 |
| 20px | `FS.name` | `size.ppt.name` | 方框名称、表格行名、属性带的值、图表数值 |
| 22px | `FS.section` | `size.ppt.section` | 分区标题 |
| 26px | `FS.sub` | `size.ppt.sub` | 子标题 |
| 40px | `FS.big` | `size.ppt.big` | 大数字 |
| 52px | `FS.title` | `size.ppt.title` | 页标题 |
| 72px | `FS.cover` | `size.ppt.cover` | 封面标题 |

- 字重只用 400、600、700。600 用于方框名和表格行名，700 用于标题和数值。
- 层级主要靠字重和颜色拉开。18px 正文占全册文字的大部分。

## 二、字体

| 用途 | 常量 | tokens.json |
| --- | --- | --- |
| 导出到 PPT 的字体，中文、西文和数字同一种 | `FONT_FACE` | `font.family.file` |
| 网页预览的字体栈，只列本机字体 | `FONT_STACK` | `font.family.ui` |
| 页面上的代码片段 | `CODE` `CODE_FACE` | `font.family.code` |

- 数字、件号、序号、页码和金额与正文同一字体，不换等宽字体。
- 预览页不从网络加载字体。

## 三、颜色

| 名称 | 常量 | tokens.json | 色值 | 用途 |
| --- | --- | --- | --- | --- |
| 墨一 | `C.ink1` | `color.ppt.ink_1` | `#1F2633` | 标题、方框名、数值；深色封面的底色 |
| 墨二 | `C.ink2` | `color.ppt.ink_2` | `#4A5363` | 正文 |
| 墨三 | `C.ink3` | `color.ppt.ink_3` | `#6B7482` | 标签、章名、页脚、次要说明 |
| 灰蓝 | `C.slate` | `color.ppt.slate` | `#5B6B82` | 结构主线、图框 |
| 弱灰 | `C.mute` | `color.ppt.mute` | `#AEB5C0` | 未选部分、后续接入、对照数据 |
| 线一 | `C.line1` | `color.ppt.line_1` | `#E3E6EB` | 分隔线、表格线、图表网格线 |
| 线二 | `C.line2` | `color.ppt.line_2` | `#C9CED6` | 方框描边、图表的非高亮条 |
| 底一 | `C.bg1` | `color.ppt.bg_1` | `#F6F8FB` | 属性带、分区底色 |
| 底二 | `C.bg2` | `color.ppt.bg_2` | `#EEF1F5` | 次级底色、图标圆底 |
| 白 | `C.white` | `color.ppt.white` | `#FFFFFF` | 页面底色 |

中性色引用 tokens.json 的冷灰阶。墨一、墨二、墨三是 `color.gray.17`、`color.gray.15`、`color.gray.13`。
弱灰、线一、线二是 `color.gray.10`、`color.gray.5`、`color.gray.9`。底一、底二、白是 `color.gray.1`、`color.gray.3`、`color.gray.0`。
灰蓝是 PPT 专用色。

语义色三个，每个配一个同含义的浅底：

| 颜色 | 常量 | tokens.json | 色值 | 浅底 | 含义 |
| --- | --- | --- | --- | --- | --- |
| 蓝 | `C.ai` | `color.ppt.ai` | `#336EE8` | `#EEF2FC` | AI：AI 执行的步骤、AI 组件、AI 场景 |
| 青绿 | `C.svc` | `color.ppt.service` | `#17998A` | `#E1F3F0` | 我方服务：实施服务、驻场团队、我方主导的工作 |
| 橙 | `C.prod` | `color.ppt.product` | `#CE8422` | `#FBF0DF` | 我方产品 |

- 浅底的常量是 `C.aiBg`、`C.svcBg`、`C.prodBg`，键名是 `color.ppt.ai_bg`、`color.ppt.service_bg`、`color.ppt.product_bg`。
- 蓝引用品牌蓝阶 `color.blue.base`，蓝的浅底引用 `color.blue.bg`。
- 汇报类可以给三个语义色另定含义，开工时写进项目色表，全册不变。
- 项目确需第四种语义色时，写进色表并注明含义，再加进图例。
- 不用红色、渐变、半透明和单页独有的颜色。
- 「本期建设」「本客户选用」不用颜色表示。未选部分画成弱灰，或写「后续自选」。
- 弱灰只画图形，不作文字色；弱灰图形旁的文字用墨三。弱灰在白底上的对比度低于 2.5:1。

## 四、线宽

| 线宽 | 常量 | tokens.json | 用途 |
| --- | --- | --- | --- |
| 1.5px | `LW.struct` | `layout.ppt.stroke.struct` | 结构线、表格线、引线、网格线、页脚线 |
| 1.8px | `LW.stroke` | `layout.ppt.stroke.stroke` | 方框描边、胶囊描边、件号气泡、图标 |
| 2.4px | `LW.flow` | `layout.ppt.stroke.flow` | 数据流箭头、选中框、折线 |
| 3.6px | `LW.heavy` | `layout.ppt.stroke.heavy` | 重线：边界、上限、交接 |

- 重线只画边界、上限和交接，一页最多两处。
- 缩略图内部可以用 1px。
- 虚线只表示两种含义：
  - 非本期或未发生：虚线框画后续接入的系统和后续场景，虚线连线画后续才有的数据路径。
  - 边界和参考线：网络边界、评审点竖线、排版参考线。
- 「双方共同」「等待」不用虚线，用浅底加实线描边或弱灰描边。

## 五、圆角与形状

- 方框 6px，卡片 8px，胶囊全圆。图框、标题栏、表格和图表的条用直角。
- 方框和卡片的常量是 `RAD.box`、`RAD.card`，键名是 `layout.ppt.radius.box`、`layout.ppt.radius.card`，分别引用 `radius.control`、`radius.panel`。
- 不用阴影、渐变和透视。
- 等轴测线框叠板可以用：顶面用浅底，侧面用同色系深色。

## 六、页面框架

正文页的框架固定。框架只定页眉和页脚，主图区的划分按本页内容。
数值的键名在 `layout.ppt.frame` 下，常量是 `FRAME`。

| 位置 | 内容 | 数值 | tokens.json |
| --- | --- | --- | --- |
| 左右边距 | — | 96px，右边线 x=1824 | `margin` `right` |
| 页眉左 | 章编号和章名，如「01　建设内容」 | 18px 墨三，top 39 | `header_top` |
| 页眉右 | 页间引用，如「件号 12」「接第 4 页」 | 18px 墨三，右端在 x=1824 | `right` |
| 标题 | 汇报类写结论，方案类写名词短语 | 52px 700 墨一，top 70 | `title_top` |
| 子标题 | 一句话 | 26px 墨二，top 141 | `sub_top` |
| 提供方胶囊 | 本页内容由哪方提供，可空 | 与子标题同一行，靠右 | `provider_top` |
| 主图区 | 主图、图例 | y 195–895 | `main_top` `main_bottom` |
| 属性带 | 主图下方，可换成评审标准框、备注带，或不放 | y 906–990，底一，圆角 6 | `attr_top` `attr_bottom` |
| 页脚线 | — | y 1017，1.5px 线一 | `foot_line` |
| 页脚左 | 只写示意、举例、尚未实施三类标注 | 18px 墨三 | `foot_top` |
| 页脚右 | 页码，与正文同一字体 | 18px 墨三 | `foot_top` |

封面、目录和章节页不用这个框架，字号、颜色和线宽仍按本文件。
