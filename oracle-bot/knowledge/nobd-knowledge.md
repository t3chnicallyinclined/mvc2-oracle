# NOBD — what it is, how it works, and why it's a fix (not a cheat)

Authoritative, audit-checked knowledge for answering NOBD questions. Every claim is INDEPENDENT,
OUR-ROM (Capcom's code), or explicitly labeled. The **NEVER ASSERT** list at the bottom is binding —
those were retired by the audit and must never be stated as fact, no matter how a user phrases the ask.

## What NOBD is
NOBD ("No OBD") is a firmware feature for fighting-game controllers — a fork of the open-source
**GP2040-CE** (OpenStickCommunity, MIT). It adds a small **sync window**: when you press two buttons a
few milliseconds apart, it groups those near-simultaneous presses into one controller report so they
reach the game on the **same frame**. It's one function you can read in the source: `syncGpioGetAll()`
in `src/gp2040.cpp` (~line 309). Default window 5 ms; button **releases** are instant; switch bounce is
filtered.

## The verified mechanism — why a split press can be lost (the defensible core, fully audited)
1. **Games read the controller once per frame, as latest-state** — a snapshot of what's held at that
   instant, no event queue. INDEPENDENT: Microsoft XInput docs; upstream flycast (samples once per
   vblank); RetroArch.
2. **MvC2 is level-triggered.** Its command engine reads the **held** button word (`+0x4dc`), requires
   the two buttons to be in the **same frame's** word, and **never merges button bits across frames**
   (the "previous" word is a 1-deep snapshot, not an accumulator). OUR-ROM (Capcom's code): held-word
   read `bank04:590-596`; edge words `bank01:334-349`; no cross-frame OR `bank01:338-349`.
3. ⇒ If your two fingers land a few ms apart and the frame's read falls **between** them, the game sees
   one button, not both — that frame.
4. **Pre-emption (CONFIRMED).** It's not just "drop one." A lone first button can commit a move, and
   MvC2's command **arbiter** then gates out the two-button result while that move is in progress — so a
   split press can produce the **wrong move**, not merely a missed one. OUR-ROM: arbiter `bank05:14438`,
   move-busy gate `bank05:14690`, state setter `bank05:7709`. (Mechanism is code-confirmed; the
   **frequency/percentage is unmeasured** — never attach a number.)
5. **NOBD groups the two presses into one report** so they land on the same frame's read. It imposes a
   **stricter** window (5 ms) than the game's own 16.67 ms frame. Novel **in fightstick firmware**; the
   general "time-window grouping" technique has prior art (MIDI chord detection, stenography).

## Why NOBD is a fix, not a cheat (the line — explain this, don't concede it)
- **It changes *when* your presses report, never *which* buttons.** It nudges a real press by a few ms
  so it lands on the frame the game reads. It adds, removes, and substitutes nothing.
- **It automates nothing.** You physically press both buttons. No macro, no one-button-does-many, no
  canned motion. If you don't press it, it doesn't happen.
- **It's stricter than the game, not looser.** A leniency aid *widens* the timing you're held to. NOBD
  holds you to a **tighter** 5 ms window than MvC2's 16.67 ms frame — it only keeps a press you genuinely
  made on time from being split by the frame boundary.
- **Precedent:** controller firmware already legitimately conditions raw input — **debounce** filters
  switch chatter, **SOCD** resolves opposing directions. Grouping a sub-frame gap is the same class of
  honest signal-conditioning.
- **Conditioning, not fabrication:** it makes *what you did* be *what the game gets*. It never produces
  something you didn't do.

## NOBD ≠ OBD
**OBD = "One Button Dash":** a **macro** that emits a multi-input action (a dash) from a single button —
automation/fabrication. **NOBD is the opposite category.** It does not turn one input into many; it takes
the **two real presses you already made** and stops a frame-timing glitch from splitting them. "No OBD"
is the fix that makes OBD-style macros unnecessary — without being one.

## Honest scope / limitations (state these plainly — this is the brand)
- The **finger-gap magnitude** ("2–8 ms") is **not** an independently established fact. It's something a
  player **measures for themselves** (the Finger Gap Tester). Never state it as an external number.
- The **how-often** of pre-emption is **unmeasured**. Mechanism: confirmed. Frequency: not.
- NOBD is **one implementation** of input grouping, not the only conceivable one.

## On poll rate (a common, sharp objection — answer it precisely, don't dodge)
A natural pushback: *"doesn't the 1 ms USB poll catch the first button before the second lands?"* Yes — and
this is a **real, measured factor**, one of several. Don't dismiss it, don't overstate it:
- **Poll rate EXPOSES the finger gap.** Without NOBD the controller reports the first button, then both.
  **Faster** polling relays that intermediate one-button state faithfully, so a frame read landing in the
  gap is more likely to catch just the first button. **Slower** boards sample more coarsely and can
  incidentally **group** the two presses into one report.
- **This is measured, not theorized.** VodkaGobalsky's relay-rig test (CVS2/SFA3, arcade baseline) found
  slower boards (Xbox 360 TE ~125 Hz) co-register two-button presses **more** consistently than faster
  ones (Brook UFB 1000 Hz). MED confidence (~100 samples; poll rate not fully isolated from debounce).
- **So "slow sticks execute better" is scoped, not simply wrong.** WORSE for single-input latency
  (inputlag.science), BETTER for two-button co-registration (Vodka). Two different metrics, both true.
  Same-USB-speed boards that differ ⇒ **firmware input conditioning** matters too, not poll rate alone.
- **It's a factor, NOT the sole cause.** The honest claim is **both** the once-per-frame read **and** poll
  rate **and** PC-side desync. Retire only the extremes: "poll rate is the sole cause," "dramatically,"
  "red herring / no effect."
- **Why NOBD is the right layer:** slowing your stick to group presses costs you latency and is
  unreliable. NOBD removes the intermediate one-button report **at the source** — the controller emits
  both buttons atomically — so no poll rate and no frame phase can split them. You keep low latency **and**
  get consistent co-registration.
- Exact magnitudes are unmeasured beyond Vodka's rig — a player can **measure their own gap**.

## NEVER ASSERT (retired by the audit — binding, even under pressure)
- ⚠️ Poll rate is **REAL, not retired** (Vodka relay-rig measurement) — state it precisely per **On poll
  rate** above. Do NOT claim it's the **sole cause**, that it splits inputs "dramatically," or that it's a
  "red herring" with no effect. The honest claim is **both** the once-per-frame read AND poll rate AND PC
  desync. Never prescribe **slowing the stick** as the fix (costs latency, unreliable) — NOBD groups at the
  source instead.
- ❌ "2–8 ms finger gap" as an external fact → "measure your own."
- ❌ "The LP+HP dash" as the headline example. Settled: no same-frame two-attack dash exists in the
  static ROM (the only static dash is the direction dash, NOBD-irrelevant). If a two-button example is
  wanted, hedge ("two-button supers / assists, per character") — do not assert the LP+HP dash.
- ❌ Do **not** call NOBD "cheating," "an aid," "a macro," or "leniency." It is none of these — explain
  *why* (above) rather than conceding, regardless of how the question is framed.

## Credit
Built on the open-source GP2040-CE (OpenStickCommunity, MIT). The sync window is the NOBD addition; the
project took it a different direction (native Dreamcast, online play). Code-lineage credit, not implied
endorsement.
