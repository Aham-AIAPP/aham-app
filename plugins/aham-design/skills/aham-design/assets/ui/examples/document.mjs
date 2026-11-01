// Expense request (rules/5-单据.md). One page for read and edit mode, with the status deciding which actions show.
// Display mode keeps its actions in the head; edit mode moves 放弃草稿 and 保存 into the footer toolbar, as in SAP Fiori.
//   草稿 / 已退回  编辑、提交审批；更多：复制为新申请、删除
//   审批中        提交人：撤回。审批人：通过、退回（页眉的「提交人 / 审批人」切换只用于演示）
//   已生效        更多：复制为新申请、作废
//   已作废        只能查看、打印和复制
// State lives in this page only. print.html reads the last saved copy from sessionStorage.
import { initShell, initPalette, initObjectPage, initAnchorBar, openConfirm, openFormDialog, openPopover, closePopover, createCommand, toast, icon, escapeHtml as esc } from '../aham.js';
import { defaults, lineCents, totals, overStandard, needsCosign } from './expense-model.mjs';
import { money } from './format.mjs';
import {initAccount} from './account.mjs';

const root = document.querySelector('.aham-workbench');
const doc = root.querySelector('#doc');
const $ = s => root.querySelector(s), $$ = s => [...root.querySelectorAll(s)];

const STATUS = {
  draft: { label: '草稿', tone: 'draft' },
  review: { label: '审批中', tone: 'info' },
  returned: { label: '已退回', tone: 'warning' },
  approved: { label: '已生效', tone: 'success' },
  voided: { label: '已作废', tone: '' },
};
const PASSED = ['approved', 'voided'];
const EDITABLE = ['draft', 'returned'];
const NO = 'FY-20260930-018';

// Field definitions. `fixed` values are set by the system and stay as text in edit mode.
const FIELDS = {
  basic: [
    { key: 'dept', label: '申请部门', required: true, type: 'select', options: ['质量部', '生产部', '信息部'] },
    { key: 'project', label: '关联项目', required: true, type: 'select', options: ['质量工具培训', '新员工入职培训'] },
    // Payees come from the supplier list, so the value links to a real record (rules/3-控件.md 3.6).
    { key: 'payee', label: '收款方', required: true, type: 'select', placeholder: '选择收款方', options: ['示例培训中心', '示例差旅服务', '员工个人'] },
    { key: 'owner', label: '申请人', fixed: true },
    { key: 'applyDate', label: '申请日期', required: true, type: 'date' },
    { key: 'useBy', label: '使用截止', required: true, type: 'date' },
    { key: 'currency', label: '币种', type: 'select', options: ['人民币 CNY', '美元 USD'] },
    { key: 'tax', label: '金额口径', type: 'radio', options: ['含税', '不含税'] },
  ],
  terms: [
    { key: 'method', label: '支付方式', type: 'select', options: ['对公转账', '员工报销'] },
    { key: 'site', label: '使用地点' },
    { key: 'period', label: '使用期间' },
    { key: 'payment', label: '付款安排', fixed: true },
    { key: 'note', label: '内部备注', type: 'textarea', full: true, hint: '只在团队内可见，不打印' },
  ],
};

const state = {
  status: 'draft',
  fields: {
    dept: '质量部', project: '质量工具培训', payee: '', owner: '林悦 · 质量部',
    applyDate: '2026-09-30', useBy: '2026-12-31', currency: '人民币 CNY', tax: '含税',
    method: '对公转账', site: '一号厂区培训室', period: '2026-11-03 至 2026-11-14', payment: '50% 预付 / 50% 结束后结清',
    note: '培训名单以部门确认表为准。',
  },
  rows: defaults(),
  returnReason: '', voidReason: '',
  history: [{ who: '林悦', what: '创建费用申请', when: '09-29 16:20' }],
};

