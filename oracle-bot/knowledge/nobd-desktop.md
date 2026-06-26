# NOBD Desktop — NOBD for the PC version of MvC2 (software)

NOBD Desktop brings the GP2040-CE NOBD **sync window to PC, in software** — for *Marvel vs Capcom 2*
in the **Capcom Fighting Collection** on **Steam**. **No NOBD stick required**; it works with whatever
controller Steam presents to the game. Same fix as the stick firmware, run on the PC instead of the stick.

## What it does
The game reads its pad once per frame (60 Hz) through `XINPUT1_3.dll` (Steam Input presents your stick as
a virtual Xbox pad). When two attack buttons land a few ms apart — your natural finger gap — the game's
single 60 Hz read can fall between them and see only the first. NOBD Desktop groups near-simultaneous
attack presses so they land on the **same game frame** — so a dash is a dash, not a stray jab.

## How it works (for the technically curious)
- Ships a `DINPUT8.dll` proxy the game already imports; from inside the process it **inline-hooks
  `XInputGetState`**.
- A background **~1 kHz poll thread** reads the stick continuously and runs the sync window on its own fine
  clock (like the controller firmware does). The game's read then samples the already-grouped result
  (lock-free).
- **Directions are never delayed**, so motion tech (fast fly / refly, triangle dashing, wavedashes) stays
  frame-tight.
- Two parts share a block of named memory: `nobd.exe` (tray + control panel + Finger Gap Tester) and the
  in-game `DINPUT8.dll` hook (headless).

### Latch modes
- **Continuous** (default, the only one in the UI): the poll thread runs the window on its own clock; the
  game samples the committed result. **Non-blocking *and* low-latency** — a lone attack costs +1 frame only
  if it lands in the last few ms before a read (~18% of presses in their own testing — an OUR-MEASUREMENT
  figure, not a universal fact); grouped presses cost 0. **Online-safe**: it never stalls the game thread,
  so it doesn't disrupt rollback netplay. (Grouping never desyncs netplay — both clients see identical
  inputs; only a *stall* would, and Continuous never stalls.)
- **Defer** (legacy, not in the UI): per-read state machine; +1 frame on every lone press. Online-safe.
- **Block** (legacy, not in the UI): stalls the read a few ms to group within the same frame; sub-frame
  latency but **offline/training only** (stalling disrupts rollback).

## How to install / use
1. **Install page** — auto-detects your MvC2 Steam folder; **Install to game** copies `DINPUT8.dll` in
   (close MvC2 first — the DLL is locked while the game runs). It then loads automatically every launch;
   you don't reinstall each session. **Uninstall** removes it.
2. **Steam Input must be enabled** for MvC2 (Steam → game → Properties → Controller) — that's what presents
   the stick as the Xbox pad the game reads.
3. **Finger Gap Tester page** — press two attack buttons together; it measures your real finger gap so you
   can pick a sync window.
4. **NOBD Sync page** — the live control + stats (splits caught/missed, groups, poll rate, input latency,
   finger gap, fps).
- It's an unsigned build, so Windows SmartScreen may warn on first run.

## Stick firmware vs NOBD Desktop — which to point someone at
- **NOBD stick firmware** (GP2040-CE-NOBD): the sync window lives on the controller; works on any
  game/console the stick is plugged into. For people building/flashing a controller.
- **NOBD Desktop**: software for the **PC Steam** MvC2; no special stick needed. For PC players who want
  the fix without new hardware.

Both implement the **same once-per-frame sync-window fix** — they just run it in different places. All the
honesty rules in `nobd-knowledge.md` apply equally (it's a fix, not an aid; changes *when* not *which*;
measure your own finger gap; never the retired claims).
