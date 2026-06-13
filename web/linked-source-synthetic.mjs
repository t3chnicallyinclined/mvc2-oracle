// linked-source-synthetic.mjs — drives the linked view with no emulator. Per frame it emits each
// slot's on-screen position + which struct offsets changed (field-resolution), shaped like a real
// match: pos/screen/anim_timer + the engine cluster churn every frame; sprite_id flares on "actions";
// health on rare "hits"; projectiles spawn from a slot and inherit its identity.
//
// frame = { frameNum, slots:[{ active, screen:{x,y}, changed:[[off,len],...] }], projectiles:[{owner,x,y}] }

const TWO_PI = Math.PI * 2;

// per-slot roster identity for the demo (real char_ids → the inspector resolves names)
const SLOT_CID = [0x2C, 0x17, 0x2A, 0x00, 0x0D, 0x1E];   // Magneto, Cable, Storm, Ryu, Hulk, Akuma

export class LinkedSyntheticSource {
  constructor() {
    this.frame = 0; this._cb = () => {}; this._proj = [];
    this.vals = SLOT_CID.map((cid) => ({ cid, sprite_id: 0x100, health: 1200, facing: 1, pos_x: 0, pos_y: 0 }));
    this.hist = SLOT_CID.map(() => [0x100]);             // per-slot sprite_id history (for replay)
  }
  onFrame(cb) { this._cb = cb; }
  history(slot) { return this.hist[slot]; }

  advance() {
    const f = ++this.frame;
    const slots = [];
    for (let s = 0; s < 6; s++) {
      const v = this.vals[s];
      // every frame: position, screen anchor, anim timer, and the engine pointer cluster (noise)
      const changed = [[0x034, 8], [0x0E0, 8], [0x142, 2], [0x154, 0x30]];
      v.pos_x = Math.sin((f + s * 30) * 0.03) * 120; v.pos_y = (s % 3) * 20;
      // sprite_id flares when this slot "acts" — staggered; advance the pose + record history
      if ((f + s * 13) % 45 < 3) {
        changed.push([0x144, 2], [0x151, 1], [0x14A, 2]);
        v.sprite_id = 0x100 + ((v.sprite_id + 1) % 24);
        const h = this.hist[s]; h.push(v.sprite_id); if (h.length > 240) h.shift();
      }
      if ((f + s * 7) % 120 === 0) { changed.push([0x110, 1], [0x1D2, 1]); v.facing ^= 1; }
      if ((f * (s + 1)) % 300 < 2) { changed.push([0x420, 2]); v.health = Math.max(0, v.health - 80); }

      const lane = s % 3, row = (s / 3) | 0;
      const x = 60 + lane * 140 + Math.sin((f + s * 30) * 0.03) * 40, y = 60 + row * 110;
      slots.push({ active: 1, cid: v.cid, screen: { x, y }, changed, vals: v });
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
