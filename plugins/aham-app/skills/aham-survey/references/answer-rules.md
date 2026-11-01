# 答案有效性规则

- `text`：去除首尾空白后非空。
- `number`：文本能解析为数字；不能把“约几十”“很多”伪装成数字。
- `single_choice`：恰好一个 `list_questions` 返回的合法选项。
- `multi_choice`：至少一个合法选项，去重；不能加入自造选项。
- `boolean`：使用服务端接受的布尔值/标准选项。
- `__other__`：只有题库允许且 `otherText` 非空时有效。
- ignored/transferred、note、transcript、evidence 不单独构成有效答案。

映射规则：引用最小客户证据片段；置信度低、互相冲突或无法满足题型的材料进入待确认/笔记。preview 返回任何 issue 时不要 commit，先修正或让用户决定跳过。

