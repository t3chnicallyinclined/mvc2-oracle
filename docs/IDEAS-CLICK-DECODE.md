# Idea: Click-to-Decode — memory location → sprite + animation

Click any object's memory (a char struct, a pool node) on any frame → **decode the fields there and
render the actual sprite/image of that object, and play its animation.** The memory map stops being
abstract bytes and becomes "this memory IS Magneto's current pose — here's the picture." Status:
**idea / extends the linked view + struct inspector**. Reuses the atlas + `sprite-client`/`sprite-gpu`.

## The decode chain (grounded in what we already have)
From a clicked memory location, identify the owning object, then:
1. **Which object** — the clicked address falls in a char slot (`0x8C268340 + slot*0x5A4`) or a pool node
   (`[N, 0x1D0]`, owner via `node+0x80` → slot). (Same correlation as `IDEAS-LINKED-VIEW.md`.)
2. **Identity → atlas key** — read `char_id` (`+0x001`) → the `PL{cid}` atlas; for a pool node use `owner_cid`.
3. **Pose → sprite** — read `sprite_id` (`+0x144`) → `PLxx.json[sprite_id]` → rect + dx/dy → render the quad
   via `sprite-gpu` (the still image for *this* frame). Palette from `+0x25`/`+0x52D` so the skin matches.
4. **Animation — two modes:**
   - **Replay (immediate):** over the captured/streamed frames, `sprite_id`@`+0x144` changes frame to
     frame. Play that recorded sequence = the animation *as it actually happened*. Free once we have frame
     data; pairs with the transport scrub.
   - **Canonical (decoded):** follow `animations`@`+0x168` → the 20-byte cell list (`sprite_id`@cell+0x04,
     `duration`@+0x02) → enumerate the move's full sprite_id sequence and play it at the real durations,
     independent of capture. Needs the cell decode (`tools/rip_gfx2_assembly.py read_cells()` / anotak cell
     semantics) — the SH4-side data the RE expert owns.

## What it unifies
memory map (where) ↔ struct decode (what fields) ↔ atlas (`sprite_id` → image) ↔ renderer (`sprite-gpu`)
↔ anim data (the sequence). It's the visual payoff of the whole stack: hover shows the label, **click
shows the picture**, and play shows the motion.

## Canonical-animation mode: pick a character → pick a move → play it
Beyond replaying captured frames, **browse and play any of a character's animations on demand.** MVC2
animations are **groups (0x00–0x1B)** of **20-byte cells**, each cell carrying `sprite_id`(@+0x04→player+0x144)
+ `duration`(@+0x02→player+0x142), the list terminated by `Ender`(@+0x03 0x80). So an offline catalog
`char → group → ordered [{sprite_id, duration}]` is extractable **with no emulator/ROM** — anotak's
per-character animgroup data is already cached in `re_kb/ingest`. Build `web/anim/PL{HEX}.json` via a
`tools/build_anim_catalog.py`, then the preview player steps each cell's `sprite_id` (atlas lookup) for its
`duration` frames. Optionally name groups as moves via the SPL group-id dispatch (`char_prg/S_PLxx.asm`).
The atlas sprite_id is the same key (masked `&0x7FFF`), so the existing `SpritePreview` lookup works.
UI: a character picker + an animation/group picker → ▶ play.

## UX
- Click a struct/cell or an on-screen box → an **inspector preview** pane shows the decoded sprite (current
  frame), the resolved `{cid, sprite_id, palette, anim_state}`, and a ▶ to play the animation (replay or
  canonical toggle).
- Scrub the transport → the preview tracks the object's pose across frames (the still updates live).
- Click a projectile's pool node → its own sprite renders (owner's atlas, the projectile's `sprite_id`).

## Dependencies / risks
- **Atlas presence** — `PLxx.json/.png` is ROM-derived (from the bring-your-own-ROM setup). Degrade
  gracefully: with no atlas, show the decoded fields + `sprite_id` number but a placeholder image.
- The **canonical animation** mode needs the cell/anim decode (RE-expert territory); the **replay** mode
  needs only the captured `+0x144` history, so ship replay first.
- READ-ONLY (viewer) — decode reads memory, never writes (cardinal rule 4).
- Builds on field-resolution memory (the linked view) + the atlas loader (`sprite-client.loadChar`).
