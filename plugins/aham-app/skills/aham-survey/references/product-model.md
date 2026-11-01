# 产品与数据模型

Aham Survey 是本地优先的 macOS 结构化现场调研终端，面向 ERP、MES、WMS、PLM、QMS、APS 售前或实施调研。

职责边界：AI 理解意图、整理证据、发现缺口；App 管理项目、题库、答案、状态、进度、校验、审计和导出。AI 不直接访问 SwiftData，App 不把模型推测自动提升为客户事实。

主要对象：

- Project：稳定 UUID、客户资料、行业、范围、已选部门、状态、revision、进度。
- Question：由已安装题库提供的 ID、部门、题型、required、顺序和合法选项。
- Answer：答案文本/选项、其他说明、顾问笔记、原始转写、状态和证据。
- MCPChangeSet：request_id、工具、前后快照、结果和撤销状态。

项目状态：`draft`、`in_progress`、`completed`、`archived`。完成必须通过必答题门；归档默认只读。

revision 在每次项目或答案变更后递增。preview token 绑定项目 UUID、revision 和待写内容；任一变化都会使旧预览失效。

