// ta-parser.mjs — PowerVR2 TA command stream → geometry lists
// Vertex layout: 28 bytes = x(f32) y(f32) z(f32) col(u8x4) spc(u8x4) u(f32) v(f32)

function f16(v) { const b = new ArrayBuffer(4); new Uint32Array(b)[0] = v << 16; return new Float32Array(b)[0]; }
function clamp255(f) { return Math.min(255, Math.max(0, (f * 255) | 0)); }

const BYTES_PER_VERTEX = 28;
const VRAM_MASK = 0x7FFFFF; // 8MB

export class TAParser {
    constructor() {
        this._cap = 32768;
        this._buf = new ArrayBuffer(this._cap * BYTES_PER_VERTEX);
        this._f32 = new Float32Array(this._buf);
        this._u8 = new Uint8Array(this._buf);
        this._n = 0;
    }

    _grow() {
        this._cap *= 2;
        const nb = new ArrayBuffer(this._cap * BYTES_PER_VERTEX);
        new Uint8Array(nb).set(this._u8.subarray(0, this._n * BYTES_PER_VERTEX));
        this._buf = nb; this._f32 = new Float32Array(nb); this._u8 = new Uint8Array(nb);
    }

    _vtx(x, y, z, bc, oc, u, v) {
        if (this._n >= this._cap) this._grow();
        const fi = this._n * 7, bi = this._n * BYTES_PER_VERTEX;
        this._f32[fi] = x; this._f32[fi+1] = y; this._f32[fi+2] = z;
        this._u8[bi+12] = (bc>>16)&0xFF; this._u8[bi+13] = (bc>>8)&0xFF; this._u8[bi+14] = bc&0xFF; this._u8[bi+15] = (bc>>24)&0xFF;
        this._u8[bi+16] = (oc>>16)&0xFF; this._u8[bi+17] = (oc>>8)&0xFF; this._u8[bi+18] = oc&0xFF; this._u8[bi+19] = (oc>>24)&0xFF;
        this._f32[fi+5] = u; this._f32[fi+6] = v;
        this._n++;
    }