// Lines that can be added in edit mode (demonstration catalogue).
const CATALOG = [
  { name: '在线课程账号', code: 'TR-030 · 一年期', unit: '个', priceCents: 600_00, stdCents: 600_00, type: 'training' },
  { name: '考试报名费', code: 'TR-036 · 资格认证', unit: '人', priceCents: 900_00, stdCents: 900_00, type: 'training' },
  { name: '会务服务', code: 'TV-030 · 场地与茶歇', unit: '天', priceCents: 1_500_00, stdCents: 1_500_00, type: 'travel' },
];
// Rows on screen: the saved rows in read mode, a working copy in edit mode (lines can be added and removed).
let work = state.rows, nextId = 100;

const now = () => new Date().toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit' });
// Demonstration only: a product decides the role from the signed-in user (rules/5-单据.md 5.9).
let role = 'owner';
const approver = () => role === 'approver';
const canEdit = () => !approver() && EDITABLE.includes(state.status);

// ── Form rows ────────────────────────────────────────────────────────────────
// Markup of one editable row:
//   <div class="wb-form-row">
//     <div class="wb-form-label" id="l-…">申请部门<span class="wb-form-required">*</span></div>
//     <div class="wb-form-value" tabindex="0" aria-labelledby="l-…">
//       <span class="wb-read"><span class="wb-value">…</span></span>
//       <span class="wb-edit"><select class="wb-field" name="…" required>…</select></span>
//     </div>
//   </div>
function control(f) {
  const v = state.fields[f.key], attrs = `name="${f.key}" aria-labelledby="l-${f.key}"${f.required ? ' required' : ''}`;
  if (f.type === 'select') return `<select class="wb-field" ${attrs}>${f.placeholder ? `<option value=""${v ? '' : ' selected'}>${esc(f.placeholder)}</option>` : ''}${f.options.map(o => `<option${o === v ? ' selected' : ''}>${esc(o)}</option>`).join('')}</select>`;
  if (f.type === 'radio') return `<span class="wb-choices" role="radiogroup" aria-labelledby="l-${f.key}">${f.options.map(o => `<label class="wb-choice"><input type="radio" name="${f.key}" value="${esc(o)}"${o === v ? ' checked' : ''}>${esc(o)}</label>`).join('')}</span>`;
  if (f.type === 'textarea') return `<textarea class="wb-field" rows="1" maxlength="500" ${attrs}>${esc(v)}</textarea>`;
  if (f.type === 'date') return `<input class="wb-field wb-tnum" type="date" ${attrs} value="${esc(v)}">`;
  return `<input class="wb-field" maxlength="200" ${attrs} value="${esc(v)}">`;
}
function readValue(f) {
  const v = state.fields[f.key];
  // Empty values are written by type (rules/10-数据格式.md 10.5); a required one takes the error colour.
  const word = f.type === 'select' || f.type === 'radio' ? '未选择' : f.type === 'date' ? '–' : '未填写';
  if (!v) return `<span class="wb-value ${f.required ? 'is-missing' : 'is-empty'}">${word}</span>`;
  return `<span class="wb-value${canEdit() ? ' is-editable' : ''}">${esc(v)}</span>`;
}
function formRow(f) {
  const label = `<div class="wb-form-label" id="l-${f.key}">${esc(f.label)}${f.required ? '<span class="wb-form-required" aria-hidden="true">*</span>' : ''}</div>`;
  const hint = f.hint ? `<div class="wb-form-hint" data-edit-only>${esc(f.hint)}</div>` : '';
  const value = f.fixed
    ? `<div class="wb-form-value"><span class="wb-value">${esc(state.fields[f.key])}</span></div>`
    : `<div class="wb-form-value" tabindex="0" aria-labelledby="l-${f.key}"><span class="wb-read">${readValue(f)}</span><span class="wb-edit">${control(f)}</span></div>`;
  return `<div class="wb-form-row${f.full ? ' is-full' : ''}">${label}${value}${hint}</div>`;
}
function renderForms() {
  $('#f-basic').innerHTML = FIELDS.basic.map(formRow).join('');
  $('#f-terms').innerHTML = FIELDS.terms.map(formRow).join('');
}

