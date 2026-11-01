// 逐像素比对两份截图目录里的同名 PNG，打印不同的图片、差异像素数和差异区域。
// scripts/compare_outputs.py 按字节比对 PNG；同一画面也可能编码成不同的字节，这个脚本只看解码后的像素。
// 运行：node qa/compare-shots.mjs [--max-pixels N] 目录A 目录B   （有图片不同、缺少或多出时退出码为 1）
// --max-pixels N：差异像素不超过 N 个的图片记为「噪声」，照样打印，但不算不同。默认 0。
// 这个容差只按像素个数算，不按色差算：改一个灰阶或描边色会改动成百上千个像素，几个像素的抗锯齿抖动不会。
// 只用 Node 自带的 zlib 解码 PNG，支持 Chromium 截图用的 8 位 RGB、RGBA，不支持隔行扫描。
import {readFileSync, readdirSync, statSync} from 'node:fs';
import {join, relative} from 'node:path';
import {inflateSync} from 'node:zlib';
import {parseArgs} from 'node:util';

export function decodePNG(buffer) {
  let pos = 8, width = 0, height = 0, channels = 0;
  const idat = [];
  while (pos < buffer.length) {
    const length = buffer.readUInt32BE(pos), type = buffer.toString('latin1', pos + 4, pos + 8), data = buffer.subarray(pos + 8, pos + 8 + length);
    if (type === 'IHDR') {
      width = data.readUInt32BE(0);
      height = data.readUInt32BE(4);
      const depth = data[8], color = data[9], interlace = data[12];
      if (depth !== 8 || interlace !== 0 || ![2, 6].includes(color)) throw new Error(`不支持的 PNG 格式：位深 ${depth}，颜色类型 ${color}，隔行 ${interlace}`);
      channels = color === 6 ? 4 : 3;
    } else if (type === 'IDAT') idat.push(data);
    else if (type === 'IEND') break;
    pos += 12 + length;
  }
  const raw = inflateSync(Buffer.concat(idat)), stride = width * channels, pixels = Buffer.alloc(height * stride);
  for (let y = 0; y < height; y++) {
    const filter = raw[y * (stride + 1)], line = raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1));
    const out = pixels.subarray(y * stride, (y + 1) * stride), up = y ? pixels.subarray((y - 1) * stride, y * stride) : null;
    for (let x = 0; x < stride; x++) {
      const a = x >= channels ? out[x - channels] : 0, b = up ? up[x] : 0, c = up && x >= channels ? up[x - channels] : 0;
      let p;
      if (filter === 0) p = 0;
      else if (filter === 1) p = a;
      else if (filter === 2) p = b;
      else if (filter === 3) p = (a + b) >> 1;
      else if (filter === 4) {
        const e = a + b - c, pa = Math.abs(e - a), pb = Math.abs(e - b), pc = Math.abs(e - c);
        p = pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
      } else throw new Error(`未知的扫描线过滤类型 ${filter}`);
      out[x] = (line[x] + p) & 255;
    }
  }
  return {width, height, channels, pixels};
}

// 返回 null 表示像素相同；否则返回尺寸差异或差异像素数、最大通道差和差异区域。
export function comparePNG(a, b) {
  const pa = decodePNG(a), pb = decodePNG(b);
  if (pa.width !== pb.width || pa.height !== pb.height) return {size: `${pa.width}×${pa.height} → ${pb.width}×${pb.height}`};
  let count = 0, maxDelta = 0, x0 = Infinity, y0 = Infinity, x1 = -1, y1 = -1;
  for (let y = 0; y < pa.height; y++) for (let x = 0; x < pa.width; x++) {
    let delta = 0;
    for (let k = 0; k < 3; k++) delta = Math.max(delta, Math.abs(pa.pixels[(y * pa.width + x) * pa.channels + k] - pb.pixels[(y * pb.width + x) * pb.channels + k]));
    if (pa.channels === 4 || pb.channels === 4) {
      const aa = pa.channels === 4 ? pa.pixels[(y * pa.width + x) * 4 + 3] : 255, ab = pb.channels === 4 ? pb.pixels[(y * pb.width + x) * 4 + 3] : 255;
      delta = Math.max(delta, Math.abs(aa - ab));
    }
    if (!delta) continue;
    count++;
    maxDelta = Math.max(maxDelta, delta);
    x0 = Math.min(x0, x); y0 = Math.min(y0, y); x1 = Math.max(x1, x); y1 = Math.max(y1, y);
  }
  return count ? {count, maxDelta, box: `x ${x0}–${x1}，y ${y0}–${y1}`} : null;
}

const pngs = dir => {
  const found = [];
  const walk = d => { for (const f of readdirSync(d).sort()) { const p = join(d, f); if (statSync(p).isDirectory()) walk(p); else if (f.endsWith('.png')) found.push(relative(dir, p)); } };
  walk(dir);
  return found;
};

if (import.meta.url === `file://${process.argv[1]}`) {
  const {values, positionals: [dirA, dirB]} = parseArgs({allowPositionals: true, options: {'max-pixels': {type: 'string', default: '0'}}});
  const maxPixels = Number(values['max-pixels']);
  if (!dirA || !dirB || !Number.isInteger(maxPixels) || maxPixels < 0) { console.error('用法：node qa/compare-shots.mjs [--max-pixels N] 目录A 目录B'); process.exit(2); }
  const a = new Set(pngs(dirA)), b = new Set(pngs(dirB)), lines = [], noise = [];
  for (const name of [...new Set([...a, ...b])].sort()) {
    if (!b.has(name)) { lines.push(`缺少：${name}`); continue; }
    if (!a.has(name)) { lines.push(`多出：${name}`); continue; }
    const bytesA = readFileSync(join(dirA, name)), bytesB = readFileSync(join(dirB, name));
    if (bytesA.equals(bytesB)) continue;
    const diff = comparePNG(bytesA, bytesB);
    if (!diff) continue;
    const detail = diff.size ? `尺寸 ${diff.size}` : `${diff.count} 个像素，最大通道差 ${diff.maxDelta}，区域 ${diff.box}`;
    (diff.count && diff.count <= maxPixels ? noise : lines).push(`${diff.count && diff.count <= maxPixels ? '噪声' : '不同'}：${name}（${detail}）`);
  }
  if (noise.length) console.log(noise.join('\n'));
  console.log(lines.length ? lines.join('\n') : `截图一致：${a.size} 张${noise.length ? `，其中 ${noise.length} 张只有不超过 ${maxPixels} 个像素的差异` : ''}`);
  process.exitCode = lines.length ? 1 : 0;
}
