# NOBD stick firmware & the Finger Gap Tester — flashing, config, measuring

Covers the **controller firmware** (GP2040-CE-NOBD) and the **Finger Gap Tester**. For the PC software,
see `nobd/nobd-desktop.md`; for what NOBD is / why it's a fix, see `nobd/nobd-knowledge.md`.

## The firmware
NOBD is a fork of the open-source **GP2040-CE** (OpenStickCommunity, MIT). It runs on RP2040 boards —
**Pico, Pico W, and the RP2040 Advanced Breakout Board**. The sync window is one function,
`syncGpioGetAll()` in `src/gp2040.cpp`. The `.uf2` releases are on the GitHub Releases page.

## Flashing a board
1. Download the `.uf2` for **your board** from the Releases page
   (`github.com/t3chnicallyinclined/GP2040-CE-NOBD/releases`).
2. **Hold BOOTSEL** while plugging the board into USB — it mounts as a drive named **RPI-RP2**.
3. **Drag the `.uf2` onto that drive.** The board reboots running NOBD. You don't reflash each session.

## Configuring NOBD (the web config)
1. **Hold S2 on boot** to enter web-config mode.
2. Open **`http://192.168.7.1`** → **Settings**.
3. **Input timing mode** (dropdown):
   - **Stock Debounce** — standard per-pin debounce (sets the sync window to 0 / off).
   - **NOBD Sync Window** — the grouping window. Value in **ms**, range **1–500**, **default 5**.
4. **Release Debounce** (checkbox, NOBD mode only): buffers *releases* by the same window to kill phantom
   re-presses from switch bounce. **Default off** — useful for **rhythm games**, not fighting games (FG
   players want instant releases for negative edge / charge partitioning).
- Both values persist in flash; switching modes preserves the other's setting.

## Picking your sync window — the Finger Gap Tester
The window should match **your** natural finger gap — so measure it, don't guess.
- **Finger Gap Tester** (separate tool): download **`FingerGapTester.exe`** (Windows, no install) from its
  Releases page, plug in your stick, and press **two attack buttons together** repeatedly. It shows the gap
  (ms) per pair live + a summary, and **recommends a sync window** from your average gap. It also flags
  **strays** (a solo press that didn't pair — a potential unwanted jab), **bounces** (re-press within ~5 ms
  of release), **pre-fire** (first button solo for 1+ frames before the second), and warns if **>50% of
  presses have a 0 ms gap** (OBD/macro detection). Also a Rust GUI (`cargo`) and a Python CLI
  (`pip install pygame; python test_finger_gap.py`).
- **NOBD Desktop** has a Finger Gap Tester built into its UI too.
- Set the window a little above your average gap. The recommendation is a starting point — your gap is a
  measured personal number, not an external fact.

## Quick support answers
- *"What board?"* → Pico / Pico W / RP2040 Advanced Breakout (RP2040-based).
- *"How do I flash?"* → hold BOOTSEL, drag the `.uf2` onto the RPI-RP2 drive.
- *"Where's the sync setting?"* → hold S2 → `http://192.168.7.1` → Settings → Input timing mode → NOBD Sync Window.
- *"What value?"* → measure with the Finger Gap Tester and set a bit above your average; 5 ms is the default.
- *"Phantom presses / eaten releases in a rhythm game"* → enable Release Debounce.

Built on GP2040-CE (OpenStickCommunity, MIT). All the honesty rules in `nobd-knowledge.md` apply.
