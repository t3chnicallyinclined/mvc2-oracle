// shaders.mjs — 🤯 INSANE EFFECTS EDITION
// 20 effects packed into bits 12-31 of fu.packed. Time in fu.atv.

export const vertexShader = /* wgsl */ `
struct Uniforms { ndcMat: mat4x4<f32> };
@group(0) @binding(0) var<uniform> uniforms: Uniforms;
struct VIn { @location(0) pos: vec3<f32>, @location(1) col: vec4<f32>, @location(2) spc: vec4<f32>, @location(3) uv: vec2<f32> };
struct VOut { @builtin(position) position: vec4<f32>, @location(0) vb: vec4<f32>, @location(1) vo: vec4<f32>, @location(2) vuv: vec3<f32> };
@vertex fn vs_main(in: VIn) -> VOut {
    var o: VOut;
    let vp = uniforms.ndcMat * vec4<f32>(in.pos, 1.0);
    o.vb = in.col; o.vo = in.spc;
    o.vuv = vec3<f32>(in.uv * in.pos.z, in.pos.z);
    o.position = vec4<f32>(vp.xy, 0.0, 1.0);
    return o;
}
`;

export const fragmentShader = /* wgsl */ `
struct FU { atv: f32, si: u32, ht: u32, ua: u32, ita: u32, ho: u32, at: u32, packed: u32 };
@group(0) @binding(1) var<uniform> fu: FU;
@group(1) @binding(0) var tex: texture_2d<f32>;
@group(1) @binding(1) var ts: sampler;
struct FIn { @location(0) vb: vec4<f32>, @location(1) vo: vec4<f32>, @location(2) vuv: vec3<f32> };
struct FOut { @builtin(frag_depth) depth: f32, @location(0) color: vec4<f32> };

fn h2r(p:f32,q:f32,t2:f32)->f32{var t=t2;if(t<0){t+=1;}if(t>1){t-=1;}
if(t<1.0/6.0){return p+(q-p)*6.0*t;}if(t<.5){return q;}if(t<2.0/3.0){return p+(q-p)*(2.0/3.0-t)*6.0;}return p;}
fn rgb2hsl(c:vec3<f32>)->vec3<f32>{let mx=max(c.r,max(c.g,c.b));let mn=min(c.r,min(c.g,c.b));let l=(mx+mn)/2.0;
if(mx==mn){return vec3<f32>(0,0,l);}let d=mx-mn;let s=select(d/(2.0-mx-mn),d/(mx+mn),l>.5);
var h=0.0;if(mx==c.r){h=(c.g-c.b)/d+select(0.0,6.0,c.g<c.b);}else if(mx==c.g){h=(c.b-c.r)/d+2.0;}else{h=(c.r-c.g)/d+4.0;}
return vec3<f32>(h/6.0,s,l);}
fn hsl2rgb(hsl:vec3<f32>)->vec3<f32>{if(hsl.y==0){return vec3<f32>(hsl.z);}
let q=select(hsl.z+hsl.y-hsl.z*hsl.y,hsl.z*(1.0+hsl.y),hsl.z<.5);let p=2.0*hsl.z-q;
return vec3<f32>(h2r(p,q,hsl.x+1.0/3.0),h2r(p,q,hsl.x),h2r(p,q,hsl.x-1.0/3.0));}
fn hash(p:vec2<f32>)->f32{return fract(sin(dot(p,vec2<f32>(12.9898,78.233)))*43758.5453);}

@fragment fn fs_main(in: FIn) -> FOut {
    var o: FOut;
    let iw=in.vuv.z; let sw=select(iw,0.00001,abs(iw)<0.00001);
    let uv=in.vuv.xy/sw; let fp=in.vuv.xy/sw; // screen pos
    let dbg=fu.packed&0xFFu; let isTr=(fu.packed>>9u)&1u;
    let fx=fu.packed>>12u; let t=fu.atv;

    var c=in.vb; var ofs=in.vo;
    if(fu.ua==0u){c.a=1.0;}
    if(fu.ht==1u){var tc=textureSampleLevel(tex,ts,uv,0.0);if(fu.ita==1u){tc.a=1.0;}
        if(fu.si==0u){c=tc;}else if(fu.si==1u){c=vec4<f32>(c.rgb*tc.rgb,tc.a);}
        else if(fu.si==2u){c=vec4<f32>(mix(c.rgb,tc.rgb,tc.a),c.a);}else{c=c*tc;}
        if(fu.ho==1u){c=vec4<f32>(c.rgb+ofs.rgb,c.a);}}
    c=clamp(c,vec4<f32>(0.0),vec4<f32>(1.0));
    if(fu.at==1u){let qa=floor(c.a*255.0+.5)/255.0;if(fu.atv>qa){discard;}c.a=1.0;}
    if(c.a<0.004){discard;}

    if(dbg==1u){c=vec4<f32>(c.rgb,1);}else if(dbg==2u){c=vec4<f32>(fract(uv.x),fract(uv.y),0,1);}
    else if(dbg==3u){let d=log2(1.0+max(100000.0*iw,-0.999999))/34.0;c=vec4<f32>(d,d,d,1);}
    else if(dbg==4u){c=vec4<f32>(c.a,c.a,c.a,1);}

    // ═══════════ 🤯 20 INSANE EFFECTS ═══════════

    // 0: 🌀 Acid Trip
    if((fx&1u)!=0u){let sw2=sin(fp.x*.01+t*2)*.3+sin(fp.y*.013+t*1.7)*.3;
        var h=rgb2hsl(c.rgb);h.x=fract(h.x+sw2+t*.1);h.y=min(h.y*2.0,1.0);
        h.z=clamp(h.z+sin(fp.x*.02+fp.y*.015+t*3)*.15,.1,.95);c=vec4<f32>(hsl2rgb(h),c.a);}

    // 1: 💀 X-Ray
    if((fx&2u)!=0u){let l=dot(c.rgb,vec3<f32>(.3,.6,.1));let b=1.0-l;c=vec4<f32>(b*.7,b*.85,b*1.0,c.a);}

    // 2: 🎵 Audio Visualizer
    if((fx&4u)!=0u){let bx=floor(fp.x/20.0);let bh=abs(sin(bx*.7+t*4.0+bx*bx*.01))*.7+.1;
        let by=1.0-fp.y/480.0;if(by<bh){let hue=bx/32.0;
        c=vec4<f32>(mix(c.rgb,hsl2rgb(vec3<f32>(fract(hue+t*.1),.9,.5)),.6),c.a);}}

    // 3: 🕳️ Black Hole
    if((fx&8u)!=0u&&fu.ht==1u){let ctr=vec2<f32>(320.0,240.0);let dl=fp-ctr;let ds=length(dl);
        let w2=80.0/(ds+40.0)*sin(t*2.0)*.01;let wuv=uv+normalize(in.vuv.xy/sw-ctr)*w2;
        c=vec4<f32>(textureSampleLevel(tex,ts,wuv,0.0).rgb,c.a);}

    // 4: ⚡ Lightning
    if((fx&16u)!=0u){let seed=floor(t*8.0);let bx2=fract(sin(seed*43.17)*1000.0)*640.0;
        let db=abs(fp.x-bx2);let br=abs(sin(fp.y*.1+seed*7.0))*30.0;
        if(db<br+2.0){let bright=1.0-db/(br+2.0);c=vec4<f32>(c.rgb+vec3<f32>(.7,.7,1)*bright*bright,c.a);}}

    // 5: 🌌 Matrix Rain
    if((fx&32u)!=0u){let col2=floor(fp.x/12.0);let spd=fract(sin(col2*127.1)*311.7)*2.0+1.0;
        let cy=fract(-t*spd*.3+col2*.1);let sy=fp.y/480.0;let trail=1.0-abs(sy-cy)*8.0;
        if(trail>0.0){let cc=fract(sin(floor(fp.y/14.0+t*spd)*col2*17.0)*43758.5);
        if(cc>.5){c=vec4<f32>(c.r,min(c.g+trail*.8,1.0),c.b,c.a);}}}

    // 6: 💫 Speed Lines
    if((fx&64u)!=0u){let ctr2=vec2<f32>(320,240);let dr=normalize(fp-ctr2);let ds2=length(fp-ctr2)/400.0;
        let la=atan2(dr.y,dr.x)*20.0;if(step(.7,fract(la+t*3.0))>.5&&ds2>.3){c=vec4<f32>(c.rgb+vec3<f32>(.3,.3,.5)*ds2,c.a);}}

    // 7: 🔮 Crystal Ball
    if((fx&128u)!=0u&&fu.ht==1u){let ctr3=vec2<f32>(320,240);let dl2=fp-ctr3;let ds3=length(dl2);
        if(ds3<200.0){let nm=ds3/200.0;let bg=nm*nm;let fuv=uv+(in.vuv.xy/sw-ctr3)*.001*bg*5.0;
        c=vec4<f32>(textureSampleLevel(tex,ts,fuv,0.0).rgb,c.a);if(ds3>180.0){c=vec4<f32>(c.rgb+.3,c.a);}}}

    // 8: 🫠 Melt
    if((fx&256u)!=0u&&fu.ht==1u){let ma=sin(fp.x*.03+t)*.01+sin(fp.x*.07+t*1.3)*.005;
        c=vec4<f32>(textureSampleLevel(tex,ts,uv+vec2<f32>(0.0,ma*fp.y*.01),0.0).rgb,c.a);}

    // 9: 🪩 Disco
    if((fx&512u)!=0u){let s1=vec2<f32>(320+sin(t*1.5)*200,240+cos(t*1.1)*150);
        let s2=vec2<f32>(320+sin(t*2.1+2)*200,240+cos(t*1.7+1)*150);
        let s3=vec2<f32>(320+sin(t*1.3+4)*200,240+cos(t*2.3+3)*150);
        c=vec4<f32>(c.r+200.0/(length(fp-s1)+50.0)*.3,c.g+200.0/(length(fp-s2)+50.0)*.3,c.b+200.0/(length(fp-s3)+50.0)*.3,c.a);}

    // 10: 💥 Comic Book
    if((fx&1024u)!=0u){let lm=dot(c.rgb,vec3<f32>(.3,.6,.1));let dsz=3.0+lm*4.0;
        let dp=fract(fp/8.0)-.5;let dt=length(dp)*8.0;let ht=step(dt,dsz);
        let ex=abs(dpdx(lm));let ey=abs(dpdy(lm));let eg=clamp((ex+ey)*20.0,0.0,1.0);
        c=vec4<f32>(c.rgb*ht*(1.0-eg),c.a);}

    // 11: 📺 CRT Retro
    if((fx&2048u)!=0u){let sy=pow(sin(fp.y*1.5)*.5+.5,.5)*.3+.7;c=vec4<f32>(c.rgb*sy,c.a);
        let sp=u32(floor(fp.x*2.0))%3u;
        if(sp==0u){c.g*=.85;c.b*=.7;}else if(sp==1u){c.r*=.7;c.b*=.85;}else{c.r*=.7;c.g*=.85;}
        let cd=abs(fp.x/640.0-.5)*2.0;c=vec4<f32>(c.rgb*(1.0-cd*cd*.15),c.a);}

    // 12: ⚡ Glitch
    if((fx&4096u)!=0u){let tr=step(.94,fract(sin(floor(fp.y*.2+t*12)*43.17)*1000));
        if(tr>.5){c=vec4<f32>(c.gbr,c.a);}
        if(step(.99,fract(sin(t*3.7)*100))>.5&&fu.ht==1u){c=textureSampleLevel(tex,ts,uv+vec2<f32>(sin(t*50.0)*.02,0.0),0.0);}}

    // 13: 🌙 Night Vision
    if((fx&8192u)!=0u){let lm2=dot(c.rgb,vec3<f32>(.3,.6,.1));let n2=hash(fp*.1+vec2<f32>(t*7.0,t*5.0))*.06;
        let sc=fp/vec2<f32>(640,480)*2.0-1.0;let vg=1.0-dot(sc,sc)*.4;
        c=vec4<f32>(.02,(lm2*1.8+n2)*vg,.02,c.a);}

    // 14: 🔥 Thermal
    if((fx&16384u)!=0u){let l2=dot(c.rgb,vec3<f32>(.3,.6,.1));var th:vec3<f32>;
        if(l2<.25){th=mix(vec3<f32>(0,0,.3),vec3<f32>(0,0,1),l2*4.0);}
        else if(l2<.5){th=mix(vec3<f32>(0,0,1),vec3<f32>(0,1,0),(l2-.25)*4.0);}
        else if(l2<.75){th=mix(vec3<f32>(0,1,0),vec3<f32>(1,1,0),(l2-.5)*4.0);}
        else{th=mix(vec3<f32>(1,1,0),vec3<f32>(1,0,0),(l2-.75)*4.0);}c=vec4<f32>(th,c.a);}

    // 15: 🌊 Underwater
    if((fx&32768u)!=0u){let wv=sin(fp.y*.015+t*2)*.004;
        if(fu.ht==1u){let tc2=textureSampleLevel(tex,ts,uv+vec2<f32>(wv,wv*.5),0.0);c=vec4<f32>(tc2.r*.6,tc2.g*.8,min(tc2.b*1.3,1.0),c.a);}
        else{c=vec4<f32>(c.r*.6,c.g*.8,min(c.b*1.3,1.0),c.a);}}

    // ═══════ 🎮 CHARACTER ONLY (isTr==1) ═══════

    // 16: 💎 Char Glow
    if((fx&65536u)!=0u&&isTr==1u){let b=dot(c.rgb,vec3<f32>(.3,.6,.1));
        let pulse=sin(t*4.0)*.15+.85;c=vec4<f32>(c.rgb+vec3<f32>(0,b*.5,b*.6)*pulse,c.a);}

    // 17: 🌈 Char Rainbow
    if((fx&131072u)!=0u&&isTr==1u){var h2=rgb2hsl(c.rgb);h2.x=fract(h2.x+t*.5+fp.y*.002);
        h2.y=max(h2.y,.8);h2.z=max(h2.z,.3);c=vec4<f32>(hsl2rgb(h2),c.a);}

    // 18: 🔥 Char Fire
    if((fx&262144u)!=0u&&isTr==1u){let b2=dot(c.rgb,vec3<f32>(.3,.6,.1));
        let fn2=hash(fp*.05+vec2<f32>(t*8.0,t*3.0));let fh=1.0-clamp((fp.y-150.0)/200.0,0.0,1.0);let fire=fh*fn2;
        c=vec4<f32>(min(c.r+fire*.8,1.0),c.g+fire*.3,c.b*.5,c.a);}

    // 19: 👻 Char Ghost
    if((fx&524288u)!=0u&&isTr==1u){let pulse2=sin(t*2.0)*.2+.5;
        c=vec4<f32>(c.r*.3+.1,c.g*.3+.15,min(c.b*.5+.3,1.0),c.a*pulse2);}

    let logDepth=log2(1.0+max(100000.0*iw,-0.999999))/34.0;
    o.depth=logDepth;
    o.color=clamp(c,vec4<f32>(0.0),vec4<f32>(1.0));
    return o;
}
`;
