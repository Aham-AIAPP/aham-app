import { spawn } from "node:child_process";

export class MCPStdioClient {
  constructor(adapter, config, timeoutMs = 10_000) {
    this.nextId = 1;
    this.pending = new Map();
    this.timeoutMs = timeoutMs;
    this.stderr = "";
    this.child = spawn(process.execPath, [adapter, "--config", config], {
      stdio: ["pipe", "pipe", "pipe"],
    });

    let buffer = "";
    this.child.stdout.setEncoding("utf8");
    this.child.stdout.on("data", (chunk) => {
      buffer += chunk;
      let newline;
      while ((newline = buffer.indexOf("\n")) >= 0) {
        const line = buffer.slice(0, newline).trim();
        buffer = buffer.slice(newline + 1);
        if (!line) continue;
        let message;
        try { message = JSON.parse(line); } catch { continue; }
        const pending = this.pending.get(message.id);
        if (!pending) continue;
        clearTimeout(pending.timer);
        this.pending.delete(message.id);
        if (message.error) pending.reject(new Error(message.error.message));
        else pending.resolve(message.result);
      }
    });
    this.child.stderr.setEncoding("utf8");
    this.child.stderr.on("data", (chunk) => {
      this.stderr = `${this.stderr}${chunk}`.slice(-4_096);
    });
    this.child.on("exit", (code) => {
      for (const pending of this.pending.values()) {
        clearTimeout(pending.timer);
        pending.reject(new Error(`MCP Adapter 已退出（code ${code ?? "unknown"}）`));
      }
      this.pending.clear();
    });
  }

  request(method, params = {}) {
    const id = this.nextId++;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`${method} 超时`));
      }, this.timeoutMs);
      this.pending.set(id, { resolve, reject, timer });
      this.child.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", id, method, params })}\n`);
    });
  }

  notify(method, params = {}) {
    this.child.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", method, params })}\n`);
  }

  close() {
    this.child.stdin.end();
    this.child.kill("SIGTERM");
  }
}

export async function verify(adapter, config) {
  const client = new MCPStdioClient(adapter, config);
  try {
    const initialized = await client.request("initialize", {
      protocolVersion: "2025-06-18",
      capabilities: {},
      clientInfo: { name: "aham-survey-verifier", version: "1.0.0" },
    });
    client.notify("notifications/initialized");
    const listed = await client.request("tools/list");
    await client.request("ping");
    const capabilityCall = await client.request("tools/call", {
      name: "get_capabilities",
      arguments: {},
    });
    if (capabilityCall?.isError) {
      throw new Error(capabilityCall.structuredContent?.message ?? "get_capabilities 失败");
    }
    const capabilities = capabilityCall?.structuredContent?.result;
    return {
      protocolVersion: initialized.protocolVersion,
      server: initialized.serverInfo,
      toolCount: listed.tools?.length ?? 0,
      contractVersion: capabilities?.mcpContractVersion,
      catalogVersion: capabilities?.questionCatalogVersion,
      featureCount: Object.keys(capabilities?.features ?? {}).length,
    };
  } finally {
    client.close();
  }
}
