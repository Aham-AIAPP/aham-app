#!/usr/bin/env node
import { access } from "node:fs/promises";
import { resolve } from "node:path";
import { verify } from "./mcp-client.mjs";

const args = process.argv.slice(2);
const value = (name) => {
  const index = args.indexOf(`--${name}`);
  return index >= 0 ? args[index + 1] : undefined;
};
const adapter = value("adapter");
const config = value("config");
if (!adapter || !config) {
  process.stderr.write("用法：verify-connection.mjs --adapter <path> --config <path>\n");
  process.exit(2);
}

try {
  await access(resolve(adapter));
  await access(resolve(config));
  const result = await verify(resolve(adapter), resolve(config));
  process.stdout.write(`${JSON.stringify({ ok: true, ...result }, null, 2)}\n`);
} catch (error) {
  process.stderr.write(`${JSON.stringify({ ok: false, message: error.message }, null, 2)}\n`);
  process.exit(1);
}

