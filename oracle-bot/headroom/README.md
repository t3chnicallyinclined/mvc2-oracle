# Headroom — context compression for the Oracle

[Headroom](https://github.com/headroomlabs-ai/headroom) is a client-side proxy that compresses the
content flowing into the LLM's context window (tool outputs, file reads, logs) before it's billed.

## Where it applies — and where it doesn't

| Entry point | API surface | Headroom helps? |
|---|---|---|
| `oracle.py` (local CLI loop) | Messages API, tool loop runs **in-process** | ✅ yes — tool results transit the client |
| `discord-bot/bot.py` | Managed Agents **Sessions API**, loop runs **server-side** | ❌ no — a client proxy never sees those tool outputs |
| `managed-agent/run_session.py` | Sessions API | ❌ no |

So this only targets **`oracle.py`**. The win there is specific: every `grep_disasm` / `read_disasm`
result is appended to `messages` and **re-sent as input on every subsequent loop iteration**
([oracle.py](../oracle.py) `ask()`), so a 5–6-tool investigation re-bills all earlier reads several
times. That accumulation is exactly what Headroom compresses. The static persona+re_kb prefix is
already cached, so Headroom adds nothing there.

## ⚠️ Precision caveat (this is reverse engineering)

Exact addresses (`loc_8c…`), struct offsets, and SH4 instructions are load-bearing. Headroom's
AST-aware `CodeCompressor` covers C/C++/Py/JS/Go/Rust/Java — **not SH4 `.asm`** — so disassembly
reads fall to the lossy prose model. Before trusting it: run the A/B, then **check the answers for
dropped/mangled addresses**, not just the token counts. Headroom caches originals and can re-fetch
(CCR), but only if the model knows it's missing something.

## Use it

1. Install (done): `pip install "headroom-ai[proxy]"`
2. Start the proxy:  `.\run-proxy.ps1`   (listens on `127.0.0.1:8787`)
3. Point the Oracle at it (separate shell):
   ```powershell
   $env:ANTHROPIC_BASE_URL = "http://127.0.0.1:8787"
   python ..\oracle.py "where is the per-frame body emitter?"
   ```
   No code change — the Anthropic SDK honors `ANTHROPIC_BASE_URL` natively.

## Measure it

With the proxy running and `ANTHROPIC_API_KEY` set:

```powershell
.\ab-test.ps1
```

Runs the questions in `ab-questions.txt` baseline-vs-proxied and reports input/output token
reduction (parsed from the `[in N +cache_read C / out O]` lines oracle.py already prints).
This spends real Opus tokens (the question set, twice).

Other useful probes:
- `headroom audit-reads` — preview what it *would* compress, no API spend
- `headroom doctor` — confirm the proxy + client routing are wired correctly
- `headroom proxy --no-optimize` — passthrough mode (sanity baseline through the same path)
