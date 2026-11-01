// 界面取值视图：把插件根目录 tokens.json 的取值按界面的 CSS 变量名排好。
// tokens.json 是唯一来源。本文件只写「变量名 → tokens.json 键名和单位」的对应关系，不写任何取值。
// 视图的分组和变量名沿用界面原来的写法，键 row 生成 --wb-row；构建、lint、主题生成和测试都读这个视图。
//   ui('size.row')              视图里的一个取值，返回 { $value, $source }
//   resolve('size.row')         视图里的取值，带单位，引用全部展开：'36px'
//   source('size.row')          对应的 tokens.json 键名：'layout.ui.size.row'
// 构建脚本按 AHAM_DESIGN_TOKENS 环境变量或向上查找插件根目录（同时有 tokens.json 和 .claude-plugin/plugin.json）找到 tokens.json。
import {readFileSync, existsSync} from 'node:fs';
import {dirname, join, resolve as resolvePath} from 'node:path';
import {fileURLToPath} from 'node:url';

export function tokensPath() {
  if (process.env.AHAM_DESIGN_TOKENS) return resolvePath(process.env.AHAM_DESIGN_TOKENS);
  let dir = dirname(fileURLToPath(import.meta.url));
  while (dir !== dirname(dir)) {
    if (existsSync(join(dir, 'tokens.json')) && existsSync(join(dir, '.claude-plugin', 'plugin.json'))) return join(dir, 'tokens.json');
    dir = dirname(dir);
  }
  throw new Error('找不到 tokens.json：本目录不在 aham-design 插件里，也没有设置 AHAM_DESIGN_TOKENS');
}

export const design = JSON.parse(readFileSync(tokensPath(), 'utf8'));

// tokens.json 里的一个取值。值写成 {组.名} 时引用另一个取值；整串是引用时取被引用的原值（数字仍是数字），
// 串里夹着引用时逐个换成文字。
export function designValue(path, seen = []) {
  if (seen.includes(path)) throw new Error(`tokens.json 循环引用：${[...seen, path].join(' → ')}`);
  const node = path.split('.').reduce((o, k) => o?.[k], design);
  if (!node || !('$value' in node)) throw new Error(`tokens.json 没有 ${path}`);
  const v = node.$value;
  if (typeof v !== 'string') return v;
  const whole = /^\{([\w.-]+)\}$/.exec(v);
  if (whole) return designValue(whole[1], [...seen, path]);
  return v.replace(/\{([\w.-]+)\}/g, (_, p) => String(designValue(p, [...seen, path])));
}

// 对应关系的写法：[tokens.json 键名, 单位]。单位只加在数字上；字符串原样使用。
const PX = 'px';
const from = (path, unit = '') => ({path, unit});
// 遮罩：颜色取 color.ui.scrim，不透明度取 layout.ui.scrim_opacity。
const scrim = theme => ({compose: () => {
  const hex = designValue('color.ui.scrim').replace('#', ''), a = designValue(`layout.ui.scrim_opacity.${theme}`);
  return `rgba(${[0, 2, 4].map(i => parseInt(hex.slice(i, i + 2), 16)).join(',')},${a})`;
}, path: `color.ui.scrim + layout.ui.scrim_opacity.${theme}`});

const LIGHT = {
  bg: from('color.gray.0'),
  canvas: from('color.gray.4'),
  fill: from('color.gray.2'),
  hover: from('color.gray.2'),
  selected: from('color.gray.4'),
  button: from('color.gray.2'),
  'button-hover': from('color.gray.4'),
  'button-press': from('color.gray.6'),
  'nav-hover': from('color.gray.6'),
  'nav-selected': from('color.gray.8'),
  line: from('color.gray.5'),
  edge: from('color.gray.8'),
  'line-soft': from('color.gray.3'),
  'line-strong': from('color.gray.11'),
  'pop-bg': from('color.gray.0'),
  'pop-edge': from('color.gray.5'),
  ink: from('color.gray.18'),
  'ink-2': from('color.gray.15'),
  muted: from('color.gray.14'),
  faint: from('color.gray.12'),
  blue: from('color.blue.base'),
  'blue-bg': from('color.blue.bg'),
  action: from('color.blue.base'),
  'action-hover': from('color.blue.hover'),
  'action-press': from('color.blue.text'),
  on: from('color.gray.0'),
  success: from('color.semantic.success'),
  'success-bg': from('color.semantic.success_bg'),
  warning: from('color.semantic.warning'),
  'warning-bg': from('color.semantic.warning_bg'),
  'warning-mark': from('color.ui.warning_mark'),
  danger: from('color.semantic.danger'),
  'danger-bg': from('color.semantic.danger_bg'),
  'danger-press': from('color.ui.danger_press'),
  info: from('color.blue.base'),
  'info-bg': from('color.blue.bg'),
  'cat-1': from('color.categorical.1'),
  'cat-2': from('color.categorical.2'),
  'cat-3': from('color.categorical.3'),
  'cat-4': from('color.categorical.4'),
  'cat-5': from('color.categorical.5'),
  'cat-6': from('color.categorical.6'),
  scrim: scrim('light'),
};
const DARK = {
  bg: from('color.gray_dark.bg'),
  canvas: from('color.gray_dark.canvas'),
  fill: from('color.gray_dark.fill'),
  hover: from('color.gray_dark.fill'),
  selected: from('color.gray_dark.selected'),
  button: from('color.gray_dark.button'),
  'button-hover': from('color.gray_dark.button_hover'),
  'button-press': from('color.gray_dark.button_press'),
  'nav-hover': from('color.gray_dark.nav_hover'),
  'nav-selected': from('color.gray_dark.nav_selected'),
  line: from('color.gray_dark.line'),
  edge: from('color.gray_dark.edge'),
  'line-soft': from('color.gray_dark.line_soft'),
  'line-strong': from('color.gray_dark.line_strong'),
  'pop-bg': from('color.gray_dark.pop_bg'),
  'pop-edge': from('color.gray_dark.pop_edge'),
  ink: from('color.gray_dark.ink'),
  'ink-2': from('color.gray_dark.ink_2'),
  muted: from('color.gray_dark.muted'),
  faint: from('color.gray_dark.faint'),
  blue: from('color.blue.dark'),
  'blue-bg': from('color.ui.blue_bg_dark'),
  action: from('color.blue.base'),
  'action-hover': from('color.blue.hover'),
  'action-press': from('color.blue.text'),
  on: from('color.gray.0'),
  success: from('color.semantic.success_dark'),
  'success-bg': from('color.ui.success_bg_dark'),
  warning: from('color.semantic.warning_dark'),
  'warning-bg': from('color.ui.warning_bg_dark'),
  'warning-mark': from('color.ui.warning_mark_dark'),
  danger: from('color.semantic.danger_dark'),
  'danger-bg': from('color.ui.danger_bg_dark'),
  'danger-press': from('color.ui.danger_press_dark'),
  info: from('color.ui.info_dark'),
  'info-bg': from('color.ui.blue_bg_dark'),
  ...Object.fromEntries([1, 2, 3, 4, 5, 6].map(n => [`cat-${n}`, from(`color.ui.cat_${n}_dark`)])),
  scrim: scrim('dark'),
};
const CONTRAST_MORE = {
  light: {line: from('color.gray.13'), muted: from('color.gray.16')},
  dark: {line: from('color.ui.line_contrast_dark'), muted: from('color.gray_dark.muted')},
};