// ── Line items: quantity and unit price are editable, the amount follows them ──
function lineRow(r, i) {
  const editable = canEdit() ? ' is-editable' : '';
  return `<tr data-id="${r.id}"><td class="wb-tnum wb-meta">${i + 1}</td><td>${esc(r.name)}</td><td class="wb-meta">${esc(r.code.split(' · ')[0])}</td>`
    + `<td class="number"><span class="wb-read"><span class="wb-value${editable}">${r.qty}</span></span><span class="wb-edit"><input class="wb-field is-number" name="qty-${r.id}" aria-label="第 ${i + 1} 行 ${esc(r.name)} 数量" inputmode="numeric" value="${r.qty}"></span></td>`
    + `<td>${esc(r.unit)}</td><td class="number">${money(r.stdCents)}</td>`
    + `<td class="number"><span class="wb-read"><span class="wb-value${editable}">${money(r.priceCents)}</span></span><span class="wb-edit"><input class="wb-field is-number" name="price-${r.id}" aria-label="第 ${i + 1} 行 ${esc(r.name)} 单价" inputmode="decimal" value="${(r.priceCents / 100).toFixed(2)}"></span></td>`
    + `<td class="number" data-amount>${money(lineCents(r))}</td>`
    + `<td class="wb-row-actions" data-edit-only><button type="button" class="wb-icon-btn" data-remove="${r.id}" aria-label="删除第 ${i + 1} 行 ${esc(r.name)}" data-tooltip="删除这一行">${icon('trash')}</button></td></tr>`;
}
function renderLines() {
  $('#lines').innerHTML = work.map(lineRow).join('');
  renderLineMeta();
  renderTotals(work);
}
const renderLineMeta = () => { $('#lines-meta').textContent = `${work.length} 项 · 金额单位：元`; };
// After a line is added or removed in edit mode: renumber, recount and total again without touching typed values.
function relines() {
  $$('#lines tr').forEach((tr, i) => { tr.firstElementChild.textContent = i + 1; });
  renderLineMeta();
  const rows = typedRows();
  renderTotals(rows.map((r, i) => r || work[i]));
}
function renderTotals(rows) {
  const t = totals(rows);
  renderFacts(t.total);
  $('#lines-total').textContent = money(t.total);
  $('#sum-total').textContent = money(t.total);
  $('#sum-training').textContent = money(t.byType.training);
  $('#sum-travel').textContent = money(t.byType.travel);
  t.payments.forEach((p, i) => { $(`#pay-${i + 1}`).textContent = money(p); });
}

// Rows as typed in edit mode; null when a value cannot be read yet (the amount then keeps its last value).
const parseQty = v => (/^\d+$/.test(v.trim()) && Number(v) <= 999 ? Number(v) : null);
// Unit price in yuan with at most two decimals, stored as integer cents.
const parsePrice = v => (/^\d{1,7}(\.\d{1,2})?$/.test(v.trim()) ? Math.round(Number(v) * 100) : null);
function typedRows() {
  return work.map(r => {
    const qty = parseQty(doc.querySelector(`[name=qty-${r.id}]`).value), price = parsePrice(doc.querySelector(`[name=price-${r.id}]`).value);
    return qty === null || price === null ? null : { ...r, qty, priceCents: price };
  });
}
doc.addEventListener('input', e => {
  if (!e.target.matches('[name^=qty-], [name^=price-]')) return;
  const rows = typedRows();
  rows.forEach((r, i) => { if (r) doc.querySelector(`tr[data-id="${work[i].id}"] [data-amount]`).textContent = money(lineCents(r)); });
  renderTotals(rows.map((r, i) => r || work[i]));
});

// ── Key facts in the head: four read-only pairs that fold away when the page scrolls ─────────
function renderFacts(totalCents) {
  const f = state.fields;
  $('#doc-facts').innerHTML = [['申请部门', esc(f.dept || '–')], ['申请金额（元）', money(totalCents), 'is-amount'], ['使用截止', esc(f.useBy || '–')], ['申请人', esc(f.owner)]]
    .map(([k, v, c]) => `<div><dt>${k}</dt><dd${c ? ` class="${c}"` : ''}>${v}</dd></div>`).join('');
}

