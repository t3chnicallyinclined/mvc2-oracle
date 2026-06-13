// texture-manager.mjs — Dreamcast texture decode + WebGPU texture cache
// DIRTY-PAGE-AWARE: only re-decodes textures whose VRAM pages actually changed

const detwiddle = [new Array(11), new Array(11)];
(() => {
    function tw(x, y, xs, ys) {
        let r=0, s=0; xs>>=1; ys>>=1;
        while (xs||ys) { if(ys){r|=(y&1)<<s;ys>>=1;y>>=1;s++;} if(xs){r|=(x&1)<<s;xs>>=1;x>>=1;s++;} }
        return r;
    }
    for (let s=0;s<11;s++) { detwiddle[0][s]=new Uint32Array(1024); detwiddle[1][s]=new Uint32Array(1024);
        const ys=1<<s; for(let i=0;i<1024;i++){detwiddle[0][s][i]=tw(i,0,1024,ys);detwiddle[1][s][i]=tw(0,i,ys,1024);} }
})();
function twop(x,y,bx,by){return detwiddle[0][by][x]+detwiddle[1][bx][y];}
function bsr(v){let r=0;while((1<<r)<v)r++;return r;}
function e5(v){return(v<<3)|(v>>2);}
function e6(v){return(v<<2)|(v>>4);}
function e4(v){return(v<<4)|v;}
function u1555(c){return[e5((c>>10)&31),e5((c>>5)&31),e5(c&31),(c>>15)?255:0];}
function u565(c){return[e5((c>>11)&31),e6((c>>5)&63),e5(c&31),255];}
function u4444(c){return[e4((c>>8)&15),e4((c>>4)&15),e4(c&15),e4((c>>12)&15)];}

const VQ_CODEBOOK_SIZE = 2048;
const PAGE_SIZE = 4096;
const VQMipPoint = [
    VQ_CODEBOOK_SIZE+0x00000, VQ_CODEBOOK_SIZE+0x00001, VQ_CODEBOOK_SIZE+0x00002,
    VQ_CODEBOOK_SIZE+0x00006, VQ_CODEBOOK_SIZE+0x00016, VQ_CODEBOOK_SIZE+0x00056,
    VQ_CODEBOOK_SIZE+0x00156, VQ_CODEBOOK_SIZE+0x00556, VQ_CODEBOOK_SIZE+0x01556,
    VQ_CODEBOOK_SIZE+0x05556, VQ_CODEBOOK_SIZE+0x15556
];
const OtherMipPoint = [
    0x00003, 0x00004, 0x00008, 0x00018, 0x00058,
    0x00158, 0x00558, 0x01558, 0x05558, 0x15558, 0x55558
];

// Compute texture byte size in VRAM for page overlap checks
function texByteSize(fmt, w, h, vq, mip, texU) {
    if (vq) {
        const mipIdx = texU + 3;
        return mip ? VQMipPoint[mipIdx] + (w * h >> 2) : VQ_CODEBOOK_SIZE + (w * h >> 2);
    }
    if (mip) {
        const mipIdx = texU + 3;
        const bpp = fmt === 5 ? 4 : fmt === 6 ? 8 : 16;
        return OtherMipPoint[mipIdx] * (bpp >> 3) + (w * h * bpp >> 3);
    }
    if (fmt === 5) return w * h >> 1;  // 4bpp
    if (fmt === 6) return w * h;       // 8bpp
    return w * h * 2;                   // 16bpp
}

export class TextureManager {
    constructor(device) {
        this.device = device;
        this.cache = new Map();       // baseKey → { texture, sampler, w, h, addr, endAddr, paletted }
        this._dirtyPages = null;      // Set of dirty page indices for current frame
        this._palDirty = false;       // Palette changed this frame
        this._pal = null;
        this._fb = null;
        this.stats = { hits: 0, misses: 0, reused: 0, vq: 0, mip: 0, unsupported: 0, dirtyDecodes: 0 };
    }

    // Set dirty pages for this frame. Call BEFORE any getTexture calls.
    setDirtyPages(dirtyPageList, pvrDirty) {
        if (dirtyPageList && dirtyPageList.length > 0) {
            this._dirtyPages = new Set(dirtyPageList);
        } else {
            this._dirtyPages = null;
        }
        this._palDirty = !!pvrDirty;
    }

    // Full invalidation (scene change / SYNC)
    invalidateAll() {
        this.cache.clear();
    }

    updatePalette(regs) {
        if (!regs || regs.length < 0x1000+4096) return;
        const pv = new DataView(regs.buffer, regs.byteOffset+0x1000, 4096);
        const ctrl = new DataView(regs.buffer, regs.byteOffset).getUint32(0x108,true) & 3;
        this._pal = new Uint8Array(4096);
        const unp = [u1555,u565,u4444,u4444][ctrl];
        for (let i=0;i<1024;i++) {
            const raw = pv.getUint32(i*4,true);
            const c = ctrl===3 ? [(raw>>16)&0xFF,(raw>>8)&0xFF,raw&0xFF,(raw>>24)&0xFF] : unp(raw&0xFFFF);
            this._pal[i*4]=c[0]; this._pal[i*4+1]=c[1]; this._pal[i*4+2]=c[2]; this._pal[i*4+3]=c[3];
        }
    }

