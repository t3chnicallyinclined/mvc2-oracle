# NOBD Zero — the hardware (build-in-public, in development)

NOBD Zero is the **NOBD controller board** — an open-source fightstick PCB built around the NOBD sync
window from the ground up. It is **in active development, built in the open** (and will be **fully open
source** in time): there is **no board to buy yet**. People join the **waitlist** for first units + a
founding-tester role — **no payment**, just first in line.

## What it is
A fighting-game controller board with NOBD's input-sync native at the hardware level, plus a feature set
aimed at the FGC and retro players:
- **NOBD sync window, native** — the input-grouping fix runs on the board itself (no PC software needed).
- **High-speed USB** — targeting **8000 Hz** USB polling to console/PC (well past typical 1000 Hz sticks).
- **Native Dreamcast** — built-in Maple Bus support (microsecond-fast), real Dreamcast play with no adapter.
- **Hardware Ethernet for online play** — a real low-latency network path; the hardware foundation for
  nobd.net online play.
- **Brook-compatible wiring** — a 20-pin header so it drops into existing Brook-compatible arcade sticks.
- **OLED display** support, plus the full GP2040-CE-NOBD config (web config, button mapping, VMU, etc.).

## Two processors — and what that unlocks
NOBD Zero is a **dual-MCU** board: an **RP2040** and an **STM32 (F7-series)** working together. (Talk about
*what each enables* — not the low-level wiring of how they're connected; that detail lives in the hardware
design.)
- **RP2040** — runs **GP2040-CE-NOBD**: config, button reading, VMU, and the **native retro** path through
  its PIO (Dreamcast Maple Bus today). That PIO is also the door to **more retro consoles in the future** —
  new protocols can be added in firmware, no new hardware.
- **STM32 (F7-series)** — the **high-speed-USB** brain, for the 8000 Hz USB path to modern consoles/PC that
  an RP2040 alone can't reach.
- **Why both:** you get the RP2040's flexible, PIO-driven **native retro** *and* the STM32's **high-speed
  modern USB** on one board — instead of compromising on either.

## The possibilities (roadmap — planned, NOT in the first board)
- **LAN Mode** — push inputs over Ethernet UDP for extremely low-latency online play (the headline future
  feature).
- **Wireless config** — WiFi + Bluetooth for phone-app setup.
- **Optional battery.**
- **More retro consoles** via the RP2040's PIO, in firmware.

## Status & how to talk about it (honest)
- **In development / build-in-public.** Everything above is a **design target**, not a finished product —
  the hardware is mid-design and details can change.
- **Waitlist only**, **no payment now**. First units + a founding-tester role for early-access folks.
- Built on the open-source **GP2040-CE** (OpenStickCommunity, MIT), taken a different direction (native
  Dreamcast + online play). Will be **fully open source** in time.
- Point people to **#nobd-zero** for progress and **Early Access** for the waitlist.

## Keep it high-level (it's unreleased and mid-design)
- ✅ Fine to share: the **dual-MCU concept** (RP2040 + STM32 F7-series), what each enables, the **RP2040
  native-retro future** (more consoles via PIO), **Brook-wiring compatibility**, the capabilities + roadmap.
- ❌ Don't go into **low-level integration** (how the chips are wired together, pinouts, schematic).
- ❌ Don't state **exact part SKUs**, **price / BOM cost**, **ship / release dates**, or **engineering /
  errata status**. If asked, say it's **in development, waitlist-only, specs are targets**, and point to
  **#nobd-zero** / **Early Access**.