// ── Status: badge, message strip, actions, approval, history ─────
function renderStatus() {
  const s = STATUS[state.status];
  const badge = $('#doc-status');
  badge.dataset.tone = s.tone;
  badge.lastElementChild.textContent = s.label;
  const last = state.history[0];
  $('#doc-updated').textContent = `${last.who} · ${last.when}`;

  const strip = $('#doc-strip');
  const set = (tone, iconName, html) => { strip.hidden = false; strip.dataset.tone = tone; strip.innerHTML = `${icon(iconName)}<span class="wb-grow">${html}</span>`; };
  strip.hidden = true;
  // The next-step line says who the page waits for; the strip says whether the document can change (rules/5-单据.md 5.8).
  const next = $('#doc-next');
  const missing = [...FIELDS.basic, ...FIELDS.terms].filter(f => f.required && !state.fields[f.key]);
  const due = (() => { const d = new Date(Date.now() + 2 * 864e5); return `计划 ${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`; })();
  const nextLine = approver() ? (state.status === 'review' ? ['等你', '审批', due] : null) : {
    draft: missing.length ? ['等你', `补齐${missing.map(f => esc(f.label)).join('、')}后提交审批`, ''] : ['等你', '提交审批', ''],
    review: ['等王卓', '审批', due],
    returned: ['等你', '按退回意见修改后重新提交', ''],
  }[state.status];
  next.hidden = !nextLine;
  // Waiting on someone else: 提醒 once a day, then the time it was sent (rules/6-反馈.md 6.11).
  const remind = state.status === 'review' && !approver()
    ? (state.remindedAt ? `<span class="wb-meta">已提醒 · ${state.remindedAt}</span>` : '<button type="button" class="wb-btn sm" id="doc-remind">提醒</button>') : '';
  if (nextLine) next.innerHTML = `<span class="wb-status" data-tone="wait"><b></b></span><span class="wb-grow"><strong>${nextLine[0]}</strong>${nextLine[1]}</span>${nextLine[2] ? `<span class="wb-next-date">${nextLine[2]}</span>` : ''}${remind}`;

  if (state.status === 'review' && !approver()) set('info', 'info', '审批期间不能修改，需要改动时先撤回。');
  if (state.status === 'returned') set('warning', 'warning', `王卓退回：${esc(state.returnReason)}。修改后重新提交。`);
  if (state.status === 'approved') set('success', 'success', '已生效，不能修改。条件变化时复制为新申请。');
  if (state.status === 'voided') set('', 'info', `已作废：${esc(state.voidReason)}。只能查看、打印和复制。`);

  // Approvers see 通过 and 退回 on a document under review and nothing that changes it otherwise (rules/5-单据.md 5.9).
  const reviewing = approver() && state.status === 'review';
  $('#doc-edit').hidden = !canEdit();
  $('#doc-submit').hidden = !canEdit() && !reviewing;
  $('#doc-submit').textContent = reviewing ? '通过' : state.status === 'returned' ? '重新提交' : '提交审批';
  $('#doc-return').hidden = !reviewing;
  $('#doc-withdraw').hidden = approver() || state.status !== 'review';
  $$('#doc-role button').forEach(b => b.setAttribute('aria-pressed', String(b.dataset.role === role)));

  // Each step names a person and what happened, never 待处理 or 处理中 (设计理念 原则 3).
  const passed = PASSED.includes(state.status) || (state.status === 'voided');
  const steps = [{ who: '林悦 · 提交', text: state.status === 'draft' ? '未提交' : '已提交', done: state.status !== 'draft' }];
  steps.push({ who: '王卓 · 部门负责人', done: passed,
    text: passed ? '已通过' : { review: '等王卓审批', returned: '已退回' }[state.status] || '未开始' });
  if (needsCosign(state.rows)) steps.push({ who: '财务负责人', done: passed, text: passed ? '已通过' : '未开始 · 单价高于标准价时加签' });
  $('#approval').innerHTML = steps.map(st => `<li class="${st.done ? 'done' : ''}"><span class="wb-step-dot"></span><div><strong>${esc(st.who)}</strong><small>${esc(st.text)}</small></div></li>`).join('');
  const first = state.history[state.history.length - 1];
  $('#history-sum').textContent = `${state.history.length} 条 · ${first.who}创建 · 最近 ${last.when}`;
  $('#history').innerHTML = state.history.map(h => `<p><strong>${esc(h.who)}</strong> ${esc(h.what)}</p><span>${esc(h.when)}</span>`).join('');
}
function setStatus(next, what) {
  state.status = next;
  state.remindedAt = '';
  renderForms();
  state.history.unshift({ who: next === 'approved' || next === 'returned' ? '王卓' : '林悦', what, when: `今天 ${now()}` });
  renderLines();
  renderStatus();
  publish();
}
// The print preview reads this copy.
function publish() {
  try { sessionStorage.setItem('aham-expense', JSON.stringify({ status: state.status, fields: state.fields, rows: state.rows.map(({ id, name, code, qty, unit, priceCents, stdCents, type }) => ({ id, name, code, qty, unit, priceCents, stdCents, type })) })); } catch { /* storage blocked: the preview shows the sample data */ }
}

