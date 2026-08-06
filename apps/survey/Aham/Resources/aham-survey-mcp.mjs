#!/usr/bin/env node
/**
 * Aham Survey · MCP stdio 适配器
 *
 * Claude Code 与 Codex 都以 stdio 接入 MCP，本文件把 stdio 上的 JSON-RPC
 * 转成对 Aham Survey.app 本地 HTTP 端点的调用：
 *
 *     客户端 ──stdio(JSON-RPC)──▶ 本适配器 ──POST /rpc──▶ App(127.0.0.1)
 *
 * 用法：
 *     node aham-survey-mcp.mjs --port 51823 --token <token>
 *
 * 零依赖，Node 18+。App 必须处于运行状态，否则工具调用会返回连接失败。
 */

const args = process.argv.slice(2);
function flag(name, fallback) {
  const i = args.indexOf(`--${name}`);
  return i >= 0 && args[i + 1] ? args[i + 1] : fallback;
}

const PORT = flag("port", process.env.AHAM_MCP_PORT);
const TOKEN = flag("token", process.env.AHAM_MCP_TOKEN);

if (!PORT || !TOKEN) {
  process.stderr.write(
    "缺少参数：--port 与 --token。可在 Aham Survey 首页「复制配置」获取。\n"
  );
  process.exit(2);
}

const ENDPOINT = `http://127.0.0.1:${PORT}/rpc`;

/** 工具清单 —— 与 App 内 MCPTools.catalog 对应 */
const TOOLS = [
  {
    name: "list_projects",
    description: "列出全部调研项目与完成进度。",
    inputSchema: { type: "object", properties: {} },
  },
  {
    name: "get_project",
    description:
      "读取单个项目的客户信息、部门、调研范围与现场备忘。project 可传 UUID 或客户名。",
    inputSchema: {
      type: "object",
      properties: { project: { type: "string" } },
      required: ["project"],
    },
  },
  {
    name: "list_questions",
    description:
      "读取某部门的题目、当前答案与触发规则。写答案前先用它拿到 question id。",
    inputSchema: {
      type: "object",
      properties: {
        project: { type: "string" },
        department: { type: "string", description: "部门 id，如 procurement" },
      },
      required: ["project", "department"],
    },
  },
  {
    name: "export_report",
    description: "生成调研报告 Markdown 文本。",
    inputSchema: {
      type: "object",
      properties: {
        project: { type: "string" },
        departments: { type: "array", items: { type: "string" } },
      },
      required: ["project"],
    },
  },
  {
    name: "create_project",
    description:
      "新建调研项目。App 内已无新建入口，这是创建项目的唯一途径。scopes 取值：erp/mes/wms/plm/qms/aps/full；industry 取值：general/automotive/electronics/equipment/food/pharma/materials/textile/metal。",
    inputSchema: {
      type: "object",
      properties: {
        customer: { type: "string" },
        consultant: { type: "string" },
        industry: { type: "string" },
        scopes: { type: "array", items: { type: "string" } },
        departments: { type: "array", items: { type: "string" } },
        companyScale: { type: "string" },
        headcount: { type: "string" },
        revenue: { type: "string" },
        existingSystems: { type: "string" },
        productInfo: { type: "string" },
        surveyGoal: { type: "string" },
      },
      required: ["customer"],
    },
  },
  {
    name: "upsert_answers",
    description:
      "批量写回答案。每条需要 department 与 question（题号来自 list_questions），text / options / note 至少给一个。",
    inputSchema: {
      type: "object",
      properties: {
        project: { type: "string" },
        answers: {
          type: "array",
          items: {
            type: "object",
            properties: {
              department: { type: "string" },
              question: { type: "string" },
              text: { type: "string" },
              options: { type: "array", items: { type: "string" } },
              note: { type: "string" },
            },
            required: ["department", "question"],
          },
        },
      },
      required: ["project", "answers"],
    },
  },
  {
    name: "import_transcript",
    description:
      "把外部转写文本追加到指定题目的转写栏（App 自身不做录音转写）。",
    inputSchema: {
      type: "object",
      properties: {
        project: { type: "string" },
        department: { type: "string" },
        question: { type: "string" },
        text: { type: "string" },
      },
      required: ["project", "department", "question", "text"],
    },
  },
  {
    name: "update_project",
    description:
      "修改客户信息、调研目标或项目状态。fields 可含 consultant / companyScale / headcount / revenue / existingSystems / productInfo / surveyGoal / status（draft·inProgress·completed·archived）。",
    inputSchema: {
      type: "object",
      properties: {
        project: { type: "string" },
        fields: { type: "object" },
      },
      required: ["project", "fields"],
    },
  },
];

async function callApp(tool, toolArgs) {
  let response;
  try {
    response = await fetch(ENDPOINT, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${TOKEN}`,
      },
      body: JSON.stringify({ tool, args: toolArgs ?? {} }),
    });
  } catch (err) {
    throw new Error(
      `连不上 Aham Survey（${ENDPOINT}）。请确认 App 正在运行、且首页显示 MCP 服务已启动。原始错误：${err.message}`
    );
  }
  if (response.status === 401) {
    throw new Error("令牌无效。请在 Aham Survey 首页重新复制配置。");
  }
  const payload = await response.json();
  if (payload.ok === false) throw new Error(payload.error || "调用失败");
  return payload.data;
}

// MARK: - JSON-RPC over stdio

function send(message) {
  process.stdout.write(JSON.stringify(message) + "\n");
}

function reply(id, result) {
  send({ jsonrpc: "2.0", id, result });
}

function replyError(id, message) {
  send({ jsonrpc: "2.0", id, error: { code: -32000, message } });
}

async function handle(request) {
  const { id, method, params } = request;

  switch (method) {
    case "initialize":
      reply(id, {
        protocolVersion: "2024-11-05",
        capabilities: { tools: {} },
        serverInfo: { name: "aham-survey", version: "1.0.0" },
      });
      return;

    case "notifications/initialized":
      return; // 通知无需回应

    case "tools/list":
      reply(id, { tools: TOOLS });
      return;

    case "tools/call": {
      const name = params?.name;
      try {
        const data = await callApp(name, params?.arguments);
        reply(id, {
          content: [
            { type: "text", text: JSON.stringify(data, null, 2) },
          ],
        });
      } catch (err) {
        reply(id, {
          content: [{ type: "text", text: `错误：${err.message}` }],
          isError: true,
        });
      }
      return;
    }

    case "ping":
      reply(id, {});
      return;

    default:
      if (id !== undefined) replyError(id, `未实现的方法：${method}`);
  }
}

let buffer = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (chunk) => {
  buffer += chunk;
  let index;
  while ((index = buffer.indexOf("\n")) >= 0) {
    const line = buffer.slice(0, index).trim();
    buffer = buffer.slice(index + 1);
    if (!line) continue;
    try {
      handle(JSON.parse(line));
    } catch {
      process.stderr.write(`无法解析的输入：${line}\n`);
    }
  }
});