    parse(taBuffer, taSize) {
        this._n = 0;
        const op = [], pt = [], tr = [];
        // Render pass tracking — each pass records cumulative poly counts
        const renderPasses = [];
        let listsEnded = new Set(); // track which list types have ended in current pass
        let curList = -1, curPPList = null, curPP = null, tileclip = 0;
        let cISP = 0, cTSP = 0, cTCW = 0, cPCW = 0, cObj = 0;
        let fbc = [0xFF,0xFF,0xFF,0xFF], foc = [0,0,0,0];
        const view = new DataView(taBuffer.buffer, taBuffer.byteOffset, taSize);
        let off = 0;

        const startList = (lt) => { if (curList !== -1) return;
            // If this list type was already ended in current pass, start new pass
            if (listsEnded.has(lt)) {
                renderPasses.push({ op_count: op.length, pt_count: pt.length, tr_count: tr.length });
                listsEnded.clear();
            }
            curList = lt;
            curPPList = lt === 0 ? op : lt === 4 ? pt : lt === 2 ? tr : null; curPP = null; };
        const endList = () => {
            if (curPP && curPP.count === 0) {
                curPP.count = this._n - curPP.first;
                if (curPP.count === 0 && curPPList) curPPList.pop();
            }
            if (curList >= 0) listsEnded.add(curList);
            curPP = null; curPPList = null; curList = -1;
        };
        const newPP = () => {
            // Finalize previous PP before starting new one
            if (curPP && curPP.count === 0) {
                curPP.count = this._n - curPP.first;
                if (curPP.count === 0 && curPPList) curPPList.pop();
            }
            curPP = { first: this._n, count: 0, isp: cISP, tsp: cTSP, tcw: cTCW, pcw: cPCW, tileclip };
            if (curPPList) curPPList.push(curPP);
        };
        const endStrip = () => { if (!curPP) return; curPP.count = this._n - curPP.first;
            if (curPP.count > 0 && curPPList) { const p = curPP;
                curPP = { first: this._n, count: 0, isp: p.isp, tsp: p.tsp, tcw: p.tcw, pcw: p.pcw, tileclip: p.tileclip };
                curPPList.push(curPP); }
        };

        while (off + 32 <= taSize) {
            const pcw = view.getUint32(off, true);
            const paraType = (pcw >> 29) & 7;

            if (paraType === 0) { endList(); off += 32; continue; }
            if (paraType === 1) { // UserTileClip — sets clip RECTANGLE only
                const xmin = view.getUint32(off + 12, true) & 63;
                const ymin = view.getUint32(off + 16, true) & 31;
                const xmax = view.getUint32(off + 20, true) & 63;
                const ymax = view.getUint32(off + 24, true) & 31;
                // Preserve mode bits (set per-polygon), update rect
                tileclip = (tileclip & 0xF0000000) | xmin | (xmax << 6) | (ymin << 12) | (ymax << 17);
                off += 32; continue;
            }
            if (paraType === 2) { off += 32; continue; } // ObjectListSet
            if (paraType === 3 || paraType === 6) { off += 32; continue; } // Reserved

            if (paraType === 4) { // Polygon param
                const lt = (pcw >> 24) & 7;
                if (curList === -1) startList(lt);
                if (curList === 1 || curList === 3) { off += 32; continue; } // mod vol
                // Set clip MODE from polygon's User_Clip field (PCW bits 16-17)
                tileclip = (tileclip & 0x0FFFFFFF) | (((pcw >> 16) & 3) << 28);
                cPCW = pcw; cObj = pcw & 0xFF;
                cISP = view.getUint32(off + 4, true);
                cTSP = view.getUint32(off + 8, true);
                cTCW = view.getUint32(off + 12, true);
                const colType = (cObj >> 4) & 3, vol = (cObj >> 6) & 1;
                // 64B poly params (intensity type 2 with offset, or type 4 with volumes)
                if (colType === 2 && !vol && (cObj>>2)&1) {
                    // PolyParam2: 64B — face base + offset colors in second 32B
                    if (off + 64 <= taSize) {
                        fbc[3] = clamp255(view.getFloat32(off+32, true));
                        fbc[0] = clamp255(view.getFloat32(off+36, true));
                        fbc[1] = clamp255(view.getFloat32(off+40, true));
                        fbc[2] = clamp255(view.getFloat32(off+44, true));
                        foc[3] = clamp255(view.getFloat32(off+48, true));
                        foc[0] = clamp255(view.getFloat32(off+52, true));
                        foc[1] = clamp255(view.getFloat32(off+56, true));
                        foc[2] = clamp255(view.getFloat32(off+60, true));
                        off += 64;
                    } else { off += 32; }
                } else if ((colType >= 1 && vol)) {
                    off += (off + 64 <= taSize) ? 64 : 32;
                } else {
                    if (colType === 1 && !vol) { // intensity type 1 — face base color only
                        fbc[3] = clamp255(view.getFloat32(off+16, true));
                        fbc[0] = clamp255(view.getFloat32(off+20, true));
                        fbc[1] = clamp255(view.getFloat32(off+24, true));
                        fbc[2] = clamp255(view.getFloat32(off+28, true));
                    } else if (colType === 2 && !vol) {
                        // intensity type 1 without offset — face base color only
                        fbc[3] = clamp255(view.getFloat32(off+16, true));
                        fbc[0] = clamp255(view.getFloat32(off+20, true));
                        fbc[1] = clamp255(view.getFloat32(off+24, true));
                        fbc[2] = clamp255(view.getFloat32(off+28, true));
                    }
                    off += 32;
                }
                if (curPPList) newPP();
                continue;
            }

            if (paraType === 5) { // Sprite param
                const lt = (pcw >> 24) & 7;
                if (curList === -1) startList(lt);
                // Set clip MODE from sprite's User_Clip field (PCW bits 16-17)
                tileclip = (tileclip & 0x0FFFFFFF) | (((pcw >> 16) & 3) << 28);
                cPCW = pcw; cObj = pcw & 0xFF;
                cISP = view.getUint32(off + 4, true);
                // Sprites flip cull mode (ta_vtx.cpp line 979)
                cISP ^= (1 << 27);
                cTSP = view.getUint32(off + 8, true);
                cTCW = view.getUint32(off + 12, true);
                const sbc = view.getUint32(off + 16, true);
                fbc[0] = (sbc>>16)&0xFF; fbc[1] = (sbc>>8)&0xFF; fbc[2] = sbc&0xFF; fbc[3] = (sbc>>24)&0xFF;
                if (curPPList) newPP();
                off += 32; continue;
            }

            if (paraType === 7) { // Vertex
                if (!curPPList || !curPP) { off += 32; continue; }
                const eos = (pcw >> 28) & 1;
                const tex = (cObj >> 3) & 1, colType = (cObj >> 4) & 3, uv16 = cObj & 1, vol = (cObj >> 6) & 1;
                const isSpr = ((cPCW >> 29) & 7) === 5;

                if (isSpr && off + 64 <= taSize) {
                    // Sprite vertex data (TA_Sprite1A + TA_Sprite1B)
                    // Flycast sprite vertex order: cv[0]=D(x3,y3) cv[1]=C(x2,y2,z2) cv[2]=A(x0,y0,z0) cv[3]=B(x1,y1,z1)
                    // Strip renders as: D,C,A,B → triangles DCA + CAB
                    const Ax=view.getFloat32(off+4,true),Ay=view.getFloat32(off+8,true),Az=view.getFloat32(off+12,true);
                    const Bx=view.getFloat32(off+16,true),By=view.getFloat32(off+20,true),Bz=view.getFloat32(off+24,true);
                    const Cx=view.getFloat32(off+28,true),Cy=view.getFloat32(off+32,true),Cz=view.getFloat32(off+36,true);
                    const Dx=view.getFloat32(off+40,true),Dy=view.getFloat32(off+44,true);
                    let Au=0,Av=0,Bu=0,Bv=0,Cu=0,Cv=0;
                    if (tex) { Av=f16(view.getUint16(off+52,true)); Au=f16(view.getUint16(off+54,true));
                        Bv=f16(view.getUint16(off+56,true)); Bu=f16(view.getUint16(off+58,true));
                        Cv=f16(view.getUint16(off+60,true)); Cu=f16(view.getUint16(off+62,true)); }
                    // Calculate D's Z and UV via plane equation (CaclulateSpritePlane)
                    // A=cv[2], B=cv[3], C=cv[1], P=cv[0] (D)
                    const ACx=Cx-Ax,ACy=Cy-Ay,ACz=Cz-Az;
                    const ABx=Bx-Ax,ABy=By-Ay,ABz=Bz-Az;
                    const APx=Dx-Ax,APy=Dy-Ay;
                    const ABu=Bu-Au,ABv=Bv-Av,ACu=Cu-Au,ACv=Cv-Av;
                    const k3=ACx*ABy-ACy*ABx;
                    const k2=k3!==0?(APx*ABy-APy*ABx)/k3:0;
                    const k1=ABx!==0?(Dx-Ax-k2*ACx)/ABx:(ABy!==0?(Dy-Ay-k2*ACy)/ABy:0);
                    const Dz=Az+k1*ABz+k2*ACz;
                    const Du=Au+k1*ABu+k2*ACu;
                    const Dv=Av+k1*ABv+k2*ACv;
                    const bc=(fbc[3]<<24)|(fbc[0]<<16)|(fbc[1]<<8)|fbc[2];
                    const oc=(foc[3]<<24)|(foc[0]<<16)|(foc[1]<<8)|foc[2];
                    // Emit in flycast strip order: D, C, A, B
                    this._vtx(Dx,Dy,Dz,bc,oc,Du,Dv);
                    this._vtx(Cx,Cy,Cz,bc,oc,Cu,Cv);
                    this._vtx(Ax,Ay,Az,bc,oc,Au,Av);
                    this._vtx(Bx,By,Bz,bc,oc,Bu,Bv);
                    off += 64; endStrip(); continue;
                }

                if (!tex) {
                    const x=view.getFloat32(off+4,true),y=view.getFloat32(off+8,true),z=view.getFloat32(off+12,true);
                    let bc = 0xFFFFFFFF;
                    if (colType===0) bc = view.getUint32(off+24,true);
                    else if (colType===1) { bc=(clamp255(view.getFloat32(off+16,true))<<24)|(clamp255(view.getFloat32(off+20,true))<<16)|
                        (clamp255(view.getFloat32(off+24,true))<<8)|clamp255(view.getFloat32(off+28,true)); }
                    this._vtx(x,y,z,bc,0,0,0); off += 32;
                } else if (!vol) {
                    if (colType===0) {
                        const x=view.getFloat32(off+4,true),y=view.getFloat32(off+8,true),z=view.getFloat32(off+12,true);
                        let u,v;
                        if (!uv16) { u=view.getFloat32(off+16,true); v=view.getFloat32(off+20,true); }
                        else { v=f16(view.getUint16(off+16,true)); u=f16(view.getUint16(off+18,true)); }
                        this._vtx(x,y,z,view.getUint32(off+24,true),view.getUint32(off+28,true),u,v); off += 32;
                    } else if (colType===1 && off+64<=taSize) {
                        const x=view.getFloat32(off+4,true),y=view.getFloat32(off+8,true),z=view.getFloat32(off+12,true);
                        let u,v;
                        if (!uv16) { u=view.getFloat32(off+16,true); v=view.getFloat32(off+20,true); }
                        else { v=f16(view.getUint16(off+16,true)); u=f16(view.getUint16(off+18,true)); }
                        const bc=(clamp255(view.getFloat32(off+32,true))<<24)|(clamp255(view.getFloat32(off+36,true))<<16)|
                            (clamp255(view.getFloat32(off+40,true))<<8)|clamp255(view.getFloat32(off+44,true));
                        const oc=(clamp255(view.getFloat32(off+48,true))<<24)|(clamp255(view.getFloat32(off+52,true))<<16)|
                            (clamp255(view.getFloat32(off+56,true))<<8)|clamp255(view.getFloat32(off+60,true));
                        this._vtx(x,y,z,bc,oc,u,v); off += 64;
                    } else {
                        const x=view.getFloat32(off+4,true),y=view.getFloat32(off+8,true),z=view.getFloat32(off+12,true);
                        let u,v;
                        if (!uv16) { u=view.getFloat32(off+16,true); v=view.getFloat32(off+20,true); }
                        else { v=f16(view.getUint16(off+16,true)); u=f16(view.getUint16(off+18,true)); }
                        const bi=view.getFloat32(off+24,true);
                        const oi=view.getFloat32(off+28,true);
                        const bc=(fbc[3]<<24)|(((fbc[0]*bi)&0xFF)<<16)|(((fbc[1]*bi)&0xFF)<<8)|((fbc[2]*bi)&0xFF);
                        const oc=(foc[3]<<24)|(((foc[0]*oi)&0xFF)<<16)|(((foc[1]*oi)&0xFF)<<8)|((foc[2]*oi)&0xFF);
                        this._vtx(x,y,z,bc,oc,u,v); off += 32;
                    }
                } else { off += 32; } // two-volume — skip

                if (eos) endStrip();
                continue;
            }
            off += 32;
        }

        // Finalize
        for (const list of [op, pt, tr]) {
            if (list.length > 0) { const last = list[list.length-1];
                if (last.count === 0) { last.count = this._n - last.first; if (last.count === 0) list.pop(); } }
        }
        // Final render pass
        renderPasses.push({ op_count: op.length, pt_count: pt.length, tr_count: tr.length });
        return { vertexData: this._u8.subarray(0, this._n * BYTES_PER_VERTEX), vertexCount: this._n, opaque: op, punchThrough: pt, translucent: tr, renderPasses };
    }

