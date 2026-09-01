-- ============================================================================
-- 75: The INPUT LATCH pipeline — raw maple byte -> pd server -> game Input_DEC
-- Traced 2026-07-14 for the "NullDC Bear vs Flycast" timing analysis.
-- Chain (all CONFIRMED from marvelous2 unless noted):
--   maple rx buffer byte 0x8C200BA8 (raw DC pad u16 low byte, active-low)
--     -> pdExecPeripheralServer = bank17.loc_8c17794E (processes rx buffers into
--        PDS_PERIPHERAL[24] @ 0x8C32C68C stride 0x34; +0x08 on, +0x2C old,
--        +0x10/+0x14 press/release, +0x30 info-ptr)
--     -> game translate loc_8c010080 (first routine after EntryPoint; calls
--        pdExec + pdGetPeripheral(0/6/0xC/0x12) -> ptrs at 0x8C212BE0[4]; builds
--        CPS2-style bitmask into Input_DEC[4] @ 0x8C2681DC stride 0x14 with
--        cur->prev copy +0x00->+0x02; analog deadzone mag^2>6400 -> 8-way atan2
--        sector table bank14.loc_8c143c00)
--     -> called from per-frame tick loc_8c0104c0 (frame counters++), which is
--        VBLANK-CHAIN callback slot 1 @ 0x8C2D6C84 (registered loc_8c122aa0(1,·),
--        trampoline loc_8C122800, SDK chain code 0x0900 via bank18.loc_8c1844D4)
--   Main loop paces on vsync flag 0x8C2152D4 (set=1 by slot-0 callback
--   loc_8c031aac; waited by loc_8c031aca with timeout 0x28C58=167ms=10 frames).
-- Consequence: MVC2 latches input EXACTLY ONCE per vblank, inside the vblank
-- interrupt chain, game-side edge detection from its own prev copy. Measured
-- end-to-end (lagProbe 2026-07-08): kcode@T -> raw byte@T+1 -> gameplay@T+2.
-- Sources: build/bank01.asm:57-330 (translate), :721-760 (tick+bsr),
--   :1336-1343 (registration), bank12.asm:5613-5899 (trampolines/init/registrar),
--   bank03.asm:3847-3910+4075-4098 (vsync flag/wait), bank17.asm:12577-12756
--   (pd server + pdGetPeripheral), bank1c.asm:10101-10143 (syHw table:
--   SB_MDSTAR=0x0CFF0000, SB_MDTSEL=0 software-trigger maple).
-- ALL nodes idempotent (UPSERT). Edges via RELATE -> run 07_dedup_edges after.
-- ============================================================================
USE NS re DB kb;

-- ---- routines ---------------------------------------------------------------
UPSERT routine:loc_8c010080 SET label='Input_Translate', pc='0x8C010080', bank='bank01',
  contribution_candidate=true,
  role='per-vblank pad read + DC->CPS2 bitmask translate (THE game input latch)',
  note='First routine after EntryPoint (bank01:57). Calls pdExecPeripheralServer (bank17.loc_8c17794E) then pdGetPeripheral (bank17.loc_8c177A54) for ports 0x00/0x06/0x0C/0x12 -> PDS ptrs cached at 0x8C212BE0[4]. Per player i (0..3): Input_DEC base 0x8C2681DC + i*0x14; copies cur@+0x00 -> prev@+0x02 (the game-side edge-detect double buffer); device-invalid (info bit0 via PDS+0x30 ptr) -> zeroes the struct (loc_8c010232); reads PDS on@+0x08 LEVEL state + analogs @+0x18/1A/1C/1E -> stores +0x08/+0x0A (triggers) +0x0C/+0x0E (stick XY); digital translate (pd 0x10 Up->0x2000, 0x20 Down->0x1000, 0x40 Left->0x0800, Start 0x08->0x8000, buttons->LP/HP/LK/HK/A1/A2 per InputsInfo bitmask); if no digital direction, analog stick: mag^2 = x^2+y^2 (fmac) vs 6400.0f (0x45C80000, radius 80) deadzone, angle via bank11.loc_8c11e210, >>13 & 7 -> 8-way sector table bank14.loc_8c143c00. Latches ONCE per vblank (called only from loc_8c0104c0). All gameplay/menu code reads Input_DEC RAM, never the hardware -> input is strictly frame-quantized; no sub-frame polling exists in MVC2.';
