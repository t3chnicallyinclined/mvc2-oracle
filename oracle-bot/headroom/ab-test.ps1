# A/B the Oracle's token usage with vs without Headroom compression.
#
# Prereqs:
#   - $env:ANTHROPIC_API_KEY set (this spends real API tokens - a handful of Opus questions, twice)
#   - the Headroom proxy running in another shell:  .\run-proxy.ps1
#
# Runs each question in ab-questions.txt through oracle.py twice (baseline vs proxied), sums the
# per-turn usage oracle.py prints to stderr ("[in N +cache_read C / out O]"), and saves the full
# answers to answers-baseline.txt / answers-headroom.txt so you can compare them for fidelity.
param(
    [string]$Proxy = "http://127.0.0.1:8787",
    [int]$Only = 0   # >0 = run only the first N questions (smoke test)
)
$ErrorActionPreference = "Stop"
if (-not $env:ANTHROPIC_API_KEY) { throw "Set ANTHROPIC_API_KEY first." }
$here   = $PSScriptRoot
$oracle = (Resolve-Path (Join-Path $here "..\oracle.py")).Path
$qs     = Get-Content (Join-Path $here "ab-questions.txt") |
          Where-Object { $_.Trim() -and -not $_.Trim().StartsWith("#") }
if ($Only -gt 0) { $qs = $qs | Select-Object -First $Only }

function Pct($a, $b) {
    if ($a -eq 0) { return "n/a" }
    return ([string]([math]::Round(100.0 * ($a - $b) / $a, 1)) + "%")
}

function Measure-Run([string]$Label, [string]$BaseUrl) {
    $in = 0; $cr = 0; $out = 0; $turns = 0
    if ($BaseUrl) { $env:ANTHROPIC_BASE_URL = $BaseUrl }
    elseif (Test-Path Env:ANTHROPIC_BASE_URL) { Remove-Item Env:ANTHROPIC_BASE_URL }
    $ansFile = Join-Path $here "answers-$Label.txt"
    $trcFile = Join-Path $here "trace-$Label.txt"
    Set-Content $ansFile "# $Label pass"
    Set-Content $trcFile "# $Label pass - full stderr (tool traces + per-turn usage)"
    $n = 0
    foreach ($q in $qs) {
        $n++
        # Start-Process with file redirection: PS 5.1 otherwise wraps python's stderr banner in an
        # ErrorRecord and (under -EA Stop) aborts the run. Redirecting at the process level avoids it.
        $outFile = New-TemporaryFile
        $errFile = New-TemporaryFile
        $argline = '"' + $oracle + '" "' + ($q -replace '"', '\"') + '"'
        Start-Process -FilePath "python" -ArgumentList $argline -NoNewWindow -Wait `
            -RedirectStandardOutput $outFile.FullName -RedirectStandardError $errFile.FullName
        $ans   = Get-Content $outFile.FullName -Raw
        $usage = Get-Content $errFile.FullName -Raw
        Remove-Item $outFile.FullName, $errFile.FullName -Force
        Add-Content $ansFile ("`n===== Q" + $n + ": " + $q + " =====")
        Add-Content $ansFile $ans
        Add-Content $trcFile ("`n===== Q" + $n + ": " + $q + " =====")
        Add-Content $trcFile $usage
        $qin = 0; $qout = 0; $qturns = 0
        foreach ($m in [regex]::Matches($usage, '\[in (\d+) \+cache_read (\d+) / out (\d+)\]')) {
            $in  += [int]$m.Groups[1].Value; $qin  += [int]$m.Groups[1].Value
            $cr  += [int]$m.Groups[2].Value
            $out += [int]$m.Groups[3].Value; $qout += [int]$m.Groups[3].Value
            $turns++; $qturns++
        }
        Write-Host ("  [" + $Label + " Q" + $n + "] api-turns=" + $qturns + " turn-in=" + $qin + " turn-out=" + $qout + " (running in=" + $in + " out=" + $out + ")")
    }
    return [pscustomobject]@{ Input = $in; CacheRead = $cr; Output = $out; Turns = $turns; Answers = $ansFile }
}

Write-Host "== Baseline (no proxy) ==" -ForegroundColor Cyan
$base = Measure-Run "baseline" $null
Write-Host ("   api-turns=" + $base.Turns + " input=" + $base.Input + " cache_read=" + $base.CacheRead + " output=" + $base.Output)

Write-Host ("== Headroom (" + $Proxy + ") ==") -ForegroundColor Cyan
$hr = Measure-Run "headroom" $Proxy
Write-Host ("   api-turns=" + $hr.Turns + " input=" + $hr.Input + " cache_read=" + $hr.CacheRead + " output=" + $hr.Output)

Write-Host "== Reduction (raw input is confounded by cross-pass cache reuse; see /stats) ==" -ForegroundColor Green
Write-Host ("   uncached-input " + (Pct $base.Input $hr.Input) + "   output " + (Pct $base.Output $hr.Output) + "   api-turns " + $base.Turns + " -> " + $hr.Turns)

Write-Host "== Headroom self-reported /stats ==" -ForegroundColor Green
try {
    $s = Invoke-RestMethod -UseBasicParsing ($Proxy + "/stats") -TimeoutSec 5
    $c = $s.summary.compression
    Write-Host ("   requests_compressed=" + $c.requests_compressed + " avg=" + $c.avg_compression_pct + "% best=" + $c.best_compression_pct + "% tokens_removed=" + $c.total_tokens_removed)
    $cost = $s.summary.cost
    Write-Host ("   cost_without_usd=" + $cost.without_headroom_usd + " cost_with_usd=" + $cost.with_headroom_usd + " saved_usd=" + $cost.total_saved_usd + " saved_pct=" + $cost.savings_pct)
} catch { Write-Host ("   (could not read /stats: " + $_ + ")") }

Write-Host ("   answers: " + $base.Answers + "  vs  " + $hr.Answers)
Write-Host "Compare those two files for dropped addresses/offsets before trusting it." -ForegroundColor Yellow
