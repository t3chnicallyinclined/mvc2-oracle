// diag_offscreen2.mjs — HEADLESS regression proof for the render_frame sprite-base-color fix.
//
// THE BUG (fixed 2026-06-13): render_frame_ta() (wasm_entry_frame.c) memset each 96B PVR
// sprite block and never wrote the TA_Sprite BASE COLOR at +16, leaving it 0x00000000.
// MVC2 body sprites use shadInstr=MODULATE (TSP bits6-7=3) -> the pvr2 fragment shader does
// c = faceColor * texColor. A zero face color zeros every fragment -> c.a<0.004 -> discard ->
// the whole body drew NOTHING, even though the TA parsed to 9 valid translucent sprite quads.
// Fix: emit 0xFFFFFFFF (modulate identity) at +16. (replay.html/index.html/ta-parser/pvr2 were
// all innocent — same render_frame.wasm, so index.html's transpiled pane had the bug too; the
// user was seeing index.html's separate ENGINE pane render correctly.)
//
// Software-WebGPU (SwiftShader) cannot read a canvas back via drawImage, so this renders the
// LIVE replay.html pane's render_frame TA into an OFFSCREEN texture and reads it back with
// copyTextureToBuffer (which DOES work under SwiftShader). The engine TA is the positive
// control (must stay non-zero). PASS = render_frame TA produces pixels.
//
//   1) serve the repo root on :8099   2) node diag_offscreen2.mjs http://localhost:8099
import puppeteer from 'puppeteer';
const BASE = process.argv[2] || 'http://localhost:8099';
const REC  = `${BASE}/web/render-replica/mc_render_rec_synth.bin`;
const args = ['--enable-unsafe-webgpu','--enable-webgpu-developer-features','--ignore-gpu-blocklist','--no-sandbox',
              '--use-webgpu-adapter=swiftshader','--enable-features=Vulkan'];
const browser = await puppeteer.launch({ headless:'new', args });
const page = await browser.newPage();
const logs=[]; page.on('console',m=>logs.push(m.text())); page.on('pageerror',e=>logs.push('ERR '+e.message));
await page.goto(`${BASE}/web/render-replica/replay.html?rec=${encodeURIComponent(REC)}`,{waitUntil:'networkidle0',timeout:90000});
await page.waitForFunction(()=>window.__pane && window.__pane.R && window.__pane.R.dev,{timeout:90000});

const out = await page.evaluate(async (engUrl) => {
    const { TAParser } = await import(new URL('../webgpu/ta-parser.mjs', location.href));
    const pane=window.__pane, R=pane.R, dev=R.dev; const W=640,H=480;
    async function drawAndRead(ta, dbg){
        const colorTex=dev.createTexture({size:[W,H],format:R.fmt,usage:GPUTextureUsage.RENDER_ATTACHMENT|GPUTextureUsage.COPY_SRC});
        const depthTex=dev.createTexture({size:[W,H],format:'depth32float',usage:GPUTextureUsage.RENDER_ATTACHMENT});
        const rt={colorView:colorTex.createView(),depthView:depthTex.createView(),width:W,height:H};
        pane.T.setDirtyPages(null,true); pane.T.updatePalette(pane.pvr);
        const P=new TAParser(); const parsed=P.parse(ta,ta.length);
        const sn=new Uint32Array(16); sn[0]=(19&0x3F)|((14&0x3F)<<16);
        R.renderFrame(parsed, pane.T, sn, pane.vram, dbg||{}, rt);
        const enc=R._lastEncoder; const bpr=Math.ceil(W*4/256)*256;
        const rb=dev.createBuffer({size:bpr*H,usage:GPUBufferUsage.COPY_DST|GPUBufferUsage.MAP_READ});
        enc.copyTextureToBuffer({texture:colorTex},{buffer:rb,bytesPerRow:bpr},[W,H]);
        dev.queue.submit([enc.finish()]);
        await rb.mapAsync(GPUMapMode.READ);
        const d=new Uint8Array(rb.getMappedRange()).slice(); rb.unmap();
        let nRGB=0; for(let y=0;y<H;y++)for(let x=0;x<W;x++){const i=y*bpr+x*4; if(d[i]|d[i+1]|d[i+2])nRGB++;}
        return {op:parsed.opaque.length,pt:parsed.punchThrough.length,tr:parsed.translucent.length,verts:parsed.vertexCount,nRGB};
    }
    window.__showFrame(0);
    const rf  = await drawAndRead(window.__lastTA, {});
    const er  = await fetch(engUrl); const engTA = new Uint8Array(await er.arrayBuffer());
    const eng = await drawAndRead(engTA, {});
    return { rf, eng };
}, `${BASE}/_ryu_capture/mc_engine_ta.bin`);
console.log('render_frame TA :', JSON.stringify(out.rf));
console.log('engine TA       :', JSON.stringify(out.eng));
const pass = out.rf.nRGB > 0 && out.eng.nRGB > 0;
console.log(pass ? 'PASS: render_frame body draws pixels (sprite base-color fix holds).'
                 : 'FAIL: render_frame body produced 0 pixels.');
console.log(logs.filter(l=>l.includes('ERR')||l.includes('WGSL')).slice(-8).join('\n'));
await browser.close();
process.exit(pass ? 0 : 1);
