# 网页幻灯片写法与导出

本文件定页面的写法和导出约束，构图按 `design-principles.md`。写页的先后由调用本引擎的流程技能决定。
流程：用 `components.js` 写 `build.js` 生成 HTML 幻灯片，网页预览，自动检查，导出可编辑 PPTX。

## 一、目录结构

```
<工作目录>/
  build.js            生成脚本
  deck/
    deck.json         {"order": ["p01", "p02", ...]}，页序
    slides/p01.html   每页一个文件
    img/              截图、照片，用相对路径引用
```

## 二、页面写法

每页是一个 `<section>`，画布 1920 × 1080 像素。页内元素全部绝对定位，坐标写在 `style` 里，单位 px。
页面由 `components.js` 生成，下例只说明生成结果的样子。

```html
<section style="background:#FFFFFF">
  <p style="left:96px;top:70px;width:1200px;font-size:52px;font-weight:700;color:#1F2633">页标题</p>
  <div style="left:96px;top:220px;width:560px;height:320px;background:#F6F8FB;border:1.8px solid #C9CED6"></div>
  <x-shape kind="ellipse" style="left:700px;top:220px;width:48px;height:48px;background:#336EE8"></x-shape>
  <x-connector x1="656" y1="360" x2="900" y2="360" head="end" style="color:#5B6B82;border-width:2.4px"></x-connector>
  <aside>讲稿：原因、例外、举例和出处。</aside>
</section>
```

### 2.1 元素

| 元素 | 用途 | 导出结果 |
| --- | --- | --- |
| `<p>` | 一段文字；带底色和边框时是带字的方框 | 文本框，可编辑 |
| `<div>` | 不含文字的矩形和圆角矩形；只设 `border-top` 或 `border-left` 时是横线或竖线 | 形状或线条，可编辑 |
| `<x-shape kind>` | `ellipse` `diamond` `rect` `rounded` | 形状，可编辑 |
| `<x-connector>` | 连线。`x1 y1 x2 y2` 是端点；`head` 取 `none` `end` `start` `both`；`route` 取 `hv` `vh` `elbow` 时走直角折线 | 线条，可编辑 |
| `<svg>` | 图标、叠板和 PPT 形状画不出的曲线 | 图片 |
| `<img>` | 截图、照片 | 图片 |
| `<aside>` | 讲稿 | PPT 备注 |

`<p>` 里可以用 `<br>` 换行，用 `<b>` 或 `<span style="color:…;font-weight:…">` 改局部格式。

### 2.2 可用样式

- 位置与尺寸：`left` `top` `width` `height`，单位 px。
- 文字：`font-size` `font-weight` `color` `line-height` `text-align` `white-space:nowrap` `padding`。`font-family` 含 `monospace` 时按代码导出，字体取 `font.family.code` 的第一项。
- 填充与边框：`background`、`border:Npx solid|dashed 颜色`、`border-radius`、`border-top`、`border-left`。
- 颜色写 `#RRGGBB` 或 `rgb()`。
- 连线：`color`、`border-width`、`border-style:dashed`。

### 2.3 导出不支持的写法

导出程序在浏览器里排版后读取每个元素的位置和计算样式。下列效果 PPT 形状表达不了，`check_slides.js` 报 ERROR：

- 渐变、阴影、文字阴影、`opacity`、`filter`、`transform`、背景图。
- 没有绝对定位的元素，例如 flex、grid 和相对定位。
- `<div>` 里放文字；`<p>` 里放 `<svg>` 或 `<img>`。
- 2.1 表以外的标签。

半透明颜色按页面底色混成实色导出，报 WARNING。`<p>` 里 `b strong span br i em` 以外的行内标签按普通文字导出，报 WARNING。

### 2.4 字体

预览用 tokens.json 的 `font.family.ui`，只列本机字体，不从网络加载。导出到 PPT 写 `font.family.file`，即微软雅黑。
数字和编号与正文同一字体。不同机器的字宽略有差别，单行文字占满文字框宽度 95% 以上时报 WARNING。

