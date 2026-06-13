// check_bodytex_routing.mjs — pre-deploy simulation for the bodytex VRAM-band routing.
//
// Two checks, no live stream / no rebuild needed:
//   A. Parse the EXISTING tools/render-replica-poc/live.mcrr prefix with the SAME
//      parsePrefix logic replay.html uses, dumping the dynamic region table. This
//      confirms the table struct {addr,len,tag[8]} and that an extra "bodytex" row
//      would be parsed like any other region (the parser is generic over the table).
//   B. Synthesize a tiny prefix+FRMx that DOES carry a "bodytex" region (addr=0x410000),
//      run the EXACT routing from replay.html liveApplyFrame, and assert:
//        - RAM-tagged regions land in ram[] at addr&0xFFFFFF
//        - the "bodytex" region lands in vram[] at addr (0x410000), NOT in ram[]
//
// Run: node tools/render-replica-poc/check_bodytex_routing.mjs
import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));

// ---- parsePrefix: byte-for-byte copy of replay.html's parser (header+tables) ----
function parsePrefix(ab) {
    const buf = new Uint8Array(ab);
    const dv  = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
    let p = 0;
    const u32 = () => { const v = dv.getUint32(p, true); p += 4; return v >>> 0; };
    if (u32() !== 0x5252434D) throw new Error('bad MCRR magic');
    const version = u32(), nStatic = u32(), nDynamic = u32(), nFrames = u32();
    const vramBytes = u32(), pvrBytes = u32(); u32();
    const region = () => { const addr=u32(); const len=u32(); let tag=''; for(let i=0;i<8;i++){const c=buf[p+i]; if(c)tag+=String.fromCharCode(c);} p+=8; return {addr,len,tag}; };
    const staticRegs  = Array.from({length:nStatic },  region);
    const dynamicRegs = Array.from({length:nDynamic}, region);
    return { version, nStatic, nDynamic, nFrames, vramBytes, pvrBytes, staticRegs, dynamicRegs, headerEnd:p };
}

const guestOff = a => (a >>> 0) & 0xFFFFFF;

// ---- routing: byte-for-byte copy of replay.html liveApplyFrame's region loop ----
function routeRegions(dynamicRegs, frmx, ram, vram) {
    const u8 = new Uint8Array(frmx);
    const dv = new DataView(u8.buffer, u8.byteOffset, u8.byteLength);
    let p = 0;
    if (dv.getUint32(p,true) !== 0x784D5246) throw new Error('bad FRMx magic'); p += 4;
    const vframe = dv.getUint32(p,true); p += 4;
    const taSize = dv.getUint32(p,true); p += 4;
    for (const r of dynamicRegs) {
        const slice = u8.subarray(p, p + r.len);
        if (r.tag === 'bodytex') { vram.set(slice, r.addr >>> 0); }   // VRAM offset, NOT &0xFFFFFF
        else ram.set(slice, guestOff(r.addr));
        p += r.len;
    }
    return { vframe, taSize, consumed: p };
}

let fail = 0;
const ok  = (c,m) => { console.log((c?'  PASS ':'  FAIL ')+m); if(!c) fail++; };

// ===== CHECK A: real prefix parse =====
console.log('CHECK A: parse existing live.mcrr prefix (generic dynamic table)');
const mcrr = join(here, 'live.mcrr');
if (existsSync(mcrr)) {
    const pre = parsePrefix(readFileSync(mcrr).buffer);
    console.log(`  v${pre.version}  nStatic=${pre.nStatic} nDynamic=${pre.nDynamic} nFrames=${pre.nFrames} vram=${pre.vramBytes} pvr=${pre.pvrBytes}`);
    console.log('  dynamic regions: ' + pre.dynamicRegs.map(r=>`${r.tag}@0x${r.addr.toString(16)}(0x${r.len.toString(16)})`).join(', '));
    ok(pre.dynamicRegs.length === pre.nDynamic, `parsed all ${pre.nDynamic} dynamic rows`);
    ok(pre.dynamicRegs.every(r => typeof r.tag==='string'), 'every region carries a tag (routing key present)');
    console.log('  (note: this is a PRE-bodytex capture; the new server adds a "bodytex" row — parser is generic so it parses identically.)');
} else {
    console.log('  (live.mcrr not present — skipping; check B is the load-bearing proof)');
}

// ===== CHECK B: synthetic frame WITH a bodytex region, exact routing =====
console.log('\nCHECK B: synthesize a FRMx with a bodytex region and route it');
// Two regions: one RAM (char_str @ 0x8C268340) + the bodytex VRAM band @ 0x410000.
const dynamicRegs = [
    { addr: 0x8C268340, len: 16, tag: 'char_str' },
    { addr: 0x410000,   len: 32, tag: 'bodytex'  },
];
// Build a FRMx record: header(12) + char_str bytes(16) + bodytex bytes(32)
const ramFill = 0xAB, vramFill = 0xCD;
const frmx = new Uint8Array(12 + 16 + 32);
const fdv = new DataView(frmx.buffer);
fdv.setUint32(0, 0x784D5246, true);  // "FRMx"
fdv.setUint32(4, 1234, true);         // vframe
fdv.setUint32(8, 0, true);            // taSize
frmx.fill(ramFill, 12, 12+16);        // char_str payload
frmx.fill(vramFill, 12+16, 12+16+32); // bodytex payload

const ram  = new Uint8Array(16*1024*1024);
const vram = new Uint8Array(8*1024*1024);
const { vframe, consumed } = routeRegions(dynamicRegs, frmx.buffer, ram, vram);

ok(vframe === 1234, `FRMx header parsed (vframe=${vframe})`);
ok(consumed === frmx.length, `consumed all ${frmx.length} bytes`);
// RAM region -> ram[] at 0x268340 (== 0x8C268340 & 0xFFFFFF)
ok(ram[0x268340] === ramFill && ram[0x268340+15] === ramFill, 'char_str -> ram[] at 0x268340');
ok(vram[0x268340] === 0, 'char_str did NOT leak into vram[]');
// bodytex -> vram[] at 0x410000 (raw VRAM offset)
ok(vram[0x410000] === vramFill && vram[0x410000+31] === vramFill, 'bodytex -> vram[] at 0x410000');
ok(ram[0x410000] === 0, 'bodytex did NOT leak into ram[] at 0x410000');
// and crucially NOT at guestOff(0x410000)=0x410000 in RAM either (same low bits) -> already covered above
ok(ram[guestOff(0x410000)] === 0, 'bodytex did NOT land in ram[] at addr&0xFFFFFF');

console.log(`\n${fail===0 ? 'ALL CHECKS PASS' : fail+' CHECK(S) FAILED'} — routing splits RAM->ram[], bodytex->vram[] as designed.`);
process.exit(fail ? 1 : 0);
