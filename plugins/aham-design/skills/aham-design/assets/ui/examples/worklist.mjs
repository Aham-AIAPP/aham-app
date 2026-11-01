// Worklist (rules/4-页面.md 4.2): approve or return expense requests in the list itself.
//   通过   done at once, the row moves to 我已处理, the toast offers 撤销
//   退回   asks for a reason first (rules/6-反馈.md 6.3)
//   批量通过 rows that cannot be approved yet are named before anything runs (rules/6-反馈.md 6.4)
// A row whose countersign is still open has 通过 disabled with the reason next to it (rules/3-控件.md 3.3).
import { initShell, initPalette, registerShortcut, openConfirm, toast, personHTML, escapeHtml as esc } from '../aham.js';
import {initAccount} from './account.mjs';
import { money } from './format.mjs';

const root = document.querySelector('.aham-workbench');
const $ = s => root.querySelector(s), $$ = s => [...root.querySelectorAll(s)];

const ITEMS = [
  ['FY-20261012-004', '临港工厂设备维保费用', '设备部', 42_600_00, '林悦', '10-16 17:42', ''],
  ['FY-20261013-011', '质量部年度外审费用', '质量部', 16_850_00, '周航', '10-16 15:08', '单价高于标准价，等财务负责人加签'],
  ['FY-20260930-018', '四季度质量工具培训费用', '质量部', 44_990_00, '林悦', '10-16 11:30', ''],
  ['FY-20261014-019', '仓库货架安装监理费用', '仓储部', 9_240_00, '许宁', '10-15 18:12', ''],
  ['FY-20261015-003', '新员工入职培训费用', '人事部', 31_500_00, '陈默', '10-15 09:51', ''],
  ['FY-20261015-027', '办公网络年度维护费用', '信息部', 4_800_00, '周航', '10-14 16:27', ''],
  ['FY-20261016-008', '安全检查差旅费用', '安全部', 5_620_00, '许宁', '10-14 10:03', '单价高于标准价，等财务负责人加签'],
];
let rows = ITEMS.map(([code, name, dept, cents, by, at, wait], id) => ({ id, code, name, dept, cents, by, at, wait, result: null, reason: '' }));
let tab = 'todo';
const selected = new Set();
const todo = () => rows.filter(r => !r.result), done = () => rows.filter(r => r.result);

function render() {
  const t = todo().length, d = done().length;
  $('#tabs').innerHTML = `<button type="button" data-tab="todo" aria-pressed="${tab === 'todo'}">待我审批 ${t}</button><button type="button" data-tab="done" aria-pressed="${tab === 'done'}">我已处理 ${d}</button>`;
  const list = tab === 'todo' ? todo() : done();
  $('#count').textContent = `${list.length} 张费用申请`;
  // The sidebar count and the 待我审批 tab read the same rows, so handling one row lowers both (rules/4-页面.md 4.1).
  const navCount = root.querySelector('.wb-rail .wb-nav-count');
  if (navCount) { navCount.textContent = t; navCount.setAttribute('aria-label', `${t} 项待办`); navCount.hidden = !t; }
  const bulk = tab === 'todo' && selected.size > 0;
  $$('[data-when=idle]').forEach(e => { e.hidden = bulk; });
  $$('[data-when=bulk]').forEach(e => { e.hidden = !bulk; });
  $('#bulk-count').textContent = `已选 ${selected.size} 张`;
  const table = $('#table'), empty = $('#empty');
  table.hidden = !list.length;
  empty.hidden = Boolean(list.length);
  if (!list.length) {
    empty.innerHTML = tab === 'todo' ? '<strong>没有待审批的费用申请</strong><p>新的审批到达时会出现在这里，也会发通知。</p>' : '<strong>还没有处理过的费用申请</strong><p>通过或退回的费用申请会出现在这里。</p>';
    table.innerHTML = '';
    return;
  }
  const check = tab === 'todo';
  // Single-line rows (rules/4-页面.md 4.3): the header row stays for screen readers only.
  const head = `<thead><tr>${check ? '<th scope="col" class="wb-check"><span class="wb-sr-only">选择</span></th>' : ''}<th scope="col">单号</th><th scope="col">费用申请</th><th scope="col">申请部门</th><th scope="col">申请金额（元）</th><th scope="col">提交时间</th><th scope="col">提交人</th><th scope="col">${check ? '处理' : '结果'}</th></tr></thead>`;
  const body = list.map(r => `<tr data-id="${r.id}"${selected.has(r.id) ? ' data-selected' : ''}>`
    + (check ? `<td class="wb-check"><label class="wb-check-hit"><input type="checkbox" data-select="${r.id}"${selected.has(r.id) ? ' checked' : ''} aria-label="选择 ${esc(r.name)}"></label></td>` : '')
    + `<td class="wb-cell-meta">${esc(r.code)}</td><td class="wb-cell-name"><a class="wb-row-link" href="document.html">${esc(r.name)}</a></td><td class="wb-cell-meta">${esc(r.dept)}</td><td class="number">${money(r.cents)}</td><td class="number wb-cell-meta">${esc(r.at)}</td><td class="wb-cell-end">${personHTML(r.by, { compact: true })}</td>`
    + (check ? `<td><div class="wb-row-buttons">${r.wait ? `<span class="wb-row-note">${esc(r.wait)}</span>` : ''}<button type="button" class="wb-btn sm" data-approve="${r.id}"${r.wait ? ' disabled' : ''}>通过</button><button type="button" class="wb-btn sm" data-return="${r.id}">退回</button></div></td>`
      : `<td><span class="wb-status" data-tone="${r.result === 'approved' ? 'success' : 'warning'}"><b></b><span>${r.result === 'approved' ? '已通过' : `已退回：${esc(r.reason)}`}</span></span></td>`)
    + '</tr>').join('');
  // Fixed columns plus 240px for the name; table-layout:fixed would otherwise squeeze the name column to 0 on narrow screens.
  table.style.minWidth = `calc(${check ? 'var(--wb-check-col) + ' : ''}${152 + 184 + 120 + 104 + 44 + (check ? 340 : 240) + 240}px)`;
  table.innerHTML = `<colgroup>${check ? '<col style="width:var(--wb-check-col)">' : ''}<col style="width:152px"><col><col style="width:184px"><col style="width:120px"><col style="width:104px"><col style="width:44px"><col style="width:${check ? 340 : 240}px"></colgroup>${head}<tbody>${body}</tbody>`;
  const all = $('[data-select-all]');
  if (all) { const n = list.filter(r => selected.has(r.id)).length; all.checked = n > 0 && n === list.length; all.indeterminate = n > 0 && n < list.length; }
}

