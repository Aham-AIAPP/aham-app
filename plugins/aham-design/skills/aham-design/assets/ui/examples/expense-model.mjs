// Expense request used by the document, print and worklist samples. Demonstration data only.
// Amounts are integer cents. Each line has a standard unit price; a price above it is allowed but asks for one more
// approval step (rules/5-单据.md 5.9).
const data = [
  ['外部培训课程', 'TR-001 · 质量工具两日课程', 6, '人', 2800, 2800, 'training'],
  ['内部讲师课时费', 'TR-006 · 新员工入职培训', 8, '课时', 500, 500, 'training'],
  ['培训教材', 'TR-012 · 印刷与装订', 30, '套', 85, 90, 'training'],
  ['培训场地租用', 'TR-018 · 两天，含设备', 2, '天', 3200, 3500, 'training'],
  ['往返交通', 'TV-001 · 高铁二等座', 12, '张', 620, 650, 'travel'],
  ['住宿', 'TV-006 · 协议酒店标准间', 10, '间夜', 460, 480, 'travel'],
  ['市内交通', 'TV-012 · 出租车与网约车', 1, '项', 1200, 1200, 'travel'],
  ['餐费补助', 'TV-018 · 按出差天数', 20, '人天', 100, 100, 'travel'],
];
export const defaults = () => data.map(([name, code, qty, unit, price, std, type], id) => ({ id, name, code, qty, unit, priceCents: price * 100, stdCents: std * 100, type }));
export const TYPES = { training: '培训费', travel: '差旅费' };

export function validRow(x) {
  return Number.isInteger(x.qty) && x.qty >= 0 && x.qty <= 999 && Number.isSafeInteger(x.priceCents) && x.priceCents >= 0 && x.priceCents <= 1e9;
}
export function lineCents(x) {
  if (!validRow(x)) throw new RangeError('Invalid expense row');
  return x.qty * x.priceCents;
}
export const overStandard = x => x.priceCents > x.stdCents;
// Total, the total per expense type, and a two-step payment schedule: 50% in advance, the rest after use.
// The second payment takes whatever the first one rounded away, so the two always add up to the total.
export function totals(rows) {
  let total = 0;
  const byType = Object.fromEntries(Object.keys(TYPES).map(k => [k, 0]));
  for (const row of rows) { const a = lineCents(row); total += a; byType[row.type] += a; }
  const first = Math.round(total / 2);
  return { total, byType, payments: [first, total - first] };
}
// A line priced above its standard adds the finance step to the approval.
export const needsCosign = rows => rows.some(overStandard);