    // Check if a texture's VRAM range overlaps any dirty page
    _isDirty(addr, byteSize, paletted) {
        // Palette change invalidates all paletted textures
        if (paletted && this._palDirty) return true;
        // No dirty VRAM pages → not dirty
        if (!this._dirtyPages) return false;
        // Check page overlap: texture covers [addr, addr+byteSize)
        const startPage = (addr / PAGE_SIZE) | 0;
        const endPage = ((addr + byteSize - 1) / PAGE_SIZE) | 0;
        for (let p = startPage; p <= endPage; p++) {
            if (this._dirtyPages.has(p)) return true;
        }
        return false;
    }

    getTexture(tsp, tcw, vram) {
        const addr=(tcw&0x1FFFFF)<<3, fmt=(tcw>>27)&7, texU=(tsp>>3)&7, texV=tsp&7;
        const w=8<<texU, h=8<<texV, palSel=(tcw>>21)&0x3F, scan=(tcw>>26)&1;
        const vq=(tcw>>30)&1, mip=(tcw>>31)&1;
        const paletted = fmt === 5 || fmt === 6;

        const baseKey = `${addr}_${fmt}_${texU}_${texV}_${palSel}_${vq}_${mip}`;
        const cached = this.cache.get(baseKey);

        if (cached) {
            // Check if this texture's VRAM pages were dirtied
            if (!this._isDirty(cached.addr, cached.endAddr - cached.addr, paletted)) {
                this.stats.hits++;
                return cached;
            }
            // Dirty — need to re-decode. Reuse GPU texture object.
            this.stats.dirtyDecodes++;
        }

        const byteSize = texByteSize(fmt, w, h, vq, mip, texU);
        const rgba = this._decode(vram, addr, fmt, w, h, palSel, scan, vq, mip, texU);
        if (!rgba) return this.getFallbackTexture();

        let texture, sampler;
        if (cached && cached.w === w && cached.h === h) {
            // Reuse existing GPU texture — just upload new data
            texture = cached.texture;
            sampler = cached.sampler;
            this.device.queue.writeTexture({texture}, rgba, {bytesPerRow: w*4}, [w, h]);
            this.stats.reused++;
        } else {
            texture = this.device.createTexture({size:[w,h],format:'rgba8unorm',usage:GPUTextureUsage.TEXTURE_BINDING|GPUTextureUsage.COPY_DST});
            this.device.queue.writeTexture({texture},rgba,{bytesPerRow:w*4},[w,h]);
            const fm=(tsp>>13)&3, cu=(tsp>>16)&1, cv=(tsp>>15)&1, fu=(tsp>>18)&1, fv=(tsp>>17)&1;
            sampler = this.device.createSampler({minFilter:fm?'linear':'nearest',magFilter:fm?'linear':'nearest',
                addressModeU:cu?'clamp-to-edge':fu?'mirror-repeat':'repeat',addressModeV:cv?'clamp-to-edge':fv?'mirror-repeat':'repeat'});
            if (cached) cached.texture.destroy();
            this.stats.misses++;
        }

        const entry = {texture, sampler, w, h, addr, endAddr: addr + byteSize, paletted};
        this.cache.set(baseKey, entry);
        return entry;
    }

    _decode(vram, addr, fmt, w, h, palSel, scan, vq, mip, texU) {
        // Reuse decode buffer to avoid GC pressure (max texture = 1024x1024x4 = 4MB)
        const needed=w*h*4;
        if(!this._decodeBuf||this._decodeBuf.length<needed) this._decodeBuf=new Uint8Array(Math.max(needed,1024*1024));
        const rgba=this._decodeBuf.subarray(0,needed);
        rgba.fill(0); // Clear — important for textures with gaps
        const bx=bsr(w), by=bsr(h);
        if (vq) { this.stats.vq++; return this._decodeVQ(vram, addr, fmt, w, h, bx, by, mip, texU, rgba); }
        let texAddr = addr;
        if (mip) {
            this.stats.mip++;
            const mipIdx = texU + 3;
            if (fmt === 5) texAddr = addr + (OtherMipPoint[mipIdx] >> 1);
            else if (fmt === 6) texAddr = addr + OtherMipPoint[mipIdx];
            else texAddr = addr + OtherMipPoint[mipIdx] * 2;
        }
        if (fmt===5) return this._pal4(vram,texAddr,w,h,bx,by,palSel,rgba);
        if (fmt===6) return this._pal8(vram,texAddr,w,h,bx,by,palSel,rgba);
        const unp = fmt===0?u1555:fmt===1?u565:fmt===2?u4444:null;
        if (!unp) { this.stats.unsupported++; return null; }
        for (let y=0;y<h;y++) for (let x=0;x<w;x++) {
            const idx = scan===1 ? y*w+x : twop(x,y,bx,by);
            const so = texAddr+idx*2; if(so+1>=vram.length)continue;
            const c=unp(vram[so]|(vram[so+1]<<8)), d=(y*w+x)*4;
            rgba[d]=c[0];rgba[d+1]=c[1];rgba[d+2]=c[2];rgba[d+3]=c[3];
        }
        return rgba;
    }

