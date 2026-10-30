# Aham Survey：AhamUI 10.1 原生适配

参考事实源：Aham-AIAPP/aham-ui 10.1.0，main 78bba0c。Swift 原子组件统一引用 DesignTokens.swift。

## 保留的页面结构

答题页保持原三栏：左目录、中间当前题与相邻题预览、右智能提示。答案与顾问记录并排；清除、忽略、转移按钮仍在原位置。既有首页、项目详情与侧栏框架不调整。仅在右栏增加折叠的来源证据/原始转写。

规范用于控件品质和一致性，不要求把网页工作台的布局强加到原生 App。

## 控件与行为

- 主按钮中性色；浅/暗主题均使用 action/on 配对色。disabled 优先于 pressed/hover，文字与底色同时更新。按钮不缩放；默认最小高度32、圆角6。
- Hover 进入立即响应、退出120ms；动作200ms内。键盘触发或系统 Reduce Motion 开启时不执行布局动画。
- 清除显示不可撤销说明，并在确认时核对答案修订号。
- 单选、多选通过 Button 暴露键盘和辅助功能语义；保留原选项文案。
- AI 润色防重复提交，取消请求不能覆盖新题的状态；追问响应检查答案修订号。原有生成结果在下一次请求中继续保留。
- 保存失败的文本保留在 AppStore 的会话草稿中。切题后仍可返回；重试校验原修订号，不覆盖外部更新。草稿不写入正式数据，退出 App 后不保留。
- 导出锁定本次提交的选项和关闭操作，失败保留配置。AI 连接测试锁定配置、取消迟到响应。

## 验证边界

共享 Aham-Validation scheme 使用隔离内存数据库、MCP 凭据与临时描述文件。SettingsManager 在隔离模式下也不加载/保存真实 API 配置。

```sh
xcodebuild -project Aham.xcodeproj -scheme Aham-Validation -destination 'platform=macOS,arch=arm64' CODE_SIGN_IDENTITY=- test
python3 Tests/Integration/storage-migration.py
```

实际 App 中复查题目切换、选项、笔记保留、证据展开、清除确认/并发保护及导出。MCP 完整写入验证仅对隔离库执行，安装后的正式库只读检查。真实第三方 LLM 的输出质量不由本地无凭据回归覆盖。