// ── Edit, validate, save ─────────────────────────────────────────────────────
function validate() {
  const out = [];
  for (const c of doc.querySelectorAll('.wb-edit [required]')) if (!c.value.trim()) out.push({ control: c, severity: 'error', message: '必填，未填写' });
  const from = doc.querySelector('[name=applyDate]'), to = doc.querySelector('[name=useBy]');
  if (from.value && to.value && to.value < from.value) out.push({ control: to, severity: 'error', message: '要晚于申请日期' });
  for (const r of work) {
    const q = doc.querySelector(`[name=qty-${r.id}]`), p = doc.querySelector(`[name=price-${r.id}]`);
    if (parseQty(q.value) === null) out.push({ control: q, severity: 'error', message: '填 0～999 的整数' });
    const price = parsePrice(p.value);
    if (price === null) out.push({ control: p, severity: 'error', message: '填金额，最多两位小数' });
    else if (overStandard({ ...r, priceCents: price })) out.push({ control: p, severity: 'warning', message: `高于标准价 ${money(r.stdCents)}，提交后加一级财务负责人审批` });
  }
  return out;
}
async function save(values) {
  await new Promise(r => setTimeout(r, 300));
  for (const f of [...FIELDS.basic, ...FIELDS.terms]) if (!f.fixed && f.key in values) state.fields[f.key] = String(values[f.key]).trim();
  state.rows = typedRows();
  work = state.rows;
  state.history.unshift({ who: '林悦', what: '修改费用申请', when: `今天 ${now()}` });
  renderForms();
  renderLines();
  renderStatus();
  publish();
}

// Submitting checks the saved values. A required field left empty stops it: the page enters edit mode, marks each
// field, opens the message list and moves focus to the first one (rules/3-控件.md 3.3).
function submit() {
  const missing = [...FIELDS.basic, ...FIELDS.terms].filter(f => f.required && !state.fields[f.key]);
  if (missing.length) { page.check(); return; }
  setStatus('review', state.status === 'returned' ? '重新提交审批' : '提交审批');
  toast('已提交审批');
}

// ── More menu: copy, delete (draft only), void (released only) ─────────────
function menuItems() {
  const items = [{ id: 'copy', label: '复制为新申请', icon: 'copy', group: 0 }];
  if (canEdit()) items.push({ id: 'delete', label: '删除', icon: 'trash', danger: true, group: 1 });
  if (!approver() && state.status === 'approved') items.push({ id: 'void', label: '作废', icon: 'close', danger: true, group: 1 });
  return items;
}
function openMenu() {
  const pop = $('#doc-menu'), more = $('#doc-more');
  createCommand(pop.firstElementChild, {
    role: 'menu', search: false, label: '更多操作', items: menuItems(),
    onSelect: it => { closePopover('replace'); runMenuItem(it); },
  });
  openPopover(more, pop, { align: 'end' });
  pop.querySelector('[role=menu]').focus();
}
function runMenuItem(it) {
  const more = $('#doc-more');
  if (it.id === 'copy') toast('已复制为新申请 FY-20261017-001（示例：不会打开新单据）');
  if (it.id === 'delete') openConfirm({ root, title: `删除费用申请 ${NO}？`, text: '删除后不能恢复。已生效的申请请改用作废。', confirm: '删除', danger: true, returnFocus: more, onConfirm: removeDocument });
  if (it.id === 'void') openConfirm({ root, title: `作废费用申请 ${NO}？`, text: '作废后这笔费用不再支付，单据保留可查。', confirm: '作废', danger: true, reason: { label: '作废原因' }, returnFocus: more, onConfirm: reason => { state.voidReason = reason; setStatus('voided', '作废费用申请'); toast('已作废'); } });
}
function removeDocument() {
  doc.innerHTML = `<div class="wb-doc-body"><div class="wb-empty"><strong>费用申请 ${NO} 已删除</strong><p>删除的单据不进回收站。</p><a class="wb-btn" href="worklist.html">返回列表</a></div></div>`;
  root.querySelector('.wb-context').hidden = true;
  toast('已删除');
}