function decide(ids, result, reason = '') {
  const before = rows;
  rows = rows.map(r => (ids.includes(r.id) ? { ...r, result, reason } : r));
  ids.forEach(id => selected.delete(id));
  render();
  const one = ids.length === 1 ? before.find(r => r.id === ids[0]) : null;
  const what = result === 'approved' ? '通过' : '退回';
  toast(one ? `已${what} ${one.name}` : `已${what} ${ids.length} 张费用申请`, { action: { label: '撤销', run: () => { rows = rows.map(r => (ids.includes(r.id) ? before.find(b => b.id === r.id) : r)); render(); } } });
}
function approveSelected(trigger) {
  const picked = todo().filter(r => selected.has(r.id)), blocked = picked.filter(r => r.wait), ok = picked.filter(r => !r.wait);
  if (!blocked.length) { decide(ok.map(r => r.id), 'approved'); return; }
  if (!ok.length) {
    openConfirm({ root, returnFocus: trigger, title: '选中的费用申请都不能通过', text: `${blocked.length} 张都在等财务负责人加签，加签完成后再审批。`, confirm: '取消勾选', cancel: '关闭', onConfirm: () => { selected.clear(); render(); } });
    return;
  }
  openConfirm({
    root, returnFocus: trigger, confirm: `通过 ${ok.length} 张`,
    title: `通过其余 ${ok.length} 张费用申请？`,
    text: `选中的 ${picked.length} 张里有 ${blocked.length} 张在等财务负责人加签，不能通过：${blocked.map(r => r.code).join('、')}。`,
    onConfirm: () => decide(ok.map(r => r.id), 'approved'),
  });
}

root.addEventListener('change', e => {
  const t = e.target;
  if ('select' in t.dataset) { const id = Number(t.dataset.select); t.checked ? selected.add(id) : selected.delete(id); render(); }
  else if ('selectAll' in t.dataset) { const ids = todo().map(r => r.id), all = ids.every(id => selected.has(id)); ids.forEach(id => (all ? selected.delete(id) : selected.add(id))); render(); }
});
root.addEventListener('click', e => {
  const b = e.target.closest('button');
  if (!b) return;
  if (b.dataset.tab) { tab = b.dataset.tab; selected.clear(); render(); }
  else if (b.dataset.approve) decide([Number(b.dataset.approve)], 'approved');
  else if (b.dataset.return) {
    const r = rows.find(x => x.id === Number(b.dataset.return));
    openConfirm({ root, returnFocus: b, title: `退回 ${r.name}？`, text: '退回后提交人修改再重新提交。原因会写进费用申请的提示条和变更记录。', confirm: '退回', reason: { label: '退回原因' }, onConfirm: reason => decide([r.id], 'returned', reason) });
  } else if (b.dataset.action === 'approve-selected') approveSelected(b);
  else if (b.dataset.action === 'clear-selection') { selected.clear(); render(); }
});

initShell(root);
render();

// Command palette (rules/7-键盘与命令.md 7.2): every button on the page is also a command here.
const rowOf = () => { const tr = document.activeElement?.closest?.('tr[data-id]'); return tr ? rows.find(r => r.id === Number(tr.dataset.id)) : null; };
const account = initAccount(root, { onShortcuts: () => palette.showShortcuts() });
const palette = initPalette({
  root,
  shell: true,
  accountItems: () => account.commands(),
  context: () => { const r = rowOf(); return r && !r.result ? { id: r.id, code: r.code, label: r.name } : null; },
  groups: ctx => [
    ...(ctx ? [{ heading: '当前费用申请', items: [
      ...(rows.find(r => r.id === ctx.id).wait ? [] : [{ id: 'approve', label: '通过', icon: 'success', run: c => decide([c.id], 'approved') }]),
      { id: 'return', label: '退回…', icon: 'close', run: c => root.querySelector(`[data-return="${c.id}"]`)?.click() },
      { id: 'open', label: '打开费用申请', icon: 'external', run: () => { location.href = 'document.html'; } },
    ] }] : []),
    ...(tab === 'todo' && selected.size ? [{ heading: `勾选的 ${selected.size} 张`, items: [
      { id: 'approve-selected', label: '通过勾选的费用申请', icon: 'success', run: () => approveSelected($('[data-action="approve-selected"]')) },
      { id: 'clear-selection', label: '清除选择', icon: 'close', run: () => { selected.clear(); render(); } },
    ] }] : []),
    { heading: '视图', items: [
      { id: 'tab-todo', label: '待我审批', icon: 'success', run: () => { tab = 'todo'; selected.clear(); render(); } },
      { id: 'tab-done', label: '我已处理', icon: 'check', run: () => { tab = 'done'; selected.clear(); render(); } },
    ] },
  ],
});
