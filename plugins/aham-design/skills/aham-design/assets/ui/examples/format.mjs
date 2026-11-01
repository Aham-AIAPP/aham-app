// Number formats shared by the samples (rules/10-数据格式.md). Pure functions, no DOM.
// Amounts are integer cents, so sums never pick up floating-point error.

// Two decimals and thousands separators: 78080000 → 780,800.00.
export const money = cents => (cents / 100).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });

// Amount in Chinese capital numerals, as printed on documents and invoices: 94280000 → 玖拾肆万贰仟捌佰元整.
export function chineseAmount(cents) {
  if (!Number.isSafeInteger(cents) || cents < 0) throw new RangeError('Invalid amount');
  const D = '零壹贰叁肆伍陆柒捌玖', U = ['', '拾', '佰', '仟'], S = ['', '万', '亿', '万亿'];
  let yuan = Math.floor(cents / 100);
  const jiao = Math.floor(cents / 10) % 10, fen = cents % 10;
  let out = '';
  if (yuan > 0) {
    const groups = [];
    while (yuan > 0) { groups.push(yuan % 10000); yuan = Math.floor(yuan / 10000); }
    let gap = false;
    for (let i = groups.length - 1; i >= 0; i--) {
      const g = groups[i];
      if (g === 0) { gap = out !== ''; continue; }
      if (out !== '' && (gap || g < 1000)) out += '零';
      gap = false;
      let part = '', zero = false;
      for (let k = 3; k >= 0; k--) {
        const d = Math.floor(g / 10 ** k) % 10;
        if (d === 0) { zero = part !== ''; continue; }
        if (zero) { part += '零'; zero = false; }
        part += D[d] + U[k];
      }
      out += part + S[i];
    }
    out += '元';
  }
  if (!jiao && !fen) return (out || '零元') + '整';
  if (jiao) out += D[jiao] + '角'; else if (out) out += '零';
  return fen ? out + D[fen] + '分' : out + '整';
}