UPSERT routine:loc_8c0104c0 SET label='Frame_Tick_VblankCb', pc='0x8C0104C0', bank='bank01',
  contribution_candidate=true,
  role='per-frame housekeeping callback (vblank chain slot 1) -> bsr Input_Translate',
  note='bank01:721-760: increments GameGlobalPointer->+0x10 and counter 0x8C2152D0, decrements countdown 0x8C2152CC, conditional counter 0x8C21528C (flag 0x8C21528A), calls bank17.loc_8c174dfc, clears 0x8C26A963, then bsr loc_8c010080 (input latch). Registered as callback SLOT 1 (cell 0x8C2D6C84) via bank12.loc_8C122AA0(r4=1, r5=this) at bank01:1336-1339; invoked by interrupt trampoline loc_8C122800 (chain code 0x0900) => INPUT IS LATCHED INSIDE THE VBLANK INTERRUPT CHAIN, not in the main loop.';
UPSERT routine:loc_8c122aa0 SET label='Callback_Register', pc='0x8C122AA0', bank='bank12',
  role='register game callback into slot table 0x8C2D6C80+ (IMASK-protected)',
  note='bank12:6034: masks interrupts (SR|=0xE0), index<0x0D, dispatch via table 0x8C16BD9C[idx] -> setters store fn ptr: slot0->0x8C2D6C80 (loc_8C1229D0), slot1->0x8C2D6C84 (loc_8C1229E0), slot2->0x8C2D6C88. Trampolines loc_8C1227E0(id0)/loc_8C122800(id1)/loc_8C122820(id2)/loc_8C122840(id3, acks SB_ISTNRM 0x4000=AICA-DMA-end)/loc_8C122870(id5)/loc_8C1228A0(id4) write current-id to 0x8C2D6CE8 then jsr the slot. Init loc_8c1228f0 clears 13 slots, hooks 12 SDK interrupt pairs from bank13.loc_8c13f4C2 via loc_8c122be0, then bank18.loc_8c1844D4(0x0900, loc_8C122800, 0x58, 0) and (0x0920, loc_8C122820, 0, 0) [+0x0A40/0x0B00 conditionally] -> handles at 0x8C2D6CB4+. Chain code 0x0900 carries the input tick.';
UPSERT routine:loc_8c031aac SET label='Vblank_Flag_Cb', pc='0x8C031AAC', bank='bank03',
  role='vblank callback slot 0: set vsync flag 0x8C2152D4=1 + per-vblank render work',
  note='bank03:3847: writes 1 -> [0x8C2152D4] then jsr bank11.loc_8c11bfc0, loc_8c030ee8, loc_8c03a004. Registered via loc_8c122aa0(0,·) at bank01:1340-1343 and trampoline loc_8C1227E0 registered with bank17.loc_8c17AE00 (SDK vsync cb setter, INFERRED name).';
UPSERT routine:loc_8c031aca SET label='Frame_Wait', pc='0x8C031ACA', bank='bank03',
  role='main-loop vsync wait: spin on flag 0x8C2152D4 with 167ms timeout',
  note='bank03:3865-3909: loops until [0x8C2152D4]!=0 using SDK timer fns bank17.loc_8c17878a/178794/17879a; bails when elapsed > 0x00028C58 (167,000us = 10 frames) -> hang-guard, proceeds anyway. => the game paces 1 logic tick per vblank flag; it follows whatever vblank cadence the emulator produces.';
UPSERT routine:loc_8c17794e SET label='pdExecPeripheralServer', pc='0x8C17794E', bank='bank17',
  role='Katana pd 1.50: process maple rx buffers -> PDS_PERIPHERAL[24]',
  note='bank17:12577-12732: gated by [0x8C1C43AC]; loops 24 logical units; bank18.loc_8c1859A0/loc_8c1859B2 return ptrs into the maple driver rx data (the 0x8C1F9xxx-0x8C200xxx work region where raw byte 0x8C200BA8 lives); PDS@0x8C32C68C+unit*0x34: +0x30=info ptr, +0x2C=old on, +0x08=on, +0x0C=~on, +0x10/+0x14=press/release (two modes on flag [0x8C32CBCC]). PROCESSES ONLY - does not kick the maple DMA (no SB writes here); the kick is the maple driver vblank hook (kd/bank18, not yet traced).';