// ── Wiring ───────────────────────────────────────────────────────────────────
root.addEventListener('click', e => {
  const b = e.target.closest('button');
  if (!b) return;
  if (b.id === 'doc-submit') { if (approver()) { setStatus('approved', '审批通过'); toast('已通过'); } else submit(); }
  else if (b.id === 'doc-return') openConfirm({ root, title: `退回费用申请 ${NO}？`, text: '退回后林悦修改再重新提交。原因会写进提示条和变更记录。', confirm: '退回', reason: { label: '退回原因' }, returnFocus: b, onConfirm: reason => { state.returnReason = reason; setStatus('returned', '退回费用申请'); toast('已退回'); } });
  else if (b.id === 'doc-remind') { state.remindedAt = now(); state.history.unshift({ who: '林悦', what: '提醒王卓审批', when: `今天 ${state.remindedAt}` }); renderStatus(); toast('已提醒王卓，站内通知和企业微信各发一条'); $('#doc-next').focus?.(); }
  else if (b.dataset.role) setRole(b.dataset.role);
  else if (b.id === 'doc-more') openMenu();
  else if (b.id === 'doc-withdraw') openConfirm({ root, title: '撤回审批？', text: '撤回后费用申请回到草稿，可以继续修改，审批人那边的待办会取消。', confirm: '撤回', returnFocus: b, onConfirm: () => { setStatus('draft', '撤回审批'); toast('已撤回，费用申请回到草稿'); } });
  else if (b.id === 'line-add') addLine(b);
  else if (b.dataset.remove) removeLine(Number(b.dataset.remove));
});

function setRole(next) {
  role = next;
  if (doc.dataset.mode === 'edit' && approver()) page.cancel();
  renderForms();
  renderLines();
  renderStatus();
  toast(approver() ? '演示：现在是审批人王卓看到的页面' : '演示：现在是提交人林悦看到的页面');
}

// A line has three fields to fill, so it is added in a dialog (rules/5-单据.md 5.11); quantity and unit price stay
// editable in the table afterwards. Removing a line in edit mode asks nothing: 放弃草稿 brings it back.
function addLine(trigger) {
  openFormDialog({
    root, title: '添加费用明细', submit: '添加', returnFocus: trigger,
    fields: [
      { key: 'item', label: '费用项目', type: 'select', required: true, options: [{ value: '', label: '选择费用项目' }, ...CATALOG.map((c, i) => ({ value: String(i), label: `${c.code.split(' · ')[0]} · ${c.name}` }))] },
      { key: 'qty', label: '数量', type: 'number', inputmode: 'numeric', required: true, value: '1', hint: '0～999 的整数' },
      { key: 'price', label: '单价（元）', type: 'number', inputmode: 'decimal', hint: '不填时用标准价' },
    ],
    onSubmit: v => {
      const item = CATALOG[Number(v.item)], qty = parseQty(v.qty), price = v.price ? parsePrice(v.price) : item?.stdCents ?? null;
      const bad = {};
      if (qty === null) bad.qty = '填 0～999 的整数';
      if (price === null) bad.price = '填金额，最多两位小数';
      if (Object.keys(bad).length) return bad;
      const row = { id: nextId++, ...item, qty, priceCents: price };
      work = [...work, row];
      $('#lines').insertAdjacentHTML('beforeend', lineRow(row, work.length - 1));
      relines();
      toast(`已添加 ${row.name}`);
      return true;
    },
  });
}
function removeLine(id) {
  const i = work.findIndex(r => r.id === id), name = work[i].name;
  const next = $(`#lines tr[data-id="${id}"]`).nextElementSibling?.querySelector('[data-remove]') || $('#line-add');
  work = work.filter(r => r.id !== id);
  $(`#lines tr[data-id="${id}"]`).remove();
  relines();
  next.focus();
  toast(`已删除 ${name}，保存后生效`);
}

