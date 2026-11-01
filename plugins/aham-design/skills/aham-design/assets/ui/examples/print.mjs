// Print preview of the expense request. Reads the copy document.mjs keeps in sessionStorage; without it, prints the sample.
import { initTheme, initTooltips, escapeHtml as esc } from '../aham.js';
import { defaults, lineCents, totals, validRow, TYPES } from './expense-model.mjs';
import { money, chineseAmount } from './format.mjs';

const root = document.querySelector('.aham-workbench');
const sample = {
  status: 'draft',
  fields: { dept: '质量部', project: '质量工具培训', payee: '', owner: '林悦 · 质量部', applyDate: '2026-09-30', useBy: '2026-12-31', currency: '人民币 CNY', tax: '含税', method: '对公转账', site: '一号厂区培训室', period: '2026-11-03 至 2026-11-14', payment: '50% 预付 / 50% 结束后结清' },
  rows: defaults(),
};
function load() {
  try {
    const saved = JSON.parse(sessionStorage.getItem('aham-expense'));
    if (!saved?.fields || !Array.isArray(saved.rows)) return sample;
    // Saved rows are data from storage: keep them only when every field has the expected type.
    const ok = r => typeof r?.name === 'string' && typeof r.code === 'string' && typeof r.unit === 'string' && Number.isSafeInteger(r.stdCents) && TYPES[r.type] && validRow(r);
    return saved.rows.length && saved.rows.every(ok) ? saved : sample;
  } catch { return sample; }
}

const q = load(), f = q.fields, t = totals(q.rows);
const MARK = { draft: '草稿 · 未生效', review: '审批中 · 未生效', returned: '已退回 · 未生效', voided: '已作废' };
const mark = MARK[q.status];
document.querySelector('#print-note').textContent = mark ? `这张单据的状态是「${mark.split(' · ')[0]}」，打印件会带「${mark}」标记` : '';

document.querySelector('#sheet').innerHTML = `
  <header class="wb-sheet-head">
    <div><h1>费用申请单</h1><p>示例科技有限公司</p></div>
    <div>${mark ? `<span class="wb-sheet-mark">${esc(mark)}</span>` : ''}</div>
  </header>
  <dl>
    <dt>申请单号</dt><dd>FY-20260930-018</dd><dt>申请日期</dt><dd>${esc(f.applyDate)}</dd>
    <dt>申请部门</dt><dd>${esc(f.dept)}</dd><dt>使用截止</dt><dd>${esc(f.useBy)}</dd>
    <dt>收款方</dt><dd>${esc(f.payee || '未填写')}</dd><dt>币种</dt><dd>${esc(f.currency)}，${esc(f.tax)}</dd>
    <dt>申请人</dt><dd>${esc(f.owner)}</dd><dt>关联项目</dt><dd>${esc(f.project)}</dd>
  </dl>
  <h2>费用明细</h2>
  <table class="wb-table">
    <colgroup><col style="width:28px"><col><col style="width:64px"><col style="width:44px"><col style="width:36px"><col style="width:76px"><col style="width:76px"><col style="width:96px"></colgroup>
    <thead><tr><th>#</th><th>费用项目</th><th>编码</th><th class="number">数量</th><th>单位</th><th class="number">标准单价</th><th class="number">单价</th><th class="number">金额</th></tr></thead>
    <tbody>${q.rows.map((r, i) => `<tr><td>${i + 1}</td><td>${esc(r.name)}</td><td class="wb-meta">${esc(r.code.split(' · ')[0])}</td><td class="number">${r.qty}</td><td>${esc(r.unit)}</td><td class="number">${money(r.stdCents)}</td><td class="number">${money(r.priceCents)}</td><td class="number">${money(lineCents(r))}</td></tr>`).join('')}</tbody>
    <tfoot><tr><td colspan="7">合计</td><td class="number">${money(t.total)}</td></tr></tfoot>
  </table>
  <div class="wb-sheet-total"><span>${Object.entries(TYPES).map(([k, l]) => `${l} ${money(t.byType[k])}`).join('，')}</span><strong>申请金额 ¥${money(t.total)}</strong><span>大写：${chineseAmount(t.total)}</span></div>
  <h2>费用说明</h2>
  <dl>
    <dt>支付方式</dt><dd>${esc(f.method)}</dd><dt>使用地点</dt><dd>${esc(f.site)}</dd>
    <dt>使用期间</dt><dd>${esc(f.period)}</dd><dt>付款安排</dt><dd>${esc(f.payment)}</dd>
  </dl>
  <div class="wb-sheet-sign"><div>申请人（签字）</div><div>审批人（签字）</div></div>`;

initTheme(root);
initTooltips(root);
document.querySelector('#print-go').addEventListener('click', () => print());
