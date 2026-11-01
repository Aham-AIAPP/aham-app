import {test} from 'node:test';
import assert from 'node:assert/strict';
import {arrange,makeProjects,applyFilters,applyView,applySearch,sortRows,groupRows,paginate,encodeState,decodeState,normalizeDisplay,displayChanged,DEFAULT_DISPLAY,STATUSES,ME,weekStart,money} from '../examples/list-model.mjs';

const rows = makeProjects();

test('fixture is deterministic, 128 rows, unique codes and names', () => {
  assert.equal(rows.length, 128);
  assert.deepEqual(makeProjects(), rows);
  assert.equal(new Set(rows.map(r => r.code)).size, 128);
  assert.equal(new Set(rows.map(r => r.name)).size, 128);
  assert.ok(rows.every(r => STATUSES.includes(r.status)));
  assert.ok(rows.every(r => r.updated >= r.created), 'last update never precedes creation');
});

test('filters by type narrow correctly; incomplete filters do not narrow', () => {
  const signed = applyFilters(rows, [{ field: 'status', op: 'is', values: ['已完成'] }]);
  assert.ok(signed.length > 0 && signed.every(r => r.status === '已完成'));
  const notSigned = applyFilters(rows, [{ field: 'status', op: 'isNot', values: ['已完成'] }]);
  assert.equal(signed.length + notSigned.length, rows.length);
  const two = applyFilters(rows, [{ field: 'owner', op: 'anyOf', values: ['林悦', '周航'] }]);
  assert.ok(two.every(r => ['林悦', '周航'].includes(r.owner)));
  const big = applyFilters(rows, [{ field: 'budgetCents', op: 'gte', values: [100000000] }]);
  assert.ok(big.every(r => r.budgetCents !== null && r.budgetCents >= 100000000));
  const range = applyFilters(rows, [{ field: 'updated', op: 'between', values: ['2026-09-20', '2026-09-30'] }]);
  assert.ok(range.every(r => r.updated >= '2026-09-20' && r.updated <= '2026-09-30'));
  const text = applyFilters(rows, [{ field: 'name', op: 'contains', values: ['东湖'] }]);
  assert.ok(text.length > 0 && text.every(r => r.name.includes('东湖')));
  assert.equal(applyFilters(rows, [{ field: 'status', op: 'is', values: [] }]).length, rows.length);
});

test('views and search', () => {
  assert.ok(applyView(rows, 'mine').every(r => r.owner === ME));
  assert.equal(weekStart('2026-09-30'), '2026-09-28');
  assert.ok(applyView(rows, 'week').every(r => r.created >= '2026-09-28'));
  assert.ok(applySearch(rows, 'prj-2026-0001').length === 1);
});

test('sorting is stable, empty amounts last in both directions, names by pinyin', () => {
  for (const dir of ['asc', 'desc']) {
    const s = sortRows(rows, { field: 'budgetCents', dir });
    const firstNull = s.findIndex(r => r.budgetCents === null);
    assert.ok(s.slice(firstNull).every(r => r.budgetCents === null));
  }
  const byName = sortRows(rows, { field: 'name', dir: 'asc' }).map(r => r.name);
  assert.equal(byName[0].slice(0, 2), '安澜');
  const byStage = sortRows(rows, { field: 'status', dir: 'asc' });
  assert.ok(byStage.every((r, i, a) => i === 0 || STATUSES.indexOf(a[i - 1].status) <= STATUSES.indexOf(r.status)));
});

test('grouping keeps option order and omits empty groups; pagination clamps', () => {
  const groups = groupRows(applyFilters(rows, [{ field: 'status', op: 'anyOf', values: ['已完成', '未开始'] }]), 'status');
  assert.deepEqual(groups.map(g => g.key), ['未开始', '已完成']);
  assert.deepEqual(groupRows(rows, null)[0].rows, rows);
  const p = paginate(rows, 99, 50);
  assert.deepEqual([p.page, p.pages, p.from, p.to, p.rows.length], [3, 3, 101, 128, 28]);
  assert.deepEqual([paginate([], 1, 20).from, paginate([], 1, 20).to], [0, 0]);
});

test('URL state round-trips and drops anything malformed or unknown', () => {
  const state = { view: 'mine', q: '东湖', filters: [{ field: 'status', op: 'anyOf', values: ['进行中', '已完成'] }], page: 2 };
  const back = decodeState(encodeState(state));
  assert.deepEqual({ view: back.view, q: back.q, filters: back.filters, page: back.page }, state);
  assert.equal(decodeState('f=not-json').dropped, 1);
  const bad = decodeState('f=' + encodeURIComponent(JSON.stringify([['status', 'is', ['不存在']], ['secret', 'is', ['x']], ['budgetCents', 'gte', [-5]], ['owner', 'is', ['许宁']]])));
  assert.equal(bad.dropped, 3);
  assert.deepEqual(bad.filters, [{ field: 'owner', op: 'is', values: ['许宁'] }]);
  assert.equal(decodeState('view=admin&page=-1').view, 'all');
  assert.equal(decodeState('page=0').page, 1);
});

test('display options normalize stored data and report changes', () => {
  assert.equal(displayChanged(null), false);
  assert.equal(displayChanged({ ...DEFAULT_DISPLAY, density: 'compact' }), true);
  const odd = normalizeDisplay({ group: 'hack', density: 'tiny', columns: [['status', false], ['status', true], ['bogus', true]] });
  assert.equal(odd.group, 'status');
  assert.equal(odd.density, 'standard');
  assert.deepEqual(odd.columns[0], ['status', false]);
  assert.equal(odd.columns.length, DEFAULT_DISPLAY.columns.length);
  assert.equal(normalizeDisplay({ group: null }).group, null);
  assert.equal(normalizeDisplay({ pageSize: 7 }).pageSize, 50);
  assert.equal(normalizeDisplay({ pageSize: 100 }).pageSize, 100);
});

test('money formats cents without floating point', () => {
  assert.equal(money(78080000), '780,800.00');
  assert.equal(money(5), '0.05');
  assert.equal(money(null), '–');
});

test('grouped rows stay contiguous and keep the sort inside each group', () => {
  const out = arrange(rows, { group: 'status', sort: { field: 'updated', dir: 'desc' } });
  const order = out.map(r => STATUSES.indexOf(r.status));
  assert.ok(order.every((v, i) => i === 0 || order[i - 1] <= v), 'groups contiguous in option order');
  for (const s of STATUSES) {
    const g = out.filter(r => r.status === s).map(r => r.updated);
    assert.ok(g.every((v, i) => i === 0 || g[i - 1] >= v), `${s} sorted by updated desc`);
  }
  assert.deepEqual(arrange(rows, { group: null, sort: { field: 'name', dir: 'asc' } }), sortRows(rows, { field: 'name', dir: 'asc' }));
});