### 2.5 可编辑性

文字、方框和连线写成可编辑元素。图标、叠板和曲线用 `<svg>`，导出为图片。
一页里 `<svg>` 占主图面积一半以上时，在讲稿里注明「本页主图为图片」。

## 三、组件

页面用 `assets/html2pptx/components.js` 拼。常量由 `assets/html2pptx/tokens.js` 从插件根的 tokens.json 换算，键名见 `style-tokens.md`，元素的含义见 `style-elements.md`。

| 类别 | 函数和常量 |
| --- | --- |
| 常量 | `C` 颜色、`FS` 字号、`LW` 线宽、`RAD` 圆角、`MARGIN` 左边距、`RIGHT` 右边线、`MAIN` 主图区上下界、`FRAME` 页面框架、`CANVAS` 画布 |
| 基础 | `text` 单行文字、`para` 段落、`box` 方框、`line` 连线、`arrow` 箭头、`circle` 圆、`diamond` 菱形、`chip` 胶囊、`labelValue` 标签与值、`attrBand` 属性带、`legend` 图例 |
| 编号与标记 | `balloon` `stepNo` `noteNo` `node` `crossMark` `dimLine` `reviewPoint` `leader` `bigNumber` `plate` `frame` |
| 图表 | `bars` 条形图、`lineChart` 折线图、`slope` 坡度图、`gantt` 甘特条 |
| 图标 | `icon` 图标、`iconCircle` 圆底图标、`ICON_NAMES` 可用名称 |
| 页面 | `page` 正文页框架、`slide` 无框架页、`writeDeck` 写出 deck 目录 |
| 工具 | `tw` 估算文字宽度、`esc` 转义 |

每个函数的参数写在 `components.js` 的函数注释里。示例 `assets/html2pptx/demo/build.js` 用五页虚构内容演示了封面、分区图、双泳道、图表和甘特条。

写法：

1. 在工作目录写 `build.js`，开头 `const K = require('<引擎>/assets/html2pptx/components');`。`<引擎>` 是本技能的目录。
2. 每页先画主图，再交给 `K.page()` 加标题、子标题、属性带、页眉和页脚。
3. 最后调用 `K.writeDeck('deck', [{ id: 'p01', html: … }, …])`。

组件没有的元素可以在 `build.js` 里自己画，数值仍取 `C`、`FS`、`LW`，并记下这个元素表达什么。

## 四、命令

脚本在 `<引擎>/assets/html2pptx/`。首次使用时在该目录运行 `npm install`。

```bash
node build.js                                                                   # 生成 deck/
node <引擎>/assets/html2pptx/preview.js deck/ deck/preview.html --title "方案预览"       # 单文件预览页
node <引擎>/assets/html2pptx/check_slides.js deck/ --png deck/png --sheet deck/总览.png  # 自动检查、截图、缩略图总览
node <引擎>/assets/html2pptx/html2pptx.js deck/ 交付.pptx --title "方案" --author "〈我方〉"  # 导出
python3 <引擎>/assets/tools/check_deck_visual.py 交付.pptx --config 项目配置.json      # PPTX 视觉检查
```

- 预览页是单个文件，可以直接发布为 Artifact 给用户看。
- `check_slides.js` 接受 deck 目录或预览页，检查两类问题：
  - 排版和导出：字号过小、文字溢出、超出画布、文字重叠、单行贴边、2.3 节的写法。
  - 设计：文字越出方框、文字压线、对比度不足、箭头没有标签、方框只写一个名称、主图区空白和占用率。
- ERROR 必须改完。WARNING 逐条改，或写明保留的理由。INFO 用来与范例库对比。
- 导出程序与预览页用同一套页面和字体排版，网页上的位置就是 PPT 里的位置。
- `check_deck_visual.py` 读导出的 PPTX，查字号下限、字号层级、强调色、图例和色表。配置示例是 `assets/tools/check_deck_visual.example.json`。
