// pvr2-renderer.mjs — WebGPU renderer for PVR2 TA stream
// ═══════════════════════════════════════════════════════════════
// GOLD STANDARD CONFIG (2026-04-12) — DO NOT CHANGE WITHOUT TESTING
//
// Performance: 1.88ms process (11% budget), 24.7ms E2E over QUIC/UDP
//
// Rendering settings:
//   Single pass:         ON  (multi-pass detection doesn't match flycast)
//   Z-sort:              OFF (submission order — sort + depth write = flicker)
//   Translucent depth:   write=ON, func=greater-equal (fixes cape rendering)
//   Opaque depth:        per-poly ISP.DepthMode, write=per-poly ZWriteDis
//   Opaque blend:        forced ONE/ZERO (no blending, matches flycast)
//   Culling:             per-poly ISP.CullMode XOR 1
//   Alpha discard:       c.a < 0.004
//
// Texture settings:
//   Dirty-page cache:    ON (only re-decode on VRAM page overlap)
//   Palette update:      on vramDirty || pvrDirty || first frame
//   Formats:             1555/565/4444 + VQ + Pal4/Pal8 + mipmapped
//   Color expansion:     bit-replication (e5/e6/e4) matching flycast
//   VQ pixel order:      prel(x,y) = p_in[0]=TL, p_in[1]=BL, p_in[2]=TR, p_in[3]=BR
//
// GPU buffer strategy:
//   Vertex/index:        double-buffered (flip each frame)
//   Fragment uniforms:   dynamic uniform buffer, 256B aligned, 8192 max slots
//   Pipeline cache:      keyed by (blend src/dst, depth mode/write, cull, topology)
//   State batching:      skip redundant setPipeline/setBindGroup/setScissorRect
//   Bind group cache:    texture bind groups rebuilt per frame (texBGs.clear)
//
// Transport: WebTransport (QUIC/UDP) with WebSocket fallback
// Vsync: decoupled — WS onmessage=decode+parse, RAF=render latest
// ═══════════════════════════════════════════════════════════════

import { vertexShader, fragmentShader } from './shaders.mjs';

const SBM=['zero','one','dst','one-minus-dst','src-alpha','one-minus-src-alpha','dst-alpha','one-minus-dst-alpha'];
const DBM=['zero','one','src','one-minus-src','src-alpha','one-minus-src-alpha','dst-alpha','one-minus-dst-alpha'];
const DCM=['never','less','equal','less-equal','greater','not-equal','greater-equal','always'];
const CM=['none','none','front','back'];

const VBL = { arrayStride: 28, attributes: [
    { shaderLocation:0, offset:0, format:'float32x3' },
    { shaderLocation:1, offset:12, format:'unorm8x4' },
    { shaderLocation:2, offset:16, format:'unorm8x4' },
    { shaderLocation:3, offset:20, format:'float32x2' },
]};

export class PVR2Renderer {
    constructor() {
        this.dev=null; this.ctx=null; this.fmt=null;
        this.pipes=new Map(); this.texBGs=new Map();
        // Double-buffered vertex/index: alternate each frame to avoid GPU write stalls
        this.vBufs=[null,null]; this.vBufSzs=[0,0]; this.vFrame=0;
        this.idxBufs=[null,null]; this.idxBufSzs=[0,0];
        this.vBuf=null; this.idxBuf=null; // Current frame's active buffers
        this.depth=null; this.bgl0=null; this.bgl1=null; this.pipeLayout=null;
        this.shader=null; this.uBG=null;
        // Dynamic frag uniform: 256-byte aligned slots, pre-allocated
        this.SLOT=256; this.MAX_SLOTS=8192;
        this.dynBuf=null; this.staging=null; this.stagingDV=null;
    }

    async init(canvas) {
        if (!navigator.gpu) throw new Error('WebGPU not supported');
        const a = await navigator.gpu.requestAdapter({powerPreference:'high-performance'});
        if (!a) throw new Error('No WebGPU adapter');
        this.dev = await a.requestDevice();
        this.ctx = canvas.getContext('webgpu');
        this.fmt = navigator.gpu.getPreferredCanvasFormat();
        this.ctx.configure({device:this.dev,format:this.fmt,alphaMode:'premultiplied'});
        this._init(canvas.width, canvas.height);
        return this.dev;
    }

