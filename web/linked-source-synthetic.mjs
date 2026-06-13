// linked-source-synthetic.mjs — drives the linked view with no emulator. Per frame it emits each
// slot's on-screen position + which struct offsets changed (field-resolution), shaped like a real
// match: pos/screen/anim_timer + the engine cluster churn every frame; sprite_id flares on "actions";
// health on rare "hits"; projectiles spawn from a slot and inherit its identity.
//
// frame = { frameNum, slots:[{ active, screen:{x,y}, changed:[[off,len],...] }], projectiles:[{owner,x,y}] }

const TWO_PI = Math.PI * 2;

export class LinkedSyntheticSource {
  constructor() { this.frame = 0; this._cb = () => {}; this._proj = []; }
  onFrame(cb) { this._cb = cb; }

  advance() {
    const f = ++this.frame;
    const slots = [];
    for (let s = 0; s < 6; s++) {
      // every frame: position, screen anchor, anim timer, and the engine pointer cluster (noise)
      const changed = [[0x034, 8], [0x0E0, 8], [0x142, 2], [0x154, 0x30]];
      // sprite_id flares when this slot "acts" — staggered per slot so they don't sync
      if ((f + s * 13) % 45 < 3) changed.push([0x144, 2], [0x151, 1], [0x14A, 2]);
      // facing flip occasionally
      if ((f + s * 7) % 120 === 0) { changed.push([0x110, 1], [0x1D2, 1]); }
      // rare "hit" → health
      if ((f * (s + 1)) % 300 < 2) changed.push([0x420, 2]);

      // on-screen position: two rows of 3, drifting horizontally
      const lane = s % 3, row = (s / 3) | 0;
      const x = 60 + lane * 140 + Math.sin((f + s * 30) * 0.03) * 40;
      const y = 60 + row * 110;
      slots.push({ active: 1, screen: { x, y }, changed });
    }

    // spawn a projectile from a rotating slot every ~70 frames; advance + cull existing
    if (f % 70 === 0) {
      const owner = (f / 70) % 6 | 0;
      this._proj.push({ owner, x: slots[owner].screen.x + 20, y: slots[owner].screen.y + 30, vx: 6, life: 60 });
    }
    this._proj = this._proj.filter((p) => { p.x += p.vx; return --p.life > 0; });

    this._cb({
      frameNum: f,
      slots,
      projectiles: this._proj.map((p) => ({ owner: p.owner, x: p.x, y: p.y })),
    });
  }
}
