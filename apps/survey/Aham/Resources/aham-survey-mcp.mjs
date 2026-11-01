#!/usr/bin/env node
/**
 * Aham Survey · MCP stdio Adapter
 *
 * AI Client ── stdio MCP ──▶ Adapter ── authenticated localhost RPC ──▶ App
 *
 * 推荐用法：
 *   node aham-survey-mcp.mjs --config "/path/to/mcp-connection.json"
 *
 * 连接文件由 App 生成，权限为 0600。Token 不应出现在命令行、Skill 或日志中。
 */

import { readFile } from "node:fs/promises";

const argv = process.argv.slice(2);
function flag(name, fallback) {
  const index = argv.indexOf(`--${name}`);
  return index >= 0 && argv[index + 1] ? argv[index + 1] : fallback;
}

async function readJSON(path, label) {
  try {
    return JSON.parse(await readFile(path, "utf8"));
  } catch (error) {
    throw new Error(`无法读取${label}：${error.message}`);
  }
}

const configPath = flag("config", process.env.AHAM_MCP_CONFIG);
const connection = configPath ? await readJSON(configPath, " Aham Survey 连接文件") : {};
const port = flag("port", process.env.AHAM_MCP_PORT ?? connection.port);
// 故意不支持 --token：命令行参数会暴露在进程列表中。
const token = process.env.AHAM_MCP_TOKEN ?? connection.token;
const endpointBase = connection.endpoint ?? (port ? `http://127.0.0.1:${port}` : null);

if (!endpointBase || !token) {
  process.stderr.write(
    "缺少 Aham Survey 连接配置。请从 App 首页复制不含 Token 的最新配置。\n"
  );
  process.exit(2);
}

const endpoint = `${endpointBase.replace(/\/$/, "")}/rpc`;
const contractURL = new URL("./mcp-contract.json", import.meta.url);
const contract = JSON.parse(await readFile(contractURL, "utf8"));
const tools = contract.tools.map(({ name, description, inputSchema }) => ({
  name,
  description,
  inputSchema,
}));
const toolNames = new Set(tools.map((tool) => tool.name));

const supportedProtocolVersions = [
  "2024-11-05",
  "2025-03-26",
  "2025-06-18",
  "2025-11-25",
];

const prompts = [
  {
    name: "create-survey-project",
    description: "根据已知客户资料创建结构化调研项目；未知事实保持为空。",
    arguments: [{ name: "customer", description: "客户名称", required: true }],
  },
  {
    name: "map-interview-to-questions",
    description: "把访谈证据映射到题目，先预览校验，再经用户确认提交。",
    arguments: [
      { name: "project", description: "项目 UUID", required: true },
      { name: "department", description: "部门 id", required: true },
    ],
  },
  {
    name: "review-survey-gaps",
    description: "检查必答题、无效答案、冲突和待确认内容。",
    arguments: [{ name: "project", description: "项目 UUID", required: true }],
  },
  {
    name: "prepare-survey-report",
    description: "回读项目快照和缺口后生成调研报告。",
    arguments: [{ name: "project", description: "项目 UUID", required: true }],
  },
];

const promptInstructions = {
  "create-survey-project": ({ customer = "目标客户" }) =>
    `为「${customer}」创建 Aham Survey 调研项目。先调用 get_capabilities 和 list_departments；只使用用户已提供的客户事实，未知字段保持空白；创建后用 UUID 回读校验。`,
  "map-interview-to-questions": ({ project = "项目 UUID", department = "部门 id" }) =>
    `处理项目 ${project} 的 ${department} 访谈材料。先调用 list_questions，逐条保留证据并映射合法题号；单选/多选必须使用题库原文；调用 preview_answer_import 展示预览，获得用户确认后再用同一批内容调用 commit_answer_import。`,
  "review-survey-gaps": ({ project = "项目 UUID" }) =>
    `检查项目 ${project}。读取项目与各部门问题，只把题型校验通过的答案视为完成；按部门列出必答缺口、冲突、无效选项和待确认事实，不把建议写成客户回答。`,
  "prepare-survey-report": ({ project = "项目 UUID" }) =>
    `为项目 ${project} 准备报告。先回读项目修订号、进度和缺口，确认导出部门后调用 export_report；明确“生成成功”不等于客户确认或最终版。`,
};

