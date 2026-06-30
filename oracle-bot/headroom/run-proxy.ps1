# Start the Headroom optimization proxy for the MvC2 Oracle (oracle.py).
#
# The proxy sits between oracle.py's Anthropic client and the API, compressing the tool
# results (grep/read_disasm output) that accumulate in the message history and get re-sent
# every loop iteration. Point the Oracle at it with:
#
#     $env:ANTHROPIC_BASE_URL = "http://127.0.0.1:8787"
#     python ..\oracle.py "where is the per-frame body emitter?"
#
# NOTE: this only helps oracle.py (the local Messages-API tool loop). The Discord bot runs on
# the managed-agent Sessions API, where the tool loop executes server-side — a client-side proxy
# never sees those tool outputs, so Headroom does nothing for it.
$ErrorActionPreference = "Stop"
$headroom = Join-Path $env:APPDATA "Python\Python313\Scripts\headroom.exe"
if (-not (Test-Path $headroom)) {
    throw "headroom.exe not found at $headroom — run: pip install 'headroom-ai[proxy]'"
}
$port = if ($env:HEADROOM_PORT) { $env:HEADROOM_PORT } else { 8787 }
Write-Host "Headroom proxy -> http://127.0.0.1:$port  (Ctrl-C to stop)" -ForegroundColor Cyan
Write-Host "In another shell:  `$env:ANTHROPIC_BASE_URL='http://127.0.0.1:$port'; python ..\oracle.py `"<q>`"" -ForegroundColor DarkGray
& $headroom proxy --port $port