const group = (prefix, names, unit = PX) => Object.fromEntries(names.map(([name, key]) => [name, from(`${prefix}.${key}`, unit)]));
const same = names => names.map(n => [n, n.replace(/-/g, '_')]);

export const VIEW = {
  color: {light: LIGHT, dark: DARK, 'contrast-more': CONTRAST_MORE},
  font: {font: from('font.family.ui'), mono: from('font.family.code')},
  text: group('size.ui', same(['text-xs', 'body', 'leading', 'leading-xs', 'text-base', 'title', 'total', 'touch-input'])),
  space: group('layout.ui.space', same(['s1', 's2', 's3', 's4', 's5', 's6', 's7', 's8', 'icon-gap'])),
  radius: group('radius', [['radius', 'panel'], ['radius-pill', 'pill'], ['control-radius', 'control']]),
  shadow: group('shadow', [['shadow-pop', 'pop'], ['shadow-float', 'float']], ''),
  size: group('layout.ui.size', same(['list-row', 'row', 'row-compact', 'row-double', 'control', 'header-control', 'field', 'hit', 'touch', 'header-row', 'nav-item', 'dot', 'kbd', 'activity-icon', 'avatar', 'command-input', 'palette-input', 'palette-item', 'check-col', 'icon', 'hairline', 'menu-row'])),
  layout: group('layout.ui.frame', same(['rail', 'nav', 'gutter', 'page-gutter', 'page-gutter-wide', 'panel-narrow', 'panel-wide', 'panel-props', 'detail-width', 'body-width', 'record-width', 'form-max', 'label', 'table-min', 'search-width', 'pop-min', 'pop-max', 'pop-form', 'menu-width', 'toast-width', 'dialog-width', 'dialog-form', 'dialog-wide', 'dialog-split-height', 'dialog-split-nav', 'overlay-width', 'palette-top', 'create-top', 'related-code', 'setting-control', 'pop-control'])),
  breakpoint: group('layout.ui.breakpoint', [['bp-mobile', 'mobile'], ['bp-context', 'context'], ['bp-form', 'form'], ['bp-log-split', 'log_split'], ['bp-wide', 'wide']]),
  z: group('layout.ui.z', [['z-pop', 'pop'], ['z-scrim', 'scrim'], ['z-nav', 'nav'], ['z-toast', 'toast']], ''),
  motion: group('layout.ui.motion', same(['instant', 'fast', 'pop', 'base', 'ease', 'ease-move', 'press-scale', 'tooltip-delay', 'state-out', 'state-in']), ''),
};

const node = path => path.split('.').reduce((o, k) => o?.[k], VIEW);

// 视图取值：数字加单位，字符串原样。
export function resolve(path) {
  const n = node(path);
  if (!n || !('path' in n)) throw new Error(`Missing token: ${path}`);
  if (n.compose) return n.compose();
  const v = designValue(n.path);
  return typeof v === 'number' ? `${v}${n.unit}` : String(v);
}
export const source = path => node(path)?.path;

// 一个分组的取值：[变量名, 视图路径]。
export function leaves(path) {
  const n = node(path);
  return Object.entries(n).filter(([, v]) => v && typeof v === 'object' && 'path' in v).map(([k]) => [k, `${path}.${k}`]);
}

// 视图换成和原来 tokens.json 一样的形状，{ group: { name: { $value } } }，给测试和旧写法读。
const materialize = (obj, prefix) => Object.fromEntries(Object.entries(obj).map(([k, v]) => {
  const p = prefix ? `${prefix}.${k}` : k;
  return [k, 'path' in v ? {$value: resolve(p), $source: v.path} : materialize(v, p)];
}));
export const tokens = {$meta: {name: design.$meta.name, version: design.$meta.version}, ...materialize(VIEW, '')};
