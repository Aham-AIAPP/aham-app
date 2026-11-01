# PPT 通用规范

本文定 Aham 系列 PPT 的通用取值和约束，与具体业务无关。每项写明 `tokens.json` 的键名，取值以 `tokens.json` 为准。
排版引擎是本插件的 `skills/aham-ppt`：组件、预览、导出和检查都从 `tokens.json` 读取，引擎代码里不写色值和字号。
做一整份方案或汇报的流程在 aham-app 插件的 `aham-ppt-proposal` 技能，它调用这个引擎。

## 1. 画布与单位

| 项目 | 取值 | tokens.json 键 |
|---|---|---|
| 画布 | 1920 × 1080 px，16:9 | `layout.ppt.canvas.width`、`layout.ppt.canvas.height` |
| 导出换算 | 2 px 等于 1 磅，144 px 等于 1 英寸 | `layout.ppt.canvas.px_per_pt` |
| 导出的页面尺寸 | 13.333 × 7.5 英寸 | 由前两项算出 |

- 页面里的坐标、字号和线宽都按 px 写，导出时统一折算。
- 页面元素全部绝对定位。导出后文字、方框和连线可编辑，图标和曲线导出为图片。

## 2. 字体

| 用途 | 取值 | tokens.json 键 |
|---|---|---|
| PPT 文件 | 微软雅黑。中文、西文和数字同一种 | `font.family.file` |
| 网页预览 | 本机字体栈，第一项是微软雅黑 | `font.family.ui` |
| 页面上的代码片段 | 等宽字体栈，只用于代码 | `font.family.code` |

- 数字、序号、页码和金额不换等宽字体。
- 预览页不从网络加载字体。预览与导出用同一种字体排版，网页上的换行就是 PPT 里的换行。
- 序号写阿拉伯数字，不用 ①②③；对错写 √ ×。字体缺这些字符时显示方框。

## 3. 字号

全册只用 7 级字号，单位 px。

| 用途 | 取值 | tokens.json 键 |
|---|---|---|
| 正文、标注、表格、页眉、页脚、图例 | 18 | `size.ppt.body` |
| 方框名称、表格行名、图表数值 | 20 | `size.ppt.name` |
| 分区标题 | 22 | `size.ppt.section` |
| 子标题 | 26 | `size.ppt.sub` |
| 大数字 | 40 | `size.ppt.big` |
| 页标题 | 52 | `size.ppt.title` |
| 封面标题 | 72 | `size.ppt.cover` |

- 18 px 是全册最小字号，折合 9 磅。检查脚本以它为下限。
- 字重只用 400、600、700。层级主要靠字重和颜色拉开。

## 4. 颜色

中性色全部引用冷灰阶 `color.gray`，蓝引用品牌蓝阶 `color.blue`。PPT 专用的三种颜色单独定义。

| 名称 | 用途 | tokens.json 键 | 引用 |
|---|---|---|---|
| 墨一 | 标题、方框名、数值；深色封面底 | `color.ppt.ink_1` | `color.gray.17` |
| 墨二 | 正文 | `color.ppt.ink_2` | `color.gray.15` |
| 墨三 | 标签、章名、页脚 | `color.ppt.ink_3` | `color.gray.13` |
| 灰蓝 | 结构主线、图框、箭头 | `color.ppt.slate` | PPT 专用 |
| 弱灰 | 未选部分、后续接入。只画图形 | `color.ppt.mute` | `color.gray.10` |
| 线一 | 分隔线、表格线、网格线 | `color.ppt.line_1` | `color.gray.5` |
| 线二 | 方框描边、非高亮的条 | `color.ppt.line_2` | `color.gray.9` |
| 底一 | 属性带、分区底色 | `color.ppt.bg_1` | `color.gray.1` |
| 底二 | 次级底色、图标圆底 | `color.ppt.bg_2` | `color.gray.3` |
| 白 | 页面底色 | `color.ppt.white` | `color.gray.0` |
| 蓝 | 语义色一，默认含义 AI | `color.ppt.ai`、`color.ppt.ai_bg` | `color.blue.base`、`color.blue.bg` |
| 青绿 | 语义色二，默认含义服务 | `color.ppt.service`、`color.ppt.service_bg` | PPT 专用 |
| 橙 | 语义色三，默认含义产品 | `color.ppt.product`、`color.ppt.product_bg` | PPT 专用 |