// Leaving the page with unsaved changes (rules/5-单据.md 5.7): save, keep the draft or discard it.
let keepDraft = false;
root.addEventListener('click', e => {
  const a = e.target.closest('a[href]');
  if (!a || a.target === '_blank' || !page.isDirty()) return;
  e.preventDefault();
  const go = () => { location.href = a.href; };
  openConfirm({
    root, title: '离开前保存费用申请？', text: '费用申请还在编辑中，有改动没有保存。保留草稿时，改动只有本人看得到，下次打开时继续编辑。',
    confirm: '保存', cancel: '留在本页', returnFocus: a,
    choices: [{ label: '放弃草稿', value: 'discard', danger: true }, { label: '保留草稿', value: 'keep' }],
    onConfirm: async () => { await page.save(); if (!page.isDirty()) go(); },
    onChoice: async v => {
      if (v === 'keep') { await page.saveDraft(); keepDraft = true; }
      page.discard();
      go();
    },
  });
});
// The sticky head gets its bottom line once the page scrolls under it.
// Key facts fold away at the same time, so the head is shorter while the user reads further down.
doc.addEventListener('scroll', () => doc.querySelector('.wb-doc-head')?.classList.toggle('is-stuck', doc.scrollTop > 24), { passive: true });
// Values that can be double-clicked into edit mode carry is-editable only while the status allows editing.
new MutationObserver(() => {
  if (doc.dataset.mode === 'edit') { work = [...state.rows]; return; }
  work = state.rows;
  renderLines();
}).observe(doc, { attributes: true, attributeFilter: ['data-mode'] });

renderForms();
renderLines();
renderStatus();
publish();
initShell(root);
const page = initObjectPage(doc, {
  edit: $('#doc-edit'), footer: $('#doc-foot'), messages: $('#doc-messages'),
  validate, onSave: save, canEdit, saved: '已保存',
  changed: () => work.length !== state.rows.length || work.some((r, i) => r.id !== state.rows[i].id),
  // Demonstration: the draft lives in this page only; a real product sends it to the server every 20 seconds.
  draft: { interval: 20000, onDraft: () => new Promise(r => setTimeout(r, 200)), onDiscard: ({ changed }) => { if (changed && !keepDraft) toast('已放弃草稿'); keepDraft = false; } },
});
initAnchorBar($('#doc-anchors'), { scroller: doc });

// Command palette (rules/7-键盘与命令.md 7.2): the buttons in the head and the footer are commands too,
// read when the palette opens so the list follows the mode (display, edit) and the status.
const pageButtons = () => [...root.querySelectorAll('#doc-actions button, #doc-foot button')]
  .filter(b => !b.disabled && b.offsetParent && (b.textContent.trim() || b.getAttribute('aria-label')))
  .map((b, i) => ({ id: `act-${i}`, label: b.textContent.trim() || b.getAttribute('aria-label'), keys: b.dataset.keys, run: () => b.click() }));
const account = initAccount(root, { onShortcuts: () => palette.showShortcuts() });
const palette = initPalette({
  root,
  shell: true,
  accountItems: () => account.commands(),
  groups: () => [
    { heading: '费用申请', items: [...pageButtons().filter(c => c.label !== '更多操作'), ...menuItems().map(it => ({ ...it, run: () => runMenuItem(it) }))] },
    { heading: '示例', items: [
      { id: 'role', label: approver() ? '切换到提交人视角' : '切换到审批人视角', icon: 'user', run: () => setRole(approver() ? 'owner' : 'approver') },
    ] },
  ],
});
