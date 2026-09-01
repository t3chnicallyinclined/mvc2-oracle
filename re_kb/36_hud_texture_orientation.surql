USE NS re DB kb;
-- ============================================================================
-- re_kb 36 — HUD texture Y-orientation: names(ParaType-5 sprite) flip, portraits
-- (ParaType-4 poly) upright. CONFIRMED root cause = client UV-corner mapping, NOT
-- the texture decoder. Traced from flycast source + live prod VRAM probe (font_tw
-- upright). [finding:hud_texture_orientation_sprite_vs_poly]
-- ============================================================================

-- Sources (flycast static + live capture)
UPSERT source:flycast_texconv_twop SET
  kind = 'flycast_source', path = 'core/rend/texconv.cpp',
  detail = 'twop()/detwiddle gen L31-79,169-171; texture_TW row-walk L386-406; '
        || 'PixelBuffer rmovey/data L96-120 (core/rend/texconv.h). Decode orientation '
        || 'is top->bottom, BYTE-IDENTICAL to web/webgpu/texture-manager.mjs twop L4-14 '
        || '+ _decode L171-176 (d=(y*w+x)*4). NO vertical flip in either decoder.';

UPSERT source:flycast_ta_vtx_sprite SET
  kind = 'flycast_source', path = 'core/hw/pvr/ta_vtx.cpp',
  detail = 'AppendSpriteVertexA L1047-1073 + B L1124-1153 + CaclulateSpritePlane '
        || 'L1075-1122. Sprite(ParaType-5) expands to 4 verts in order '
        || '{cv0=(x3,y3), cv1=(x2,y2), cv2=(x0,y0), cv3=(x1,y1)} = {D,C,A,B}; UVs '
        || 'u0v0->cv2, u1v1->cv3, u2v2->cv1, cv0.uv computed by plane closure. This '
        || 'is NOT a perimeter (A,B,C,D) order. Polys(ParaType-4) ARE perimeter.';

UPSERT source:prod_font_probe SET
  kind = 'live_capture', path = '/dev/shm/font_tw.png + font_lin.png (prod 149.28.44.118)',
  detail = 'Orientation probe CPU-decodes the LIVE name/FONT glyph VRAM like '
        || 'TextureManager. font_tw.png (twiddle path) = UPRIGHT readable "TIME/0123456789/'
        || 'LEVEL". font_lin.png (linear path) = garbage. => the live name texture IS '
        || 'TWIDDLED and decodes UPRIGHT through our twop. Decoder is not the bug.';

UPSERT source:replica_collectHudQuads SET
  kind = 'flycast_source', path = 'core/network/maplecast_oracle_hook.cpp',
  detail = 'collectHudQuads L2986-3079. isSpritePara=((pcw>>29)&7)==5 L3025; sprites '
        || 'read rc.verts[pp.first..+4] DIRECTLY (L3037-3047) -> captures the {D,C,A,B} '
        || 'sprite vertex order verbatim. q.u[c]=vt.u; q.v[c]=vt.v captured AS-IS L3068. '
        || 'HudQuad struct (oracle_hook.h L225-230): f32 x[4],y[4],u[4],v[4],col[4],4 ctrl.';

UPSERT source:replica_buildHudTA SET
  kind = 'client_source', path = 'web/render-replica/replay.html (deployed prod)',
  detail = 'parseHUDQ L544-554 reads 96B HudQuad; buildHudTA L571-624 writes q.u[i]/'
        || 'q.v[i] VERBATIM and re-strips ALL quads with a SINGLE order=[0,1,3,2] '
        || '(L599). Applies perimeter strip to BOTH ParaType-4 (correct) and ParaType-5 '
        || '(WRONG: {D,C,A,B} order) -> name V axis reversed -> names upside-down.';

-- The finding
UPSERT finding:hud_texture_orientation_sprite_vs_poly SET
  title = 'HUD names flip / portraits upright = ParaType-5 sprite vs ParaType-4 poly '
       || 'UV-corner mapping in client buildHudTA, NOT the texture decoder',
  status = 'confirmed', confidence = 0.95, date = '2026-06-15',
  summary =
    'SYMPTOM: HUD character-NAME/TIME/FONT glyphs decode upside-down; PORTRAITS upright; '
 || 'a global decoder V-flip fixes names but breaks portraits. Both go through one '
 || 'TextureManager._decode. ROOT CAUSE (flycast-traced): (1) The decoder is NOT the '
 || 'bug — flycast texture_TW (texconv.cpp L386-406) walks rows top->bottom into '
 || 'PixelBuffer (texconv.h L96-120) IDENTICALLY to our twop+_decode; live prod probe '
 || 'font_tw.png decodes the name VRAM UPRIGHT. (2) The flip is in UV-vs-corner mapping. '
 || 'HUD names are PVR SPRITES (ParaType-5, (pcw>>29)&7==5); portraits/bars are POLYS '
 || '(ParaType-4). flycast AppendSpriteVertexB (ta_vtx.cpp L1124-1153) expands a sprite '
 || 'to 4 verts in NON-perimeter order {D,C,A,B} = {(x3,y3),(x2,y2),(x0,y0),(x1,y1)} '
 || 'with UVs u0v0->cv2,u1v1->cv3,u2v2->cv1,cv0 plane-closed; polys are perimeter '
 || '{A,B,C,D}. collectHudQuads captures sprite verts verbatim in {D,C,A,B} order. '
 || 'Client buildHudTA (replay.html L571-624) re-strips ALL quads with ONE order '
 || '[0,1,3,2] that is correct for perimeter polys but pairs the wrong V with each '
 || 'screen corner for the {D,C,A,B} sprite layout -> name V reversed = upside-down; '
 || 'portraits unaffected. FIX (client, sprite-render expert owns): in buildHudTA, '
 || 'branch on isSprite=((q.pcw>>29)&7)==5 and use a sprite-specific strip permutation '
 || 'that maps the engine {D,C,A,B} corners+UVs to a correct triangle-strip (each screen '
 || 'corner keeps ITS OWN captured u/v — DO NOT remap V, remap the CORNER ORDER). '
 || 'NO global decode flip, NO 1-V. Portraits keep [0,1,3,2]. window._hudQuadOrder is a '
 || 'live calibration knob but must become per-paramtype, not one global order.',
  open_items =
    'Determine the exact sprite strip permutation empirically with window._hudQuadOrder '
 || 'on a name-only quad (the {D,C,A,B}->screen mapping); candidates [2,3,1,0] / '
 || '[2,1,3,0] derived from u0v0=corner0. Validate names AND portraits upright in one '
 || 'frame. CHARQ/HUDQ both carry u/v verbatim so no server change needed.';

UPSERT edge:about_36a SET in = finding:hud_texture_orientation_sprite_vs_poly, out = source:flycast_texconv_twop, rel='cites';
UPSERT edge:about_36b SET in = finding:hud_texture_orientation_sprite_vs_poly, out = source:flycast_ta_vtx_sprite, rel='cites';
UPSERT edge:about_36c SET in = finding:hud_texture_orientation_sprite_vs_poly, out = source:prod_font_probe, rel='cites';
UPSERT edge:about_36d SET in = finding:hud_texture_orientation_sprite_vs_poly, out = source:replica_collectHudQuads, rel='cites';
UPSERT edge:about_36e SET in = finding:hud_texture_orientation_sprite_vs_poly, out = source:replica_buildHudTA, rel='cites';