    // Fill background polygon from PVR registers + VRAM (matches flycast FillBGP)
    // Must be called AFTER parse() and inserts opaque[0] as a full-screen background quad
    fillBGP(result, pvrRegs, vram) {
        const rv = new DataView(pvrRegs.buffer, pvrRegs.byteOffset, pvrRegs.byteLength);
        const paramBase = rv.getUint32(0x20, true) & 0xF00000;
        const ispBgT = rv.getUint32(0x8C, true);
        const ispBgD = rv.getFloat32(0x88, true);

        // ISP_BACKGND_T fields
        const tagOffset = ispBgT & 7;
        const tagAddress = (ispBgT >> 3) & 0x1FFFFF;
        const skip = (ispBgT >> 24) & 7;
        const shadow = (ispBgT >> 27) & 1;

        const stripBase = (paramBase + tagAddress * 4) & VRAM_MASK;
        let stripVs = 3 + skip;
        stripVs *= 4; // bytes per vertex entry

        const vertexPtr0 = tagOffset * stripVs + stripBase + 12; // +12 skips ISP/TSP/TCW

        // Read ISP/TSP/TCW from VRAM at strip_base
        const vv = new DataView(vram.buffer, vram.byteOffset, vram.byteLength);
        if (stripBase + 12 > vram.length) return;
        const bgISP = vv.getUint32(stripBase, true);
        const bgTSP = vv.getUint32(stripBase + 4, true);
        const bgTCW = vv.getUint32(stripBase + 8, true);

        // Decode ISP fields to build PCW
        const isTexture = (bgISP >> 25) & 1;
        const isOffset = (bgISP >> 24) & 1;
        const isGouraud = (bgISP >> 23) & 1;
        const isUV16 = (bgISP >> 22) & 1;
        const bgPCW = (isUV16) | (isGouraud << 1) | (isOffset << 2) | (isTexture << 3);

        // Read 3 vertices from VRAM
        const bgVerts = [];
        let vptr = vertexPtr0;
        for (let i = 0; i < 3; i++) {
            if (vptr + 12 > vram.length) return;
            const x = vv.getFloat32(vptr, true);
            const y = vv.getFloat32(vptr + 4, true);
            const z = vv.getFloat32(vptr + 8, true);
            let u = 0, v = 0, col = 0xFFFFFFFF, spc = 0;
            let cptr = vptr + 12;

            if (isTexture) {
                if (isUV16) {
                    const uvPacked = vv.getUint32(cptr, true);
                    u = f16(uvPacked & 0xFFFF);
                    v = f16((uvPacked >> 16) & 0xFFFF);
                    cptr += 4;
                } else {
                    u = vv.getFloat32(cptr, true);
                    v = vv.getFloat32(cptr + 4, true);
                    cptr += 8;
                }
            }
            if (cptr + 4 <= vram.length) {
                col = vv.getUint32(cptr, true);
                cptr += 4;
            }
            if (isOffset && cptr + 4 <= vram.length) {
                spc = vv.getUint32(cptr, true);
            }
            bgVerts.push({ x, y, z, u, v, col, spc });
            vptr += stripVs;
        }

        // Background depth
        const bgDepth = Math.max(ispBgD - 1e-6, 1e-11);

        // Build 4-vertex quad
        let v0, v1, v2, v3;
        if (!isTexture) {
            // Non-textured: full-screen quad
            v0 = { x: -256, y: 0, z: bgDepth, u: 0, v: 0, col: bgVerts[0].col, spc: bgVerts[0].spc };
            v1 = { x: 896, y: 0, z: bgDepth, u: 0, v: 0, col: bgVerts[1].col, spc: bgVerts[1].spc };
            v2 = { x: -256, y: 480, z: bgDepth, u: 0, v: 0, col: bgVerts[2].col, spc: bgVerts[2].spc };
            v3 = { x: 896, y: 480, z: bgDepth, u: 0, v: 0, col: bgVerts[2].col, spc: bgVerts[2].spc };
        } else {
            // Textured: extend horizontally
            v0 = { ...bgVerts[0], z: bgDepth };
            v1 = { ...bgVerts[1], z: bgDepth };
            v2 = { ...bgVerts[2], z: bgDepth };
            const deltaU = (v1.u - v0.u) * 0.4;
            v0.x -= 256; v0.u -= deltaU;
            v1.x += 256; v1.u += deltaU;
            v2.x -= 256; v2.u -= deltaU;
            v3 = { ...v2, x: v1.x, u: v1.u };
        }

        // Emit 4 background vertices at the START of the vertex buffer
        // Shift all existing vertices forward by 4
        const oldN = this._n;
        const shiftBy = 4;
        // Grow buffer if needed
        while (this._n + shiftBy > this._cap) this._grow();

        // Shift existing vertex data forward
        const shiftBytes = shiftBy * BYTES_PER_VERTEX;
        this._u8.copyWithin(shiftBytes, 0, oldN * BYTES_PER_VERTEX);
        this._n = oldN + shiftBy;

        // Write background vertices at position 0-3
        const emit = (idx, vtx) => {
            const fi = idx * 7, bi = idx * BYTES_PER_VERTEX;
            this._f32[fi] = vtx.x; this._f32[fi+1] = vtx.y; this._f32[fi+2] = vtx.z;
            // Packed color ARGB → RGBA bytes
            this._u8[bi+12] = (vtx.col>>16)&0xFF;
            this._u8[bi+13] = (vtx.col>>8)&0xFF;
            this._u8[bi+14] = vtx.col&0xFF;
            this._u8[bi+15] = (vtx.col>>24)&0xFF;
            this._u8[bi+16] = (vtx.spc>>16)&0xFF;
            this._u8[bi+17] = (vtx.spc>>8)&0xFF;
            this._u8[bi+18] = vtx.spc&0xFF;
            this._u8[bi+19] = (vtx.spc>>24)&0xFF;
            this._f32[fi+5] = vtx.u; this._f32[fi+6] = vtx.v;
        };
        emit(0, v0); emit(1, v1); emit(2, v2); emit(3, v3);

        // Update all poly param first/count to account for the shift
        for (const list of [result.opaque, result.punchThrough, result.translucent]) {
            for (const pp of list) { pp.first += shiftBy; }
        }

        // Insert background poly as opaque[0]
        const bgPP = {
            first: 0, count: 4,
            isp: (7 << 29) | (bgISP & 0x1FFFFFFF), // DepthMode=7 (always), keep rest
            tsp: bgTSP, tcw: bgTCW,
            pcw: (4 << 29) | bgPCW, // ParaType=4, obj_ctrl from ISP
            tileclip: 0,
        };
        // Force DepthMode=7 (always pass) and CullMode=0 (no cull)
        bgPP.isp = (bgPP.isp & ~(7 << 27)) | (0 << 27); // CullMode=0
        bgPP.isp = (bgPP.isp & ~(7 << 29)) | (7 << 29); // DepthMode=7

        result.opaque.unshift(bgPP);
        result.vertexData = this._u8.subarray(0, this._n * BYTES_PER_VERTEX);
        result.vertexCount = this._n;
    }
}