    // Bind a SECOND renderer to another canvas reusing an existing device (the
    // STAF HUD/effects overlay shares the main renderer's device so textures and
    // buffers are interoperable). alphaMode 'premultiplied' lets the canvas be a
    // transparent overlay composited over the lean character canvas.
    initShared(canvas, device) {
        this.dev = device;
        this.ctx = canvas.getContext('webgpu');
        this.fmt = navigator.gpu.getPreferredCanvasFormat();
        this.ctx.configure({device:this.dev,format:this.fmt,alphaMode:'premultiplied'});
        this._init(canvas.width, canvas.height);
        return this.dev;
    }

    _init(w,h) {
        const d = this.dev;
        this.uBuf = d.createBuffer({size:64,usage:GPUBufferUsage.UNIFORM|GPUBufferUsage.COPY_DST});
        this.dynBuf = d.createBuffer({size:this.SLOT*this.MAX_SLOTS,usage:GPUBufferUsage.UNIFORM|GPUBufferUsage.COPY_DST});
        this.staging = new ArrayBuffer(this.SLOT*this.MAX_SLOTS);
        this.stagingDV = new DataView(this.staging);
        this.depth = d.createTexture({size:[w,h],format:'depth32float',usage:GPUTextureUsage.RENDER_ATTACHMENT});
        this.bgl0 = d.createBindGroupLayout({entries:[
            {binding:0,visibility:GPUShaderStage.VERTEX,buffer:{type:'uniform'}},
            {binding:1,visibility:GPUShaderStage.FRAGMENT,buffer:{type:'uniform',hasDynamicOffset:true}},
        ]});
        this.bgl1 = d.createBindGroupLayout({entries:[
            {binding:0,visibility:GPUShaderStage.FRAGMENT,texture:{sampleType:'float'}},
            {binding:1,visibility:GPUShaderStage.FRAGMENT,sampler:{type:'filtering'}},
        ]});
        this.pipeLayout = d.createPipelineLayout({bindGroupLayouts:[this.bgl0,this.bgl1]});
        this.shader = d.createShaderModule({code:vertexShader+'\n'+fragmentShader});
        this.shader.getCompilationInfo().then(info=>{for(const m of info.messages)console.log('[WGSL]',m.type,m.message,'line',m.lineNum);});
        this.uBG = d.createBindGroup({layout:this.bgl0,entries:[
            {binding:0,resource:{buffer:this.uBuf}},
            {binding:1,resource:{buffer:this.dynBuf,size:32}},
        ]});
    }

    _pipe(sb,db,dm,dw,cm,topo) {
        const k=`${sb}_${db}_${dm}_${dw}_${cm}_${topo}`; let p=this.pipes.get(k); if(p)return p;
        const isDepthOnly = topo==='triangle-list-depth';
        p = this.dev.createRenderPipeline({layout:this.pipeLayout,
            vertex:{module:this.shader,entryPoint:'vs_main',buffers:[VBL]},
            fragment:{module:this.shader,entryPoint:'fs_main',targets:[{format:this.fmt,
                blend:{color:{srcFactor:SBM[sb]||'one',dstFactor:DBM[db]||'zero',operation:'add'},
                       alpha:{srcFactor:SBM[sb]||'one',dstFactor:DBM[db]||'zero',operation:'add'}},
                writeMask:isDepthOnly?0:GPUColorWrite.ALL}]},
            primitive:{topology:'triangle-list',cullMode:'none',frontFace:'cw'},
            depthStencil:{format:'depth32float',depthWriteEnabled:!!dw,depthCompare:DCM[dm]||'always'},
        });
        this.pipes.set(k,p); return p;
    }

    _texBG(t,s) { let b=this.texBGs.get(t); if(b)return b;
        b=this.dev.createBindGroup({layout:this.bgl1,entries:[{binding:0,resource:t.createView()},{binding:1,resource:s}]});
        this.texBGs.set(t,b); return b; }

    uploadVerts(data) {
        const f=this.vFrame, n=data.byteLength;
        if(!this.vBufs[f]||this.vBufSzs[f]<n){
            if(this.vBufs[f])this.vBufs[f].destroy();
            this.vBufSzs[f]=Math.max(n,1<<20);
            this.vBufs[f]=this.dev.createBuffer({size:this.vBufSzs[f],usage:GPUBufferUsage.VERTEX|GPUBufferUsage.COPY_DST});
        }
        this.vBuf=this.vBufs[f];
        this.dev.queue.writeBuffer(this.vBuf,0,data);
    }

