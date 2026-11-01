"""Aham 文档排版引擎：Word 渲染、整份文档组装、文字规范化和 OOXML 检查。

源码在 aham-design 插件的 skills/aham-word/scripts/aham_doc/。视觉取值读插件根的 tokens.json，
版面规则、写作规则和品牌取值读技能的 config/。

公开接口：下面 __all__ 列出的模块，每个模块里由该模块的 __all__ 列出的函数、类和取值。
调用方只用这些名字；以下划线开头的函数是引擎内部实现。

- blocks           文档块类型登记和校验
- brand            品牌配置：名称、英文品牌名、logo、Word 标记字符样式名
- document         整份 Word 文档的组装和命令行入口
- docx_ooxml       OOXML 属性顺序检查和修正
- docx_typography  文档取值读取和字体槽校验
- docx_widths      表格列宽计算
- notes            说明条款的序号与标签写法
- outline          章节编号和目录条目
- paths            技能目录和 config/ 读取
- text             中文标点、金额和人民币大写
- tokens           tokens.json 的读取、引用解析和文档取值视图
- word             Word 渲染器和扩展点

引擎不导入调用方的脚本。调用方自己的内容块、表格规则、SVG 预处理和 SVG 转 PNG 函数经 word 模块的
扩展点登记（register_block、register_table_hooks、set_svg_styler、set_svg_rasterizer），名称和 logo 经 brand 模块传入。
"""

__all__ = [
    "blocks",
    "brand",
    "document",
    "docx_ooxml",
    "docx_typography",
    "docx_widths",
    "notes",
    "outline",
    "paths",
    "text",
    "tokens",
    "word",
]