async function callApp(tool, args) {
  let response;
  try {
    response = await fetch(endpoint, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify({ tool, args: args ?? {} }),
      signal: AbortSignal.timeout(30_000),
    });
  } catch (error) {
    throw {
      code: "APP_UNREACHABLE",
      message: "连不上 Aham Survey。请确认 App 正在运行且 MCP 服务已启动。",
      retryable: true,
      details: { cause: error.message },
    };
  }

  let payload;
  try {
    payload = await response.json();
  } catch {
    throw {
      code: "APP_RESPONSE_INVALID",
      message: `Aham Survey 返回了无法解析的 HTTP ${response.status} 响应。`,
      retryable: true,
    };
  }

  if (!response.ok || payload.ok === false) {
    const structured = payload.error;
    if (structured && typeof structured === "object") throw structured;
    throw {
      code: response.status === 401 ? "AUTH_TOKEN_INVALID" : "APP_CALL_FAILED",
      message: typeof structured === "string" ? structured : `HTTP ${response.status}`,
      retryable: response.status >= 500,
    };
  }
  return payload.data;
}

function send(message) {
  process.stdout.write(`${JSON.stringify(message)}\n`);
}

function reply(id, result) {
  send({ jsonrpc: "2.0", id, result });
}

function replyError(id, error, fallbackCode = -32000) {
  const message = error?.message ?? String(error ?? "未知错误");
  send({
    jsonrpc: "2.0",
    id,
    error: {
      code: fallbackCode,
      message,
      data: typeof error === "object" ? error : undefined,
    },
  });
}

function toolErrorResult(error) {
  const payload = typeof error === "object"
    ? error
    : { code: "TOOL_CALL_FAILED", message: String(error), retryable: false };
  return {
    content: [{ type: "text", text: JSON.stringify(payload, null, 2) }],
    structuredContent: payload,
    isError: true,
  };
}

async function handle(request) {
  const { id, method, params } = request;

  try {
    switch (method) {
      case "initialize": {
        const requested = params?.protocolVersion;
        const protocolVersion = supportedProtocolVersions.includes(requested)
          ? requested
          : supportedProtocolVersions.at(-1);
        reply(id, {
          protocolVersion,
          capabilities: { tools: {}, prompts: {}, resources: {} },
          serverInfo: { name: "aham-survey", version: "1.1.0" },
          instructions:
            "先调用 get_capabilities。访谈自动映射必须 preview 后再 commit；未知事实保持为空。",
        });
        return;
      }

      case "notifications/initialized":
      case "notifications/cancelled":
        return;

      case "tools/list":
        reply(id, { tools });
        return;

      case "tools/call": {
        const name = params?.name;
        if (!toolNames.has(name)) {
          reply(id, toolErrorResult({
            code: "TOOL_NOT_FOUND",
            message: `未知工具：${name ?? "<empty>"}`,
            retryable: false,
          }));
          return;
        }
        try {
          const data = await callApp(name, params?.arguments);
          reply(id, {
            content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
            structuredContent: { result: data },
          });
        } catch (error) {
          reply(id, toolErrorResult(error));
        }
        return;
      }

      case "prompts/list":
        reply(id, { prompts });
        return;

      case "prompts/get": {
        const name = params?.name;
        const build = promptInstructions[name];
        if (!build) {
          replyError(id, new Error(`未知 Prompt：${name}`), -32602);
          return;
        }
        reply(id, {
          description: prompts.find((prompt) => prompt.name === name)?.description,
          messages: [{
            role: "user",
            content: { type: "text", text: build(params?.arguments ?? {}) },
          }],
        });
        return;
      }

      case "resources/list":
        reply(id, {
          resources: [
            {
              uri: "aham://capabilities",
              name: "Aham Survey capabilities",
              description: "App、MCP 契约与功能版本",
              mimeType: "application/json",
            },
            {
              uri: "aham://departments",
              name: "Aham Survey departments",
              description: "当前实际安装的部门题库和调研范围",
              mimeType: "application/json",
            },
          ],
        });
        return;

      case "resources/read": {
        const uri = params?.uri;
        const tool = uri === "aham://capabilities"
          ? "get_capabilities"
          : uri === "aham://departments"
            ? "list_departments"
            : null;
        if (!tool) {
          replyError(id, new Error(`未知 Resource：${uri}`), -32602);
          return;
        }
        const data = await callApp(tool, {});
        reply(id, {
          contents: [{ uri, mimeType: "application/json", text: JSON.stringify(data, null, 2) }],
        });
        return;
      }

      case "ping":
        reply(id, {});
        return;

      default:
        if (id !== undefined) replyError(id, new Error(`未实现的方法：${method}`), -32601);
    }
  } catch (error) {
    if (id !== undefined) replyError(id, error);
  }
}

let buffer = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (chunk) => {
  buffer += chunk;
  let newline;
  while ((newline = buffer.indexOf("\n")) >= 0) {
    const line = buffer.slice(0, newline).trim();
    buffer = buffer.slice(newline + 1);
    if (!line) continue;
    try {
      void handle(JSON.parse(line));
    } catch {
      process.stderr.write("收到无法解析的 MCP JSON-RPC 消息。\n");
    }
  }
});
