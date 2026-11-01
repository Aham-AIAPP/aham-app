// 从 aham-design 插件复制界面取值，写成 src/styles/aham/tokens.json。
// aham-design 的 tokens.json 是唯一取值来源；它的 assets/ui/scripts/tokens.mjs 把取值排成界面的 --wb-* 变量视图。
// 本脚本只复制这个视图并记录来源，不改任何取值。复制后运行 node scripts/build-aham-tokens.mjs 生成 tokens.css。
// 用法：AHAM_DESIGN_DIR=<aham-plugins 仓库>/plugins/aham-design node scripts/sync-aham-design-tokens.mjs
import {writeFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {join, resolve} from 'node:path';
import {pathToFileURL} from 'node:url';

const dir = process.env.AHAM_DESIGN_DIR;
if (!dir) throw new Error('请设置 AHAM_DESIGN_DIR，指向 aham-plugins 仓库里的 plugins/aham-design 目录');
const plugin = resolve(dir);
const {tokens} = await import(pathToFileURL(join(plugin, 'skills/aham-design/assets/ui/scripts/tokens.mjs')).href);
let commit = 'unknown';
try { commit = execFileSync('git', ['-C', plugin, 'rev-parse', 'HEAD'], {encoding: 'utf8'}).trim(); } catch { /* 不在 git 仓库里时记为 unknown */ }
const out = {
  $meta: {
    ...tokens.$meta,
    $description: '界面取值，复制自 aham-design 插件（tokens.json 经 assets/ui/scripts/tokens.mjs 生成的 --wb-* 视图）。不要手改；改取值先改 aham-design，再运行 scripts/sync-aham-design-tokens.mjs。',
    source: {
      repository: 'Aham-AIAPP/aham-plugins（GitHub 仓库尚未建立，复制自本地仓库）',
      path: 'plugins/aham-design/tokens.json',
      commit,
    },
  },
  ...Object.fromEntries(Object.entries(tokens).filter(([key]) => key !== '$meta')),
};
writeFileSync(new URL('../src/styles/aham/tokens.json', import.meta.url), JSON.stringify(out, null, 2) + '\n');
console.log(`tokens.json 已更新：aham-design ${tokens.$meta.version}，提交 ${commit}`);