UPSERT routine:loc_8c177a54 SET label='pdGetPeripheral', pc='0x8C177A54', bank='bank17',
  role='Katana pd 1.50: return &PDS_PERIPHERAL[id] = 0x8C32C68C + id*0x34',
  note='bank17:12735-12741. Game calls with 0x00/0x06/0x0C/0x12 (port A-D unit 0).';
UPSERT routine:loc_8c02d1c0 SET label='Input_Read_Both', pc='0x8C02D1C0', bank='bank02',
  role='read both players input: (Input_DEC+0x04) | (Input_DEC+0x10 & 0x3F60)',
  note='bank02:~31830: per active side reads u16@+0x10 masked 0x3F60 OR u16@+0x04 from base 0x8C2681DC (+0x14 for P2). USE-site showing Input_DEC struct has multiple derived words beyond cur/prev.';

-- ---- fields / memory --------------------------------------------------------
UPSERT field:input_dec SET name='Input_DEC', offset='0x8C2681DC (P1), +0x14/player, 4 slots', owner='global',
  type='struct[0x14]', class='logical',
  note='Game-side per-player input struct, written ONLY by loc_8c010080 at vblank: +0x00 cur bitmask (0x0400 R,0x0800 L,0x1000 D,0x2000 U,0x0200 LP,0x0100 HP,0x0040 LK,0x0020 HK,0x0080 A1,0x0010 A2,0x8000 START per InputsInfo), +0x02 prev (edge detect), +0x04/+0x10 derived words (reader loc_8c02d1c0 mask 0x3F60), +0x08/+0x0A triggers, +0x0C/+0x0E analog XY. Matches re-catalog/spreadsheet-data.md Input_DEC 2C2681DC/2C2681F0.';
UPSERT buffer:maple_rx_p1_buttons SET name='maple_rx_p1_buttons', address='0x8C200BA8',
  note='P1 raw DC controller condition u16 low byte in the maple/kd driver rx work region (0x8C1F9xxx-0x8C200xxx BSS). Active-low DC layout: bit2=A (press=0xFB), bit7=Right (0x7F) - matches lagProbe 2026-07-08 measurement. Written by maple DMA once per frame; read only via pdExecPeripheralServer. Not labeled in work.asm (address never appears as a literal in the banks - reached via kd driver pointers).';
UPSERT buffer:pds_peripheral_array SET name='PDS_PERIPHERAL[24]', address='0x8C32C68C',
  note='Katana pd 1.50 processed pad state, stride 0x34: +0x08 on (level, active-high), +0x0C off, +0x10/+0x14 press/release, +0x2C old, +0x30 info ptr, +0x18/1A/1C/1E analogs. Game caches &PDS[port] at 0x8C212BE0[4].';

-- ---- findings ----------------------------------------------------------------
UPSERT finding:input_latch_once_per_vblank SET
  statement='MVC2 latches controller input EXACTLY ONCE per frame, inside the vblank interrupt chain (chain 0x0900 -> loc_8c0104c0 -> loc_8c010080), into Input_DEC@0x8C2681DC; every gameplay/menu consumer reads that RAM. Combined with the measured chain (kcode@T -> raw maple byte 0x8C200BA8@T+1 -> gameplay@T+2, lagProbe 2026-07-08), the game-fixed internal latency is 1 frame poll-to-register + 1 frame register-to-visible. NO sub-frame input path exists: an emulator can only shift WHICH vblank a press lands on (max +/-1 frame, from host-poll point vs guest maple DMA kick, and from maple DMA completion timing instant-vs-realistic). Emulator "polls faster" folklore has no mechanism beyond that boundary alignment. MDTSEL=0 (software maple trigger, syHw table bank1c loc_8c1c44d8) - the SDK maple driver kicks the poll DMA per frame; flycast completes the DMA after a realistic emulated bus delay (maple_if.cpp sh4CyclesForXfer 2Mb/740Kb) while classic nullDC-era completion timing may differ (OPEN - decisive experiment: force flycast maple_schd synchronous, rerun lagProbe; if response moves TRIG+2->TRIG+1 the DMA-completion timing is a REAL 1-frame emulator differentiator for MVC2).',
  status='confirmed', confidence='high', date='2026-07-14', contribution_candidate=true;
