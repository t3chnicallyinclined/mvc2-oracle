# Decode the captured Effect Poly textures (efx_NNN.raw) to PNG using the dims +
# format from mc_effects.log. 16-bit twiddled PVR (fmt = e4 low byte: 0=ARGB1555,
# 1=RGB565, 2=ARGB4444). Square textures -> full Morton de-twiddle.
import re, os
from PIL import Image

def morton(x, y):
    m = 0
    for i in range(16):
        m |= ((x >> i) & 1) << (2*i)
        m |= ((y >> i) & 1) << (2*i+1)
    return m

def dec(v, f):
    if f == 0:  # ARGB1555
        return (((v>>10)&31)*255//31, ((v>>5)&31)*255//31, (v&31)*255//31, 255 if v&0x8000 else 0)
    if f == 1:  # RGB565
        return (((v>>11)&31)*255//31, ((v>>5)&63)*255//63, (v&31)*255//31, 255)
    return (((v>>8)&15)*17, ((v>>4)&15)*17, (v&15)*17, ((v>>12)&15)*17)  # ARGB4444

D = "effects-capture"
for line in open(f"{D}/mc_effects.log"):
    m = re.match(r'\[EFX\]\s+(\d+)\s+(\d+)x(\d+)\s+\w+\s+(\w+)', line)
    if not m: continue
    idx, w, h, e4 = int(m[1]), int(m[2]), int(m[3]), int(m[4],16)
    if idx > 24 or w==0 or h==0 or w>512 or h>512: continue
    fn = f"{D}/efx_{idx:03d}.raw"
    if not os.path.exists(fn): continue
    data = open(fn,'rb').read(); fmt = e4 & 0xff
    img = Image.new('RGBA',(w,h)); px = img.load()
    for y in range(h):
        for x in range(w):
            o = morton(x,y)*2
            if o+1 < len(data):
                px[x,y] = dec(data[o] | (data[o+1]<<8), fmt)
    img.save(f"{D}/efx_{idx:03d}.png")
    print(f"idx {idx:2d}: {w}x{h} fmt{fmt} -> efx_{idx:03d}.png")
