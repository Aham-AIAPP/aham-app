# 本地回归验证

在仓库根目录运行，需 Xcode 和 Node 18+。

```sh
xcodebuild -project Aham.xcodeproj -scheme Aham-Validation -destination 'platform=macOS,arch=arm64' CODE_SIGN_IDENTITY=- test
python3 Tests/Integration/storage-migration.py
```

共享的 Aham-Validation scheme 设置 `AHAM_TEST_IN_MEMORY=1`，测试宿主的数据库、MCP 凭据与连接文件均隔离。不要将 E2E 脚本指向正式应用的连接描述文件。

E2E：以 `AHAM_TEST_IN_MEMORY=1` 启动构建出的 App 可执行文件，标准输出会给出 `AHAM_TEST_CONFIG_PATH`（只有路径，不含 Token）；将此文件传给：

```sh
node Tests/Integration/mcp-e2e.mjs --config <测试连接文件> --adapter <同一构建的Resources/aham-survey-mcp.mjs>
```

测试结束后退出测试进程；临时文件位于应用临时目录。生产应用不需要退出或更换配置。

storage-migration.py 从修复前提交 b7841bd 构造包含项目、答案、备忘、追问和变更集的合成数据库，再用当前模型迁移并重开，检查旧内容及新增证据的持久性；不访问用户数据库。

新写入规则见 docs/WRITE-INTEGRITY.md。