    // Convert triangle-strip polys to triangle-list indices
    _buildIndexBuffer(lists) {
        // Count total indices needed
        let totalIdx = 0;
        for (const list of lists) for (const pp of list) {
            if (pp.count < 3 || pp._s < 0) continue;
            totalIdx += (pp.count - 2) * 3;
        }
        const indices = new Uint32Array(totalIdx);
        let idx = 0;
        for (const list of lists) for (const pp of list) {
            if (pp.count < 3 || pp._s < 0) continue;
            pp._idxFirst = idx;
            pp._idxCount = 0;
            for (let i = 0; i < pp.count - 2; i++) {
                const v0 = pp.first + i;
                const v1 = pp.first + i + 1;
                const v2 = pp.first + i + 2;
                if (i & 1) { indices[idx++]=v1; indices[idx++]=v0; indices[idx++]=v2; }
                else       { indices[idx++]=v0; indices[idx++]=v1; indices[idx++]=v2; }
                pp._idxCount += 3;
            }
        }
        // Upload to double-buffered index buffer
        const f=this.vFrame, byteLen = idx * 4;
        if (!this.idxBufs[f] || this.idxBufSzs[f] < byteLen) {
            if (this.idxBufs[f]) this.idxBufs[f].destroy();
            this.idxBufSzs[f] = Math.max(byteLen, 512*1024);
            this.idxBufs[f] = this.dev.createBuffer({size:this.idxBufSzs[f], usage:GPUBufferUsage.INDEX|GPUBufferUsage.COPY_DST});
        }
        this.idxBuf=this.idxBufs[f];
        this.dev.queue.writeBuffer(this.idxBuf, 0, indices.buffer, 0, byteLen);
        this._idxArr = indices;
    }

    // Custom background texture bind group
    _customBgBG(tex) {
        if(!this._bgSampler)this._bgSampler=this.dev.createSampler({minFilter:'linear',magFilter:'linear'});
        if(this._bgTex!==tex){this._bgTex=tex;
            this._bgBindGroup=this.dev.createBindGroup({layout:this.bgl1,entries:[
                {binding:0,resource:tex.createView()},{binding:1,resource:this._bgSampler}]});}
        return this._bgBindGroup;
    }

