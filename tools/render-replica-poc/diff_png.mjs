// diff_png.mjs — pixel diff two PNGs (e.g. replica render vs cockpit/ground-truth
// screenshot). Reports match %, max/mean channel delta, and writes a heatmap.
//
//   node diff_png.mjs <a.png> <b.png> [--out diff.png] [--tol N] [--ignore-alpha]
//
// tol = per-channel tolerance (0-255) below which a pixel counts as a match.
// Exit code 0 if mean delta <= tol, else 1 (so it can gate CI / a converge loop).

import { readFileSync, writeFileSync } from 'node:fs';
import { PNG } from 'pngjs';

function arg(name, def) { const i = process.argv.indexOf(name); return i >= 0 ? process.argv[i + 1] : def; }
const [, , aPath, bPath] = process.argv;
if (!aPath || !bPath || aPath.startsWith('--')) {
    console.error('usage: node diff_png.mjs <a.png> <b.png> [--out diff.png] [--tol N] [--ignore-alpha]');
    process.exit(2);
}
const outPath = arg('--out', 'diff.png');
const tol = +arg('--tol', '2');
const ignoreAlpha = process.argv.includes('--ignore-alpha');

const a = PNG.sync.read(readFileSync(aPath));
const b = PNG.sync.read(readFileSync(bPath));
if (a.width !== b.width || a.height !== b.height) {
    console.error(`size mismatch: ${a.width}x${a.height} vs ${b.width}x${b.height}`);
    process.exit(2);
}
const W = a.width, H = a.height, N = W * H;
const diff = new PNG({ width: W, height: H });

let matched = 0, sumDelta = 0, maxDelta = 0, diffPixels = 0;
const chans = ignoreAlpha ? 3 : 4;
for (let i = 0; i < N; i++) {
    const o = i * 4;
    let pxMax = 0, pxSum = 0;
    for (let c = 0; c < chans; c++) {
        const d = Math.abs(a.data[o + c] - b.data[o + c]);
        pxSum += d; if (d > pxMax) pxMax = d;
    }
    sumDelta += pxSum;
    if (pxMax > maxDelta) maxDelta = pxMax;
    if (pxMax <= tol) { matched++; diff.data[o] = a.data[o]; diff.data[o + 1] = a.data[o + 1]; diff.data[o + 2] = a.data[o + 2]; diff.data[o + 3] = 255; }
    else {
        diffPixels++;
        // red heatmap scaled by magnitude
        const m = Math.min(255, pxMax);
        diff.data[o] = 255; diff.data[o + 1] = 255 - m; diff.data[o + 2] = 255 - m; diff.data[o + 3] = 255;
    }
}
writeFileSync(outPath, PNG.sync.write(diff));

const meanDelta = sumDelta / (N * chans);
const matchPct = (matched / N * 100);
console.log(`A: ${aPath}`);
console.log(`B: ${bPath}`);
console.log(`size: ${W}x${H} (${N} px), tol=${tol}, channels=${chans}`);
console.log(`match:        ${matchPct.toFixed(4)}%  (${matched}/${N})`);
console.log(`diff pixels:  ${diffPixels}`);
console.log(`max Δ:        ${maxDelta} (per channel)`);
console.log(`mean Δ:       ${meanDelta.toFixed(4)} (per channel)`);
console.log(`heatmap:      ${outPath}`);
process.exit(meanDelta <= tol ? 0 : 1);
