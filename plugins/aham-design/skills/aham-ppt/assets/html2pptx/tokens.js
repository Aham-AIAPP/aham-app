// 读 aham-design 插件根目录的 tokens.json，给出各脚本要用的常量。本文件只做查找、引用解析和换算，不写数值。
// references/style-tokens.md 列出每个常量对应的 tokens.json 键名，由插件的 tests/test_ppt_tokens.py 检查一致。
//
// 查找 tokens.json 的顺序：
// 1. 环境变量 AHAM_DESIGN_TOKENS 指向的文件。
// 2. 从本文件所在目录逐级向上，第一个同时有 tokens.json 和 .claude-plugin/plugin.json 的目录，即插件根目录。
//    本文件随插件安装在 <插件根>/skills/aham-ppt/assets/html2pptx/，向上四级就是插件根。
//    这一步不读 CLAUDE_PLUGIN_ROOT：从 aham-app 的技能里调用时，该变量指向 aham-app，不是本插件。
const fs = require('fs'), path = require('path');

const TOKENS_ENV = 'AHAM_DESIGN_TOKENS';

function tokensPath() {
  if (process.env[TOKENS_ENV]) return path.resolve(process.env[TOKENS_ENV]);
  for (let dir = __dirname; ; dir = path.dirname(dir)) {
    if (fs.existsSync(path.join(dir, 'tokens.json')) && fs.existsSync(path.join(dir, '.claude-plugin', 'plugin.json'))) return path.join(dir, 'tokens.json');
    if (path.dirname(dir) === dir) break;
  }
  throw new Error(`找不到 tokens.json：本引擎不在 aham-design 插件目录里，也没有设置 ${TOKENS_ENV}`);
}

const TOKENS_PATH = tokensPath();
const RAW = JSON.parse(fs.readFileSync(TOKENS_PATH, 'utf8'));

// 取值写成 {"$value": …}；值为 "{组.名}" 时引用另一个取值
function lookup(dotted, seen = []) {
  if (seen.includes(dotted)) throw new Error(`tokens.json 循环引用：${[...seen, dotted].join(' → ')}`);
  let node = RAW;
  for (const k of dotted.split('.')) {
    if (!node || typeof node !== 'object' || !(k in node)) throw new Error(`tokens.json 没有 ${dotted}`);
    node = node[k];
  }
  if (!node || typeof node !== 'object' || !('$value' in node)) throw new Error(`tokens.json 的 ${dotted} 不是取值`);
  const m = typeof node.$value === 'string' && /^\{([A-Za-z0-9_.\-]+)\}$/.exec(node.$value);
  return m ? lookup(m[1], [...seen, dotted]) : node.$value;
}
// 一个分组下的全部取值，键名不变
function group(dotted) {
  let node = RAW;
  for (const k of dotted.split('.')) node = node[k];
  return Object.fromEntries(Object.keys(node).filter(k => !k.startsWith('$')).map(k => [k, lookup(`${dotted}.${k}`)]));
}
// color.ppt 的键换成引擎沿用的常量名：ink_1 → ink1，ai_bg → aiBg，service → svc，product → prod
const PPT_COLOR_NAMES = { service: 'svc', service_bg: 'svcBg', product: 'prod', product_bg: 'prodBg', ai_bg: 'aiBg' };
const colorName = k => PPT_COLOR_NAMES[k] || k.replace(/_/g, '');
const rename = (obj, fn) => Object.fromEntries(Object.entries(obj).map(([k, v]) => [fn(k), v]));

const L = 'layout.ppt';
const CANVAS = { w: lookup(`${L}.canvas.width`), h: lookup(`${L}.canvas.height`), pxPerPt: lookup(`${L}.canvas.px_per_pt`) };
const PX_PER_PT = CANVAS.pxPerPt;                 // 2px = 1 磅
const PX_PER_IN = PX_PER_PT * 72;                 // 144px = 1 英寸
const fr = group(`${L}.frame`);
const FRAME = {
  margin: fr.margin, right: fr.right,
  headerTop: fr.header_top, titleTop: fr.title_top, subTop: fr.sub_top, providerTop: fr.provider_top,
  main: { y0: fr.main_top, y1: fr.main_bottom },
  attr: { y0: fr.attr_top, y1: fr.attr_bottom },
  footLine: fr.foot_line, footTop: fr.foot_top,
};

// 字体栈的第一项
const firstFamily = stack => stack.split(',')[0].replace(/['"]/g, '').trim();
const FONT_STACK = lookup('font.family.ui');      // 网页预览的字体栈，只列本机字体
const CODE = lookup('font.family.code');          // 等宽字体栈，只用于页面上的代码

module.exports = {
  TOKENS_PATH,
  C: rename(group('color.ppt'), colorName),
  FS: group('size.ppt'),
  LW: group(`${L}.stroke`),
  RAD: group(`${L}.radius`),
  CANVAS, PX_PER_PT, PX_PER_IN,
  FONT_STACK, CODE,
  FONT_FACE: lookup('font.family.file'),          // 导出到 PPT 时写的字体：中文、西文和数字同一种
  CODE_FACE: firstFamily(CODE),                   // 页面写了等宽字体（代码）时导出用的字体
  // 预览页外框的深色模式，取界面深色灰阶；幻灯片本身不用
  DARK: { bg: lookup('color.gray_dark.bg'), ink: lookup('color.gray_dark.ink'), muted: lookup('color.gray_dark.muted') },
  FRAME, MARGIN: FRAME.margin, RIGHT: FRAME.right,
  MAIN: { y0: FRAME.main.y0, y1: FRAME.main.y1 },
  // 主图区矩形：左右边距之间，主图区上下界之间
  MAIN_RECT: { x: FRAME.margin, y: FRAME.main.y0, w: FRAME.right - FRAME.margin, h: FRAME.main.y1 - FRAME.main.y0 },
  lookup,
};
