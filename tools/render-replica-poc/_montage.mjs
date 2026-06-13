import {readFileSync,writeFileSync} from 'node:fs';
import {PNG} from 'pngjs';
const ref=PNG.sync.read(readFileSync('PNG_reference.png'));
const tr=PNG.sync.read(readFileSync('PNG_transpiled.png'));
const W=ref.width,H=ref.height;
// crop the character bbox from each (non-black region) and place side by side at 2x
function bbox(p){let x0=W,y0=H,x1=0,y1=0;for(let y=0;y<H;y++)for(let x=0;x<W;x++){const o=(y*W+x)*4;if(p.data[o]|p.data[o+1]|p.data[o+2]){if(x<x0)x0=x;if(x>x1)x1=x;if(y<y0)y0=y;if(y>y1)y1=y;}}return[x0,y0,x1,y1];}
const ba=bbox(ref),bb=bbox(tr);
console.log('ref bbox',ba,'transpiled bbox',bb);
const pad=4;
function crop(p,b){const[x0,y0,x1,y1]=b;const w=x1-x0+1+pad*2,h=y1-y0+1+pad*2;const out=new PNG({width:w,height:h});for(let y=0;y<h;y++)for(let x=0;x<w;x++){const sx=x0-pad+x,sy=y0-pad+y;const d=(y*w+x)*4;if(sx>=0&&sx<W&&sy>=0&&sy<H){const s=(sy*W+sx)*4;out.data[d]=p.data[s];out.data[d+1]=p.data[s+1];out.data[d+2]=p.data[s+2];out.data[d+3]=255;}else{out.data[d+3]=255;}}return out;}
const ca=crop(ref,ba),cb=crop(tr,bb);
// montage: 3x zoom each, on a gray strip, labeled by position
const S=3,gap=20;
const ch=Math.max(ca.height,cb.height)*S;
const cw=ca.width*S+gap+cb.width*S;
const m=new PNG({width:cw,height:ch});
for(let i=0;i<cw*ch;i++){m.data[i*4]=48;m.data[i*4+1]=48;m.data[i*4+2]=48;m.data[i*4+3]=255;}
function blit(c,ox){for(let y=0;y<c.height*S;y++)for(let x=0;x<c.width*S;x++){const sx=(x/S)|0,sy=(y/S)|0;const s=(sy*c.width+sx)*4;const dx=ox+x,dy=y;if(dx<cw&&dy<ch){const d=(dy*cw+dx)*4;m.data[d]=c.data[s];m.data[d+1]=c.data[s+1];m.data[d+2]=c.data[s+2];m.data[d+3]=255;}}}
blit(ca,0);blit(cb,ca.width*S+gap);
writeFileSync('PNG_montage.png',PNG.sync.write(m));
console.log('wrote PNG_montage.png (LEFT=reference engine quads, RIGHT=transpiled geometry) '+cw+'x'+ch);
