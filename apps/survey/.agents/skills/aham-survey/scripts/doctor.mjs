#!/usr/bin/env node
import { readFile, stat } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { verify } from "./mcp-client.mjs";

const args = process.argv.slice(2);
const value = (name) => {
  const index = args.indexOf(`--${name}`);
  return index >= 0 ? args[index + 1] : undefined;
};
const adapter = value("adapter");
const config = value("config");
const checks = [];
const record = (name, ok, detail) => checks.push({ name, ok, detail });

try {
  const major = Number(process.versions.node.split(".")[0]);
  record("node", major >= 18, `v${process.versions.node}`);
  if (!adapter || !config) throw new Error("需要 --adapter 和 --config 路径");

  const adapterPath = resolve(adapter);
  const configPath = resolve(config);
  const adapterStat = await stat(adapterPath);
  record("adapter", adapterStat.isFile(), adapterPath);
  const contractPath = resolve(dirname(adapterPath), "mcp-contract.json");
  const contract = JSON.parse(await readFile(contractPath, "utf8"));
  record("contract", contract.version === 1, `version ${contract.version}, ${contract.tools?.length ?? 0} tools`);

  const configStat = await stat(configPath);
  const mode = configStat.mode & 0o777;
  record("descriptor-permissions", (mode & 0o077) === 0, `mode ${mode.toString(8).padStart(3, "0")}`);
  const descriptor = JSON.parse(await readFile(configPath, "utf8"));
  const endpoint = String(descriptor.endpoint ?? "");
  record("loopback", /^http:\/\/(127\.0\.0\.1|localhost)(:\d+)?$/i.test(endpoint), endpoint || "missing");
  record("credential", typeof descriptor.token === "string" && descriptor.token.length >= 16, "present and masked");

  if (checks.every((check) => check.ok)) {
    const result = await verify(adapterPath, configPath);
    record(
      "mcp-readonly-smoke",
      result.toolCount > 0 && result.contractVersion === 1 && result.catalogVersion >= 1,
      `${result.toolCount} tools, contract ${result.contractVersion}, catalog ${result.catalogVersion}`
    );
  }
} catch (error) {
  record("doctor", false, error.message);
}

const ok = checks.length > 0 && checks.every((check) => check.ok);
process.stdout.write(`${JSON.stringify({ ok, checks }, null, 2)}\n`);
process.exitCode = ok ? 0 : 1;
