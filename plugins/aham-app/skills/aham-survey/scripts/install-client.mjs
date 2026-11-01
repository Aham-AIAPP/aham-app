#!/usr/bin/env node
import { cp, mkdir, readFile, rename, stat, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { basename, dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const args = process.argv.slice(2);
const has = (name) => args.includes(`--${name}`);
const value = (name) => {
  const index = args.indexOf(`--${name}`);
  return index >= 0 ? args[index + 1] : undefined;
};
const client = value("client");
const adapter = value("adapter");
const config = value("config");
const targetHome = resolve(value("home") ?? homedir());
const apply = has("apply");
const supported = new Set(["codex", "claude", "claude-desktop", "vscode", "cursor"]);
const sourceSkill = resolve(dirname(fileURLToPath(import.meta.url)), "..");

if (!supported.has(client) || !adapter || !config) {
  process.stderr.write("用法：install-client.mjs --client codex|claude|claude-desktop|vscode|cursor --adapter <path> --config <path> [--home <path>] [--apply]\n");
  process.exit(2);
}
if (basename(sourceSkill) !== "aham-survey") throw new Error("Skill 根目录名称必须为 aham-survey");
await stat(resolve(adapter));
await stat(resolve(config));

const skillDestination = client === "claude" || client === "claude-desktop"
  ? join(targetHome, ".claude", "skills", "aham-survey")
  : join(targetHome, ".agents", "skills", "aham-survey");
const mcpDefinition = {
  type: "stdio",
  command: process.execPath,
  args: [resolve(adapter), "--config", resolve(config)],
};
const operations = [{ type: "copy-skill", from: sourceSkill, to: skillDestination }];

if (client === "codex") operations.push({ type: "merge-toml", path: join(targetHome, ".codex", "config.toml") });
if (client === "claude") operations.push({ type: "merge-json", path: join(targetHome, ".claude.json"), root: "mcpServers" });
if (client === "claude-desktop") operations.push({
  type: "merge-json",
  path: join(targetHome, "Library", "Application Support", "Claude", "claude_desktop_config.json"),
  root: "mcpServers",
});
if (client === "vscode") operations.push({ type: "merge-json", path: join(targetHome, ".copilot", "mcp-config.json"), root: "servers" });
if (client === "cursor") {
  operations.push({ type: "merge-json", path: join(targetHome, ".cursor", "mcp.json"), root: "mcpServers" });
  operations.push({ type: "write-rule", path: join(targetHome, ".cursor", "rules", "aham-survey.mdc") });
}

if (!apply) {
  process.stdout.write(`${JSON.stringify({ ok: true, mode: "dry-run", client, operations }, null, 2)}\n`);
  process.exit(0);
}

async function readTextIfExists(path, fallback = "") {
  try { return await readFile(path, "utf8"); } catch (error) {
    if (error.code === "ENOENT") return fallback;
    throw error;
  }
}

async function backupIfExists(path) {
  try {
    await stat(path);
    const backup = `${path}.backup-${new Date().toISOString().replaceAll(":", "-")}`;
    await cp(path, backup, { recursive: true, errorOnExist: true });
    return backup;
  } catch (error) {
    if (error.code === "ENOENT") return null;
    throw error;
  }
}

async function atomicWrite(path, content, mode) {
  await mkdir(dirname(path), { recursive: true, mode: 0o700 });
  const temporary = `${path}.tmp-${process.pid}`;
  await writeFile(temporary, content, { encoding: "utf8", mode });
  await rename(temporary, path);
}

await mkdir(dirname(skillDestination), { recursive: true, mode: 0o700 });
const skillBackup = await backupIfExists(skillDestination);
await cp(sourceSkill, skillDestination, {
  recursive: true,
  filter: (source) => !source.includes(`${join("scripts", "node_modules")}`),
});

if (client === "codex") {
  const path = operations.find((op) => op.type === "merge-toml").path;
  let current = await readTextIfExists(path);
  const begin = "# BEGIN aham-survey managed";
  const end = "# END aham-survey managed";
  const existingStart = current.indexOf(begin);
  const existingEnd = current.indexOf(end);
  if (existingStart < 0 && /^\s*\[mcp_servers\.aham-survey\]/m.test(current)) {
    throw new Error(`已有非安装器管理的 aham-survey 配置，请手工处理：${path}`);
  }
  if (existingStart >= 0 && existingEnd >= existingStart) {
    current = `${current.slice(0, existingStart)}${current.slice(existingEnd + end.length)}`.trimEnd();
  }
  const quote = (text) => JSON.stringify(text);
  const block = `${begin}\n[mcp_servers.aham-survey]\ncommand = ${quote(process.execPath)}\nargs = [${mcpDefinition.args.map(quote).join(", ")}]\nstartup_timeout_sec = 20\ntool_timeout_sec = 60\ndefault_tools_approval_mode = "writes"\n${end}`;
  await backupIfExists(path);
  await atomicWrite(path, `${current}${current ? "\n\n" : ""}${block}\n`, 0o600);
} else {
  const op = operations.find((item) => item.type === "merge-json");
  const raw = await readTextIfExists(op.path, "{}");
  const document = JSON.parse(raw);
  document[op.root] = document[op.root] ?? {};
  document[op.root]["aham-survey"] = mcpDefinition;
  await backupIfExists(op.path);
  await atomicWrite(op.path, `${JSON.stringify(document, null, 2)}\n`, 0o600);
}

if (client === "cursor") {
  const rulePath = operations.find((op) => op.type === "write-rule").path;
  const rule = `---\ndescription: Use Aham Survey for structured customer discovery and survey workflows\nalwaysApply: false\n---\n\nWhen the user asks about customer discovery, interviews, survey answers, survey gaps, or survey reports, use the aham-survey MCP. Call get_capabilities first. Never invent customer facts. For mapped interview answers, preview_answer_import before commit_answer_import and obtain confirmation.\n`;
  await backupIfExists(rulePath);
  await atomicWrite(rulePath, rule, 0o600);
}

process.stdout.write(`${JSON.stringify({ ok: true, mode: "applied", client, skillDestination, skillBackup, tokenCopied: false }, null, 2)}\n`);