    // renderTarget: optional {colorView, depthView, width, height} for offscreen rendering
    renderFrame(parsed, texMgr, pvrSnap, vram, dbg, renderTarget) {
        const {vertexData,vertexCount,opaque,punchThrough,translucent}=parsed;
        if(!vertexCount)return;
        dbg = dbg || {};
        // Apply character transforms to translucent vertex positions
        const charScale = (dbg.charScale || 100) / 100.0;
        const bigHead = dbg.bigHead;
        const headScale = (dbg.headSize || 250) / 100.0;
        if (charScale !== 1.0 || bigHead) {
            const vf = new Float32Array(vertexData.buffer, vertexData.byteOffset, vertexCount * 7);
            // Fixed center point (screen center-bottom where characters stand)
            const cx = 320, cy = 300;
            for (const pp of translucent) {
                if (pp.count < 3) continue;
                let sumY=0;
                for (let v=pp.first;v<pp.first+pp.count;v++) sumY+=vf[v*7+1];
                const avgY = sumY / pp.count;
                if (avgY <= 120) continue; // Skip HUD/timer
                const headFactor = bigHead ? Math.max(0, 1 - (avgY - 180) / 60) : 0;
                const scale = charScale * (1 + headFactor * (headScale - 1));
                for (let v = pp.first; v < pp.first + pp.count; v++) {
                    const fi = v * 7;
                    vf[fi] = cx + (vf[fi] - cx) * scale;
                    vf[fi + 1] = cy + (vf[fi + 1] - cy) * scale;
                }
            }
        }
        this.uploadVerts(vertexData);
        // NDC matrix with zoom + shake
        const ndcMat = this._ndcMat(pvrSnap);
        const zoom = (dbg.zoom || 100) / 100.0;
        if (zoom !== 1.0) { ndcMat[0] *= zoom; ndcMat[5] *= zoom; }
        const shk = (dbg.shakeAmt || 0) / 100.0;
        if (shk > 0) {
            const t = performance.now() / 1000.0;
            ndcMat[12] += Math.sin(t * 30) * shk;
            ndcMat[13] += Math.cos(t * 37) * shk * 0.7;
        }
        if (dbg.mirror) { ndcMat[0] = -ndcMat[0]; ndcMat[12] = -ndcMat[12]; }
        this.dev.queue.writeBuffer(this.uBuf, 0, ndcMat);
        // Palette already updated per-frame in webgpu-test.html via setDirtyPages + updatePalette
        this.texBGs.clear(); // Must rebuild bind groups when textures are re-decoded

        // Stage all frag uniforms
        let slot=0;
        const stage=(list,lt)=>{for(const pp of list){
            if(pp.count<3){pp._s=-1;continue;}
            if(lt==='opaque'&&((pp.isp>>29)&7)===0){pp._s=-1;continue;}
            if(slot>=this.MAX_SLOTS){pp._s=-1;continue;}
            const o=slot*this.SLOT, tsp=pp.tsp, pcw=pp.pcw;
            const shadInstr = (dbg.shadOverride&&dbg.shadInstr>=0) ? dbg.shadInstr : (tsp>>6)&3;
            const useAlpha = dbg.useAlphaOverride>=0 ? dbg.useAlphaOverride : (tsp>>20)&1;
            // atv: time for effects (simple), extra fx bits packed into upper bits of packed field
            this.stagingDV.setFloat32(o,(lt==='punch_through')?1.0:(performance.now()/1000.0)%100.0,true);
            this.stagingDV.setUint32(o+4,shadInstr,true);
            this.stagingDV.setUint32(o+8,(pcw>>3)&1,true);
            this.stagingDV.setUint32(o+12,useAlpha,true);
            this.stagingDV.setUint32(o+16,(tsp>>19)&1,true);
            this.stagingDV.setUint32(o+20,dbg.noOffset?0:(pcw>>2)&1,true);
            this.stagingDV.setUint32(o+24,lt==='punch_through'?1:0,true);
            // Pack: bits 0-7=debug, bit8=gouraud, bit9=trans, bit10-11=discard, bits12+=effects
            const modes={normal:0,solid:1,uv:2,depth:3,alpha:4};
            const gouraud = (pcw>>1)&1;
            const isTrans = lt==='translucent'?1:0;
            const noDiscard = dbg.noDiscard?1:0;
            const discTransOnly = dbg.discardTransOnly?1:0;
            const fxBits = (dbg.fxBits||0)&0xFFFFF; // 20 bits of effects
            this.stagingDV.setUint32(o+28,(modes[dbg.shaderMode]||0)|(gouraud<<8)|(isTrans<<9)|(noDiscard<<10)|(discTransOnly<<11)|(fxBits<<12),true);
            pp._s=slot; slot++;
        }};
        stage(opaque,'opaque'); stage(punchThrough,'punch_through'); stage(translucent,'translucent');
        if(slot>0) this.dev.queue.writeBuffer(this.dynBuf,0,this.staging,0,slot*this.SLOT);

        // Build index buffer: convert strips to triangle lists
        this._buildIndexBuffer([opaque, punchThrough, translucent]);

        // Flycast forces opaque blend to (ONE, ZERO) — no blending
        for(const pp of opaque){pp.tsp=(pp.tsp&0x03FFFFFF)|(1<<29)|(0<<26);}

        const fb=texMgr.getFallbackTexture(), fbBG=this._texBG(fb.texture,fb.sampler);
        const enc=this.dev.createCommandEncoder();
        const texView = renderTarget ? renderTarget.colorView : this.ctx.getCurrentTexture().createView();
        const depthView = renderTarget ? renderTarget.depthView : this.depth.createView();
        let passes = parsed.renderPasses || [{op_count:opaque.length,pt_count:punchThrough.length,tr_count:translucent.length}];
        if(dbg.singlePass) passes=[{op_count:opaque.length,pt_count:punchThrough.length,tr_count:translucent.length}];

        const cW = renderTarget ? renderTarget.width : this.depth.width;
        const cH = renderTarget ? renderTarget.height : this.depth.height;
        const applyTileClip=(rp,tc)=>{
            const mode=tc>>>28;
            if(mode>=2){
                const xmin=(tc&63)*32, xmax=((tc>>6)&63)*32+32;
                const ymin=((tc>>12)&31)*32, ymax=((tc>>17)&31)*32+32;
                // mode 2=Outside (render inside), mode 3=Inside (render outside — needs shader, use inside approx)
                const sx=Math.max(0,xmin), sy=Math.max(0,ymin);
                const sw=Math.min(cW,xmax)-sx, sh=Math.min(cH,ymax)-sy;
                if(sw>0&&sh>0) rp.setScissorRect(sx,sy,sw,sh);
                else rp.setScissorRect(0,0,cW,cH);
            } else {
                rp.setScissorRect(0,0,cW,cH);
            }
        };
        let _lastPipe=null, _lastTBG=null, _lastClip=-1;
        const drawSlice=(rp,list,lt,start,count)=>{
            for(let i=start;i<start+count;i++){
                const pp=list[i]; if(!pp||pp.count<3||pp._s<0)continue;
                const isp=pp.isp,tsp=pp.tsp,tcw=pp.tcw,pcw=pp.pcw;
                if(dbg.excludeTex&&dbg.excludeTex.has(tcw>>>0))continue; // bake: drop shadow/meter/HUD textures → clean character only
                let dm=(isp>>29)&7,cm=(isp>>27)&3,zw=(isp>>26)&1?0:1;
                if(lt==='opaque'&&dbg.opDepthFunc>=0)dm=dbg.opDepthFunc;
                if(lt==='opaque'&&dm===0)continue;
                // Custom background: skip stage geometry by Z threshold
                // Opaque: skip background + FillBGP (low Z)
                // Translucent: skip floor grid (low Z, keep characters at high Z)
                if(dbg.customBg){
                    const floorZ=dbg.floorZ||0.003;
                    const vf=new Float32Array(vertexData.buffer,vertexData.byteOffset,vertexCount*7);
                    const z0=vf[pp.first*7+2];
                    if(lt==='opaque'&&z0<floorZ)continue;
                    if(lt==='translucent'&&z0<floorZ)continue;
                }
                // RE COCKPIT layer isolation: hide whole Z/blend-classified layers so
                // the operator can see STAGE / CHARACTER / EFFECT in isolation (same
                // idea as the floor-cut, but per-layer). dbg.reHide = bitmask:
                //   1=stage(bg)  2=character/HUD  4=effect/spark(additive)
                // NOTE: gate on reHide ALONE (the bitmask is the intent to isolate).
                // It used to also require dbg.reLayerFilter, but that flag is the
                // histogram/classify-ETL toggle and is FORCED OFF in DIFF mode — so the
                // hide checkboxes set reHide yet nothing was skipped. (BUG 1 fix.)
                if(dbg.reHide){
                    const vf2=new Float32Array(vertexData.buffer,vertexData.byteOffset,vertexCount*7);
                    const z0=vf2[pp.first*7+2];
                    const reCut=(dbg.reCut!==undefined)?dbg.reCut:0.0091;
                    const dstB=(tsp>>26)&7;
                    let layerBit;
                    if(z0<reCut) layerBit=1;                 // STAGE / BG
                    else if(dstB===1) layerBit=4;            // additive => EFFECT / SPARK
                    else layerBit=2;                         // CHARACTER / HUD
                    if(dbg.reHide & layerBit) continue;
                }
                if(lt==='punch_through'||lt==='translucent')dm=6;
                if(lt==='translucent')zw=1; if(lt==='punch_through')zw=1;
                if(lt==='translucent'&&dbg.trDepthFunc!==undefined)dm=dbg.trDepthFunc;
                if(lt==='translucent'&&dbg.trDepthWrite)zw=1;
                let sb=(tsp>>29)&7, db=(tsp>>26)&7;
                if(dbg.blendOverride){sb=dbg.blendSrc||4;db=dbg.blendDst||5;}
                let cullIdx = cm^1;
                if(dbg.cullOverride==='none')cullIdx=0;
                else if(dbg.cullOverride==='front')cullIdx=2;
                else if(dbg.cullOverride==='back')cullIdx=3;
                // Tile clip — only change scissor when needed
                if(!dbg.tileClipOff&&pp.tileclip!==_lastClip){applyTileClip(rp,pp.tileclip);_lastClip=pp.tileclip;}
                // Pipeline — only set when changed
                const pipe=this._pipe(sb,db,dm,zw,cullIdx,'triangle-list');
                if(pipe!==_lastPipe){rp.setPipeline(pipe);_lastPipe=pipe;}
                // Texture bind group — only set when changed
                let tbg=fbBG;
                if((pcw>>3)&1){const t=texMgr.getTexture(tsp,tcw,vram);if(t)tbg=this._texBG(t.texture,t.sampler);}
                if(tbg!==_lastTBG){rp.setBindGroup(1,tbg);_lastTBG=tbg;}
                // Uniform bind group (always changes — dynamic offset per poly)
                rp.setBindGroup(0,this.uBG,[pp._s*this.SLOT]);
                rp.drawIndexed(pp._idxCount,1,pp._idxFirst,0,0);
            }
        };

        let prevPass = {op_count:0,pt_count:0,tr_count:0};
        for(let pi=0;pi<passes.length;pi++){
            const pass=passes[pi];
            const isFirst=pi===0;
            // Each render pass gets its own depth clear (color preserved from previous pass)
            // If custom BG was pre-rendered, load instead of clear on first pass
            const firstLoadOp = (isFirst && !dbg._bgPreRendered) ? 'clear' : 'load';
            const clearAlpha = (dbg.customBg || dbg.transparentClear) ? 0 : 1;  // transparent clear when custom BG / overlay
            const rp=enc.beginRenderPass({
                colorAttachments:[{view:texView,clearValue:{r:0,g:0,b:0,a:clearAlpha},loadOp:firstLoadOp,storeOp:'store'}],
                depthStencilAttachment:{view:depthView,depthClearValue:0.0,depthLoadOp:'clear',depthStoreOp:'store'},
            });
            rp.setVertexBuffer(0,this.vBuf);
            if(this.idxBuf) rp.setIndexBuffer(this.idxBuf,'uint32');
            _lastPipe=null;_lastTBG=null;_lastClip=-1; // Reset state tracking per pass

            rp.setScissorRect(0,0,cW,cH);
            if(dbg.drawOpaque!==false){
                let opStart=prevPass.op_count+(dbg.opSkip||0), opEnd=Math.min(pass.op_count,prevPass.op_count+(dbg.opMax||9999));
                drawSlice(rp,opaque,'opaque',opStart,opEnd-opStart);
            }
            if(dbg.drawPunch!==false) drawSlice(rp,punchThrough,'punch_through',prevPass.pt_count,pass.pt_count-prevPass.pt_count);
            rp.setScissorRect(0,0,cW,cH);
            // Translucent rendering
            if(dbg.drawTrans!==false && dbg.noSort){
                // No-sort path: draw translucent in submission order (like opaque)
                let trS=prevPass.tr_count+(dbg.trSkip||0), trE=Math.min(pass.tr_count,prevPass.tr_count+(dbg.trMax||9999));
                drawSlice(rp,translucent,'translucent',trS,trE-trS);
            }
            // Per-TRIANGLE Z-sort path (matches flycast sortTriangles)
            if(dbg.drawTrans!==false && !dbg.noSort){
                let trStart=prevPass.tr_count+(dbg.trSkip||0);
                let trEnd=Math.min(pass.tr_count,prevPass.tr_count+(dbg.trMax||9999));
                const trCount=trEnd-trStart;
                if(trCount>0){
                    const vf32=new Float32Array(vertexData.buffer,vertexData.byteOffset,vertexCount*7);
                    const idxArr=this._idxArr;
                    // Extract all triangles with their min Z and poly index
                    if(!this._triSort)this._triSort=[];
                    const tris=this._triSort; tris.length=0;
                    for(let i=trStart;i<trStart+trCount;i++){
                        const pp=translucent[i]; if(!pp||pp.count<3||pp._s<0)continue;
                        for(let t2=0;t2<pp._idxCount;t2+=3){
                            const ii=pp._idxFirst+t2;
                            if(ii+2>=idxArr.length)continue;
                            const v0=idxArr[ii],v1=idxArr[ii+1],v2=idxArr[ii+2];
                            const z0=vf32[v0*7+2],z1=vf32[v1*7+2],z2=vf32[v2*7+2];
                            const minZ=Math.min(z0,z1,z2);
                            tris.push(i,ii,minZ); // polyIdx, idxStart, z — packed flat for speed
                        }
                    }
                    // Sort by Z ascending (farthest first), stable by original order
                    const triCount=tris.length/3;
                    // Build sort indices
                    if(!this._triOrder||this._triOrder.length<triCount)this._triOrder=new Uint32Array(Math.max(triCount,256));
                    const order=this._triOrder;
                    for(let i=0;i<triCount;i++)order[i]=i;
                    if(!dbg.noSort){
                        const eps=dbg.zEpsilon||0.00005;
                        order.sort((a,b)=>{const dz=tris[a*3+2]-tris[b*3+2];return Math.abs(dz)<eps?tris[a*3]-tris[b*3]:dz;});
                    }
                    // Draw sorted triangles
                    for(let si=0;si<triCount;si++){
                        const oi=order[si]*3;
                        const polyIdx=tris[oi], idxStart=tris[oi+1];
                        const pp=translucent[polyIdx];
                        const isp=pp.isp,tsp=pp.tsp,tcw=pp.tcw,pcw=pp.pcw;
                        if(dbg.excludeTex&&dbg.excludeTex.has(tcw>>>0))continue; // bake: drop furniture textures
                        let dm=6,zw=0,cm=(isp>>27)&3;
                        if(dbg.trDepthFunc!==undefined)dm=dbg.trDepthFunc;
                        if(dbg.trDepthWrite)zw=1;
                        let sb=(tsp>>29)&7,db=(tsp>>26)&7;
                        if(dbg.blendOverride){sb=dbg.blendSrc||4;db=dbg.blendDst||5;}
                        const pipe=this._pipe(sb,db,dm,zw,cm^1,'triangle-list');
                        let tbg=fbBG;
                        if((pcw>>3)&1){const tx=texMgr.getTexture(tsp,tcw,vram);if(tx)tbg=this._texBG(tx.texture,tx.sampler);}
                        if(pipe!==_lastPipe){rp.setPipeline(pipe);_lastPipe=pipe;}
                        rp.setBindGroup(0,this.uBG,[pp._s*this.SLOT]);
                        if(tbg!==_lastTBG){rp.setBindGroup(1,tbg);_lastTBG=tbg;}
                        rp.drawIndexed(3,1,idxStart,0,0);
                    }
                }
            }
            // Translucent depth-only pass: writes depth for next render pass
            // Only for multi-pass frames and polys with ZWriteDis=0
            if(dbg.drawTrans!==false && pi<passes.length-1){
                const trStart=prevPass.tr_count+(dbg.trSkip||0), trCount=Math.min(pass.tr_count,prevPass.tr_count+(dbg.trMax||9999))-trStart;
                for(let i=trStart;i<trStart+trCount;i++){
                    const pp=translucent[i]; if(!pp||pp.count<3||pp._s<0)continue;
                    if((pp.isp>>26)&1) continue; // ZWriteDis=1, skip
                    const cm=(pp.isp>>27)&3;
                    // Depth-only pipeline: colorWrite=0, depthWrite=true, depthFunc=greater-equal
                    const depthPipe=this._pipe(0,0,6,1,cm^1,'triangle-list-depth');
                    rp.setPipeline(depthPipe);
                    rp.setBindGroup(0,this.uBG,[pp._s*this.SLOT]);
                    rp.setBindGroup(1,fbBG);
                    rp.drawIndexed(pp._idxCount,1,pp._idxFirst,0,0);
                }
            }

            rp.end();
            prevPass=pass;
        }
        if (!renderTarget) {
            // Direct to canvas — submit immediately
            this.dev.queue.submit([enc.finish()]);
        }
        // If renderTarget, caller will add post-process pass and submit
        this._lastEncoder = renderTarget ? enc : null;
        this.vFrame^=1; // Flip double buffer for next frame
    }

    _ndcMat(snap) {
        const g=snap[0],tx=g&0x3F,ty=(g>>16)&0x3F,w=(tx+1)*32,h=(ty+1)*32;
        const m=new Float32Array(16);
        m[0]=2/w;m[5]=-2/h;m[10]=1;m[12]=-1;m[13]=1;m[15]=1;
        return m;
    }
}
