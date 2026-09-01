-- HUD character portraits decoded from DM01 (char-select POL+TEX)
USE NS re DB kb;

UPSERT source:dm01_portraits CONTENT {
  name: "DM01POL.BIN + DM01TEX.BIN",
  kind: "disc_asset",
  note: "Character-select NaomiLib display list + concatenated PVR texture blob; holds the 56-char portrait grid."
};
UPSERT finding:hud_portrait_decode CONTENT {
  name: "hud_portrait_decode",
  status: "confirmed",
  confidence: "high",
  summary: "Real character HUD portraits decoded OFFLINE from disc DM01POL/DM01TEX. The mugshots live in DM01 texture #11 (512x512 RGB565 TWIDDLED), an 8x8 grid of 64x64 cells (56 faces + 8 STAGE/random plates). Faces are stored rotated 90deg (corrected on-screen by bank16 portrait-rotation tables); CCW-rotate to upright. Decode = NaomiLib morton-twiddle + RGB565 (same path as tools/rip_stage.py). POL texture-header table at POL+0x08..POL+0x10, RAM base 0x0ce80000.",
  routines: "bank16 loc_8c1617b8 'Naomi Portraits Rotation Table' (char_id-indexed 0x00..0x3a); loc_8c161a7c 'Dreamcast Portrait Rotation Table'; loc_8c161fec 'Dreamcast Character Select ID Table' (8x8 grid->char_id, 0xff=empty). Per-char FAC files (PLxx_FAC.BIN) load to 0x0c5*8000.. (pl_mem.asm pl_A_FACfile..pl_F_FACfile); bank03 loc_8c0323f8 binds FAC ptr into char+0x184 via memcpy bank12 loc_8c129668. Portrait draw bank0f loc_8c0f4334 selects portrait MODEL via char-struct +0x20.",
  open: "No STATIC sheet-cell->char_id table exists (engine resolves cell->char at runtime via char+0x20). CELL_CHAR in tools/rip_portraits.py is the visually-verified map of 51/56 rendered faces (row-by-row name-verified, uniqueness-guarded). 5 omitted (0x11 Jill, 0x15 Amingo, 0x32 Colossus, 0x35 Blackheart, 0x39 BoneWolverine) -> HUD monogram fallback. To CLOSE: Oracle-dump char+0x20 per char_id in a live all-char match to lock the remaining 5.",
  tool: "tools/rip_portraits.py -> web/render-replica/hud/portraits/portraits.{png,json} ({rects:{'<char_id>':{x,y,w,h}}}); consumed by web/render-replica/hud-client.mjs load()/_plate() auto-upgrade. Deployed prod 149.28.44.118 /var/www/maplecast/render-replica/hud/portraits/ (png md5 ce1476877f17eb55dfcd136d799b9699).",
  char_id_numbering: "Uses ROM internal char_id (Spider-Man=0x0c, SonSon=0x14, Strider=0x05) -- identical to HUD NAMES[] and live char+0x001."
};
RELATE finding:hud_portrait_decode->cites->source:dm01_portraits;