UPSERT finding:frame_loop_vblank_paced SET
  statement='MVC2 main loop paces on a vsync flag (0x8C2152D4) set by vblank callback slot 0 (loc_8c031aac) and waited by loc_8c031aca with a 167ms (10-frame) timeout hang-guard: 1 logic tick per vblank the emulator delivers. The game does not self-time; frame pacing quality is 100% the emulator/host pipeline. Turbo speed = frameskip cadence (work.asm: 0x8C289620 rate Turbo1=4/Turbo2=2/FreeSelectNormal=6, counter 0x8C289621, sheet Frame_Skip_Cycle_Value 0x8C289600 "frames since match start incl. skipped"; factory default Turbo=0 set by init_default_settings@0x8C01099C settings+0x3) - non-uniform sim cadence at Turbo settings is GAME-INTRINSIC judder, not an emulator defect (skip-vs-double-tick direction INFERRED; confirm by probing 0x8C3496B0 Total_Frames vs vblank count).',
  status='confirmed', confidence='high', date='2026-07-14', contribution_candidate=true;

-- ---- sources ----------------------------------------------------------------
UPSERT source:marv_bank01_input SET kind='marvelous2',
  ref='build/bank01.asm:57-330 (loc_8c010080 translate), :721-760 (loc_8c0104c0 tick), :1336-1343 (slot registration), :1425+ (init_default_settings Turbo=0)';
UPSERT source:marv_bank12_intr SET kind='marvelous2',
  ref='build/bank12.asm:5613-5899 (trampolines loc_8C1227E0..loc_8C1228A0, init loc_8c1228f0, registrar loc_8C122AA0, slots 0x8C2D6C80+)';
UPSERT source:marv_bank17_pd SET kind='marvelous2',
  ref='build/bank17.asm:12577-12756 (pdExecPeripheralServer loc_8c17794E, pdGetPeripheral loc_8c177A54, PDS@0x8C32C68C stride 0x34)';
UPSERT source:marv_bank1c_syhw SET kind='marvelous2',
  ref='build/bank1c.asm:10101-10143 (syHw register table: SB_MDSTAR=0x0CFF0000, SB_MDTSEL=0, SB_MSYS=0xC3500000; SDK strings Shinobi 1.62 / pd Ver 1.50 / kamui2 / NaomiLib)';
UPSERT source:lagprobe_2026_07_08 SET kind='measurement',
  ref='memory/reference_mvc2_input_lag.md - lagProbeTick deterministic rig: kcode@T -> 0x8C200BA8@T+1 -> gameplay@T+2, 8x byte-identical, structural at TRIG=60/120';

-- ---- edges (RELATE; dedup with 07_dedup_edges.surql) -------------------------
RELATE routine:loc_8c0104c0->calls->routine:loc_8c010080;
RELATE routine:loc_8c010080->calls->routine:loc_8c17794e;
RELATE routine:loc_8c010080->calls->routine:loc_8c177a54;
RELATE routine:loc_8c010080->writes->field:input_dec;
RELATE routine:loc_8c02d1c0->reads->field:input_dec;
RELATE routine:loc_8c17794e->reads->buffer:maple_rx_p1_buttons;
RELATE routine:loc_8c17794e->writes->buffer:pds_peripheral_array;
RELATE routine:loc_8c010080->reads->buffer:pds_peripheral_array;
RELATE finding:input_latch_once_per_vblank->about->routine:loc_8c010080;
RELATE finding:input_latch_once_per_vblank->about->buffer:maple_rx_p1_buttons;
RELATE finding:input_latch_once_per_vblank->cites->source:marv_bank01_input;
RELATE finding:input_latch_once_per_vblank->cites->source:marv_bank17_pd;
RELATE finding:input_latch_once_per_vblank->cites->source:marv_bank1c_syhw;
RELATE finding:input_latch_once_per_vblank->cites->source:lagprobe_2026_07_08;
RELATE finding:frame_loop_vblank_paced->about->routine:loc_8c031aca;
RELATE finding:frame_loop_vblank_paced->cites->source:marv_bank12_intr;
RELATE finding:frame_loop_vblank_paced->cites->source:marv_bank01_input;
-- ============================================================================
