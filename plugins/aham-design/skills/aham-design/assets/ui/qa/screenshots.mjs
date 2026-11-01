// 示例页基准截图：按固定视口、主题、时钟和语言给 examples/ 下每个示例页截全页图，
// 再把 aham.css、aham.js 复制进同一目录，用 scripts/compare_outputs.py diff 比对两份产出。
// 运行：node qa/screenshots.mjs [--out 目录] [--root 仓库目录] [--widths 1440,390] [--themes light,dark]
// 需要 @playwright/test 和 Chromium：npm ci && npx playwright install --with-deps chromium
import {chromium} from '@playwright/test';
import {spawn} from 'node:child_process';
import {copyFile, mkdir, readdir, rm, writeFile} from 'node:fs/promises';
import {join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {parseArgs} from 'node:util';

const {values: opt} = parseArgs({options: {
  root: {type: 'string', default: '.'},
  out: {type: 'string', default: 'qa-results/shots'},
  widths: {type: 'string', default: '1440,390'},
  themes: {type: 'string', default: 'light,dark'},
  port: {type: 'string', default: '8770'},
}});
const root = resolve(opt.root), out = resolve(opt.out), base = `http://127.0.0.1:${opt.port}`;
const widths = opt.widths.split(',').map(Number), themes = opt.themes.split(',');
// 1440 宽用 900 高起步；390 宽是 rules/1 和 rules/9 要求验收的手机宽度，按常见手机屏用 844 高起步。
const startHeight = width => (width <= 640 ? 844 : 900);
// 页面里的「今天」固定在 examples/list-model.mjs 的 TODAY 那一天，相对日期每天截出来都一样。
const CLOCK = new Date('2026-09-30T09:00:00+08:00');
// 视口加高的上限，防止异常页面产生过大的图片。
const MAX_HEIGHT = 12000;

const pages = (await readdir(join(root, 'examples'))).filter(f => f.endsWith('.html') && !f.startsWith('_')).sort();
if (!pages.length) throw new Error(`${root}/examples 下没有示例页`);

const serve = fileURLToPath(new URL('../scripts/serve.mjs', import.meta.url));
const server = spawn(process.execPath, [serve], {env: {...process.env, PORT: opt.port, AHAM_ROOT: root}, stdio: 'pipe'});
await new Promise((ok, fail) => { server.stdout.once('data', ok); server.once('error', fail); server.once('exit', code => fail(new Error(`server ${code}`))); });

// 外框高度是 100vh，正文在内部滚动区里滚动，整页截图只能截到首屏。
// 这里反复把视口加高到内部滚动区不再溢出为止；加高后溢出量不减少的区域（例如固定最大高度的列表）不再追。
function overflowProbe() {
  const fixed = new WeakSet();
  let last = new Map();
  window.__ahamShotOverflow = () => {
    let max = 0;
    const now = new Map();
    for (const el of document.querySelectorAll('body *')) {
      if (fixed.has(el) || !el.getClientRects().length || !/auto|scroll/.test(getComputedStyle(el).overflowY)) continue;
      const over = el.scrollHeight - el.clientHeight;
      if (over <= 1) continue;
      if (last.has(el) && over >= last.get(el)) { fixed.add(el); continue; }
      now.set(el, over);
      max = Math.max(max, over);
    }
    last = now;
    return max;
  };
}
// 页面一建出 .aham-workbench 就写上 data-theme，首帧就是目标主题，不经过亮色到暗色的切换。
function themeProbe(theme) {
  const set = () => { for (const el of document.querySelectorAll('.aham-workbench')) if (el.dataset.theme !== theme) el.dataset.theme = theme; };
  new MutationObserver(set).observe(document, {childList: true, subtree: true, attributes: true, attributeFilter: ['data-theme']});
}
const frames = page => page.evaluate(() => new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r))));

const manifest = [];
let failures = 0;
let browser;
try {
  // 这几项让 Chromium 的软件栅格化少受线程调度和 CPU 指令集影响，同一张图两次截出来的像素更稳定。
  browser = await chromium.launch({args: ['--disable-partial-raster', '--disable-skia-runtime-opts', '--disable-lcd-text', '--font-render-hinting=none']});
  await rm(out, {recursive: true, force: true});
  for (const width of widths) for (const theme of themes) {
    const dir = join(out, `${width}-${theme}`);
    await mkdir(dir, {recursive: true});
    const context = await browser.newContext({
      viewport: {width, height: startHeight(width)}, deviceScaleFactor: 1,
      locale: 'zh-CN', timezoneId: 'Asia/Shanghai', colorScheme: theme, reducedMotion: 'reduce',
    });
    await context.clock.setFixedTime(CLOCK);
    await context.addInitScript(overflowProbe);
    await context.addInitScript(themeProbe, theme);
    for (const file of pages) {
      const page = await context.newPage(), errors = [], name = file.replace(/\.html$/, '');
      page.on('pageerror', e => errors.push(e.message));
      try {
        await page.goto(`${base}/examples/${file}`, {waitUntil: 'networkidle'});
        await page.evaluate(() => document.fonts.ready);
        await frames(page);
        let height = startHeight(width);
        for (let i = 0; i < 6; i++) {
          const extra = await page.evaluate(() => window.__ahamShotOverflow());
          if (!extra || height >= MAX_HEIGHT) break;
          height = Math.min(MAX_HEIGHT, height + Math.ceil(extra));
          await page.setViewportSize({width, height});
          await frames(page);
        }
        // 加高后新露出的文字可能还要加载字体，截图前再等一次。
        await page.evaluate(() => document.fonts.ready);
        await frames(page);
        await page.screenshot({path: join(dir, `${name}.png`), fullPage: true, animations: 'disabled', caret: 'hide', scale: 'css'});
        manifest.push({page: name, width, theme, viewportHeight: height, errors});
        if (errors.length) console.warn(`页面报错：${width}-${theme}/${file}：${errors.join('；')}`);
      } catch (error) {
        failures++;
        manifest.push({page: name, width, theme, failure: error.message.split('\n')[0]});
        console.error(`截图失败：${width}-${theme}/${file}：${error.message}`);
      } finally {
        await page.close();
      }
    }
    await context.close();
  }
  for (const f of ['aham.css', 'aham.js']) await copyFile(join(root, f), join(out, f));
  await writeFile(join(out, 'shots.json'), JSON.stringify(manifest, null, 1) + '\n');
  console.log(`已截 ${manifest.length - failures} 张图：${pages.length} 个示例页 × 宽度 ${widths.join('、')} × 主题 ${themes.join('、')}，输出到 ${out}`);
} finally {
  await browser?.close();
  server.kill();
}
if (failures) process.exitCode = 1;
