# 内容 JSON 格式

`scripts/build_docx.py` 读取一个 JSON 对象，按本文的键生成 Word 文档。内容只写文字和结构，格式由引擎按 `tokens.json` 决定。完整示例见 `examples/demo-content.json`。

## 顶层键

| 键 | 必填 | 说明 |
|---|---|---|
| `meta` | 是 | 文档信息，见下节 |
| `chapters` | 是 | 章节数组，见「章节」 |
| `cover` | 否 | 是否生成封面，缺省为 `true` |
| `toc` | 否 | 是否生成目录，缺省时章节数不少于 4 才生成 |
| `intro` | 否 | 文首提示条：`{"label": "文档用途", "text": "……"}` |
| `closing_note` | 否 | 文末提示条的文字，标签取 `closing_label`，缺省为「说明」 |
| `parties` | 否 | 参与方，最多 4 个，供泳道图和表格圆点使用，见「参与方」 |
| `numeric_facts` | 否 | 数字事实，见「数字事实」 |

## meta

| 键 | 必填 | 说明 |
|---|---|---|
| `title` | 是 | 文档名或文档类型，印在封面、文首和页眉 |
| `date` | 是 | 文档日期，写成 `2026-11-01`。引擎不取运行当天的日期，同一份内容两次生成得到同一份文件 |
| `version` | 否 | 版本号，缺省为 `V1.0`，印在封面和页脚 |
| `project_name` | 否 | 项目名。写了项目名时，封面主标题是项目名，`title` 降为副标题 |
| `customer_name` | 否 | 客户全称。写了时封面印「客户」一行，文首标题上方印客户名 |
| `lede` | 否 | 导语，印在文首标题下方 |
| `key_figures` | 否 | 关键数字，最多 4 个：`[{"label": "……", "value": "……"}]` |
| `cover_fields` | 否 | 封面信息行：`[["标签", "值"], …]`。不写时印客户、项目、版本、日期 |
| `kicker` | 否 | 封面标题上方的一行小字 |
| `show_workflow_status` | 否 | 为 `true` 时在封面、页脚印文档状态，文字取 `status_text`，缺省为「草稿」。只用于内部版 |

## 章节

`chapters` 里每一项是一章：

| 键 | 说明 |
|---|---|
| `title` | 章标题。引擎自动编号 1、2、3，标题已带编号时不重复编号 |
| `number` | 指定编号，覆盖自动编号 |
| `numbered` | 为 `false` 时这一章不编号 |
| `summary` | 章标题下的一行灰色说明 |
| `orientation` | `portrait`（缺省）或 `landscape`。方向变化时引擎新开一节 |
| `page_break_before` | 为 `true` 时这一章从新页开始 |
| `blocks` | 内容块数组 |
| `chapters` | 下级章节，层级最多 3 级 |

## 内容块

每个内容块是一个对象，`type` 决定类型。缺省类型是 `paragraph`。

| type | 键 | 说明 |
|---|---|---|
| `paragraph`（或 `text`） | `text`、`indent`、`bold_prefix` | 正文。`text` 里的换行拆成多段。`indent` 为 `false` 时不缩进首行。`bold_prefix` 是段首要加粗的文字。「★」印成重点色 |
| `subheading` | `title`、`level`、`number` | 章内小标题，`level` 为 2 或 3，编号接在章编号后 |
| `list`（或 `bullets`） | `items`、`ordered`、`start` | 列表。`items` 每项是文字，或 `{"text": "……", "level": 2}`。`ordered` 为 `true` 时编号为「1.」。`start` 用于续号 |
| `callout`（或 `lead`） | `label`、`text`、`tone` | 提示条。`tone` 取 `lead`（缺省，主色）、`key`（规则，重点色）、`risk`（风险，重点色） |
| `quote` | `text`、`speaker`、`timestamp`、`source_id` | 引语。后三项拼成一行出处，印在引语下方居右 |
| `table` | 见「表格」 | 三线表 |
| `figure`（或 `image`、`gallery`、`svg`） | `path`、`paths`、`svg`、`caption`、`source`、`width_cm`、`alt` | 图片。`paths` 写多张时并排。`svg` 写 SVG 路径，`path` 写 PNG 备用图。路径相对内容文件所在目录 |
| `swimlane` | `steps`、`caption`、`note` | 泳道图。每步写 `[执行方, 角色, 操作]`，执行方必须在 `parties` 里登记 |
| `notes` | `title`、`items`、`table_note` | 编号说明条款。紧跟表格时按表注字号排 |
| `page_break` | 无 | 分页 |
| `spacer` | `points` | 空白，单位磅，缺省 6 |

图片找不到时，引擎在原位置印一条「配图状态」提示，文档照常生成。未识别的 `type` 印成一行「［待补充］」提示，业务技能可用 `register_block` 登记新类型。

## 表格

| 键 | 说明 |
|---|---|
| `columns` | 表头文字数组，最多 12 列 |
| `rows` | 行数组，每行是与表头等长的数组 |
| `caption` | 表题，印在表格上方 |
| `widths_cm` | 各列宽度，单位厘米。引擎按版心宽度等比缩放。其他拼写的宽度键直接报错 |
| `alignments` | 各列横向排法，`right` 为靠右 |
| `density` | `regular`（缺省）或 `compact`。`compact` 字号不变，行距和单元格内边距更小 |
| `marks` | 单元格标记，见下表 |
| `note` | 表注，印在表格下方 |
| `layout` | 写 `key_value` 时排成键值表：`rows` 每行是 `[标签, 值]`，不设表头行 |

`marks` 的键：

| 键 | 说明 |
|---|---|
| `level` | 等级列的列名，或 `{"column": 列名, "hot": [取值]}`。`hot` 里的取值印成重点色，缺省为「重点」 |
| `status` | 状态列：`{"column": 列名, "tags": {取值: 标签类型}, "default": 标签类型}`。标签类型有 `solid`、`outline`、`dashed`、`hot` |
| `party` | 参与方列的列名数组，单元格前加参与方圆点 |
| `party_header` | 为 `true` 时表头文字前加参与方圆点 |

表头含「金额」「单价」「总价」「税额」的列自动靠右，并按 `config/layout-rules.json` 的 `amount_unit` 在表头补单位。合计行、分组行和合并单元格不属于通用表格，由业务技能用表格扩展点实现。

## 参与方

```json
"parties": [
  {"name": "示例甲方", "aliases": ["甲方"]},
  {"name": "实施方"},
  {"name": "第三方", "lane": false}
]
```

参与方按顺序取 `role.document.party` 的 `party_1` 至 `party_4` 颜色。`lane` 为 `false` 时，这个参与方在泳道图里不占一条泳道。

## 数字事实

```json
"numeric_facts": [
  {"id": "line_count", "value": 22, "unit": "条", "inline_unit": true}
]
```

正文和表格里写 `{{fact:line_count}}`，生成时换成「22条」。同一个数字只在这里写一次。