    _decodeVQ(vram, addr, fmt, w, h, bx, by, mip, texU, rgba) {
        const unp = fmt===0?u1555:fmt===1?u565:fmt===2?u4444:null;
        if (!unp) { this.stats.unsupported++; return null; }
        const cbAddr = addr;
        let idxAddr = mip ? addr + VQMipPoint[texU + 3] : addr + VQ_CODEBOOK_SIZE;
        if(!this._vqCB) this._vqCB=new Uint8Array(256*16);
        const cb = this._vqCB;
        for (let i = 0; i < 256; i++) {
            const co = cbAddr + i * 8;
            for (let p = 0; p < 4; p++) {
                const so = co + p * 2; if (so + 1 >= vram.length) continue;
                const c = unp(vram[so] | (vram[so+1] << 8));
                const d = i * 16 + p * 4;
                cb[d] = c[0]; cb[d+1] = c[1]; cb[d+2] = c[2]; cb[d+3] = c[3];
            }
        }
        const hw = w >> 1, hh = h >> 1, bcx = bx - 1, bcy = by - 1;
        for (let y = 0; y < hh; y++) {
            for (let x = 0; x < hw; x++) {
                const ti = twop(x, y, bcx, bcy);
                const io = idxAddr + ti; if (io >= vram.length) continue;
                const ci = vram[io] * 16, px = x * 2, py = y * 2;
                let d = (py * w + px) * 4;
                rgba[d]=cb[ci]; rgba[d+1]=cb[ci+1]; rgba[d+2]=cb[ci+2]; rgba[d+3]=cb[ci+3];
                d = ((py+1) * w + px) * 4;
                rgba[d]=cb[ci+4]; rgba[d+1]=cb[ci+5]; rgba[d+2]=cb[ci+6]; rgba[d+3]=cb[ci+7];
                d = (py * w + px + 1) * 4;
                rgba[d]=cb[ci+8]; rgba[d+1]=cb[ci+9]; rgba[d+2]=cb[ci+10]; rgba[d+3]=cb[ci+11];
                d = ((py+1) * w + px + 1) * 4;
                rgba[d]=cb[ci+12]; rgba[d+1]=cb[ci+13]; rgba[d+2]=cb[ci+14]; rgba[d+3]=cb[ci+15];
            }
        }
        return rgba;
    }

    _pal4(vram,addr,w,h,bx,by,palSel,rgba) {
        if(!this._pal)return null; const pb=palSel<<4;
        for(let y=0;y<h;y++)for(let x=0;x<w;x++){
            const ti=twop(x,y,bx,by),bo=addr+(ti>>1); if(bo>=vram.length)continue;
            const ni=(ti&1)?((vram[bo]>>4)&0xF):(vram[bo]&0xF), pi=(pb+ni)*4, d=(y*w+x)*4;
            rgba[d]=this._pal[pi];rgba[d+1]=this._pal[pi+1];rgba[d+2]=this._pal[pi+2];rgba[d+3]=this._pal[pi+3];
        } return rgba;
    }

    _pal8(vram,addr,w,h,bx,by,palSel,rgba) {
        if(!this._pal)return null; const pb=((palSel>>4)<<8);
        for(let y=0;y<h;y++)for(let x=0;x<w;x++){
            const ti=twop(x,y,bx,by),bo=addr+ti; if(bo>=vram.length)continue;
            const pi=(pb+vram[bo])*4, d=(y*w+x)*4;
            rgba[d]=this._pal[pi];rgba[d+1]=this._pal[pi+1];rgba[d+2]=this._pal[pi+2];rgba[d+3]=this._pal[pi+3];
        } return rgba;
    }

    getFallbackTexture() {
        if(this._fb)return this._fb;
        const t=this.device.createTexture({size:[1,1],format:'rgba8unorm',usage:GPUTextureUsage.TEXTURE_BINDING|GPUTextureUsage.COPY_DST});
        this.device.queue.writeTexture({texture:t},new Uint8Array([255,255,255,255]),{bytesPerRow:4},[1,1]);
        this._fb={texture:t,sampler:this.device.createSampler({minFilter:'nearest',magFilter:'nearest'})};
        return this._fb;
    }
}