- 对比度按 WCAG 2.x 计算。文字色对白底不低于 4.5:1，图形和描边不低于 3:1。
- 墨一、墨二、墨三、灰蓝和蓝可以作文字色。弱灰对白底低于 2.5:1，只画图形，旁边的文字用墨三。
- 青绿对白底 3.52:1，橙对白底 3.02:1，都达到图形的 3:1，不作正文颜色。
- 语义色每种只表示一个含义，全册不变，页面上用图例或提供方胶囊说明。一份文稿可以另定三色的含义。
- 不用红色、渐变、半透明和单页独有的颜色。

## 5. 线宽

| 用途 | 取值 px | tokens.json 键 |
|---|---|---|
| 结构线、表格线、引线、网格线、页脚线 | 1.5 | `layout.ppt.stroke.struct` |
| 方框描边、胶囊描边、编号圆、图标 | 1.8 | `layout.ppt.stroke.stroke` |
| 数据流箭头、选中框、折线 | 2.4 | `layout.ppt.stroke.flow` |
| 重线：边界、上限、交接 | 3.6 | `layout.ppt.stroke.heavy` |

- 重线一页最多两处。
- 虚线只表示「非本期或未发生」和「边界与参考线」两种含义。

## 6. 圆角、阴影和形状

| 项目 | 取值 | tokens.json 键 |
|---|---|---|
| 方框 | 6 px | `layout.ppt.radius.box`，引用 `radius.control` |
| 卡片、分区底 | 8 px | `layout.ppt.radius.card`，引用 `radius.panel` |
| 胶囊 | 全圆 | — |

- 图框、标题栏、表格和图表的条用直角。
- PPT 不用阴影、渐变、透视和半透明。导出程序遇到这些写法报错，因为 PPT 形状表达不了。

## 7. 页面框架

正文页的页眉和页脚位置固定，主图区的划分按本页内容。键名都在 `layout.ppt.frame` 下，单位 px。

| 位置 | 取值 | 键 |
|---|---|---|
| 左右边距 | 96，右边线 x = 1824 | `margin`、`right` |
| 页眉（章名、页间引用） | top 39，18 px 墨三 | `header_top` |
| 页标题 | top 70，52 px 700 墨一 | `title_top` |
| 子标题 | top 141，26 px 墨二 | `sub_top` |
| 提供方胶囊 | top 142，与子标题同一行，靠右 | `provider_top` |
| 主图区 | y 195–895 | `main_top`、`main_bottom` |
| 属性带 | y 906–990，底一，圆角 6 | `attr_top`、`attr_bottom` |
| 页脚线 | y 1017，1.5 px 线一 | `foot_line` |
| 页脚标注和页码 | top 1030，18 px 墨三 | `foot_top` |

封面、目录和章节页不用这个框架，字号、颜色和线宽仍按本文。

## 8. 检查

| 检查 | 位置 | 内容 |
|---|---|---|
| 页面排版 | `skills/aham-ppt/assets/html2pptx/check_slides.js` | 字号下限、文字溢出、超出画布、重叠、导出不支持的写法、文字越框、压线、对比度、空白 |
| PPTX 视觉 | `skills/aham-ppt/assets/tools/check_deck_visual.py` | 字号下限、字号层级、强调色与图例、色表外的颜色 |

- ERROR 必须改完。WARNING 逐条改，或写明保留的理由。
- 文字方面的检查（用词、标题形式、页码引用）属于流程技能，不在本插件。
