// Summarize: the body-texture VRAM band, page-aligned, and how big a per-frame ship it is.
const lo=0x415400, hi=0x450200;
const pageLo = lo & ~0xFFF;       // 4KB page align down
const pageHi = (hi + 0xFFF) & ~0xFFF;
console.log(`body-texture VRAM band: 0x${lo.toString(16)}..0x${hi.toString(16)}`);
console.log(`page-aligned: 0x${pageLo.toString(16)}..0x${pageHi.toString(16)} = ${((pageHi-pageLo)/1024).toFixed(0)}KB/frame`);
// A safe over-ship covering both bodies + headroom for a 3rd/4th: round to 0x400000..0x480000 (512KB)
console.log(`safe over-ship 0x400000..0x480000 = 512KB/frame (covers 3-4 bodies w/ headroom)`);
// At zstd ~ texture data compresses ~2-3x; 512KB raw -> ~200KB/frame *60 = ~12MB/s. Tight.
// Tighter: 0x410000..0x460000 = 320KB/frame.
console.log(`tighter 0x410000..0x460000 = ${((0x460000-0x410000)/1024)}KB/frame`);
