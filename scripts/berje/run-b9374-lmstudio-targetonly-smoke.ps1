param(
    [string] $OutDir,

    [string] $ModelKey = 'google/gemma-4-26b-a4b',

    [string] $Identifier,

    [int] $Context = 2048,

    [int] $MaxTokens = 96,

    [double] $CpuAllCoreMaxPct = 20.0
)

$ErrorActionPreference = 'Stop'

$SourceRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

if ([string]::IsNullOrWhiteSpace($Identifier)) {
    $Identifier = "targetonly-b9374-lmstudio-$(Get-Date -Format yyyyMMdd-HHmmss)"
}
if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $OutDir = Join-Path $SourceRoot "artifacts\lmstudio-b9374-targetonly-$(Get-Date -Format yyyyMMdd-HHmmss)"
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$month = Get-Date -Format 'yyyy-MM'
$day = Get-Date -Format 'yyyy-MM-dd'
$serverLog = "C:\Users\berje\.lmstudio\server-logs\$month\$day.1.log"
$lineStart = 0
if (Test-Path -LiteralPath $serverLog) {
    $lineStart = (Get-Content -LiteralPath $serverLog | Measure-Object -Line).Lines
}

$request = @{
    model = $Identifier
    prompt = 'Clean inference means'
    temperature = 0
    top_p = 1
    top_k = 1
    stream = $false
    max_tokens = [int] $MaxTokens
}
$requestPath = Join-Path $OutDir 'request.json'
$request | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $requestPath -Encoding utf8

$proc = $null
$cpu0 = 0.0
$cpu1 = 0.0
$wall = [Diagnostics.Stopwatch]::StartNew()
try {
    lms unload -a | Out-File -LiteralPath (Join-Path $OutDir 'lms-unload-before.txt') -Encoding utf8
    Start-Sleep -Seconds 2
    Set-Content -LiteralPath (Join-Path $OutDir 'lms-ps-before.json') -Value (lms ps --json)

    lms load $ModelKey -c $Context --parallel 1 --gpu max --identifier $Identifier -y |
        Out-File -LiteralPath (Join-Path $OutDir 'lms-load.txt') -Encoding utf8
    Start-Sleep -Seconds 2
    Set-Content -LiteralPath (Join-Path $OutDir 'lms-ps-after-load.json') -Value (lms ps --json)

    $proc = Get-Process llama-server -ErrorAction Stop | Sort-Object StartTime -Descending | Select-Object -First 1
    $commandLine = (Get-CimInstance Win32_Process -Filter "ProcessId=$($proc.Id)").CommandLine
    Set-Content -LiteralPath (Join-Path $OutDir 'command_line.txt') -Value $commandLine -Encoding utf8

    $proc.Refresh()
    $cpu0 = if ($proc.CPU -ne $null) { [double] $proc.CPU } else { 0.0 }

    $response = Invoke-RestMethod -Uri 'http://127.0.0.1:1234/v1/completions' -Method Post `
        -ContentType 'application/json' -Body (Get-Content -LiteralPath $requestPath -Raw) -TimeoutSec 240
    $response | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $OutDir 'response.json') -Encoding utf8

    $proc.Refresh()
    $cpu1 = if ($proc.CPU -ne $null) { [double] $proc.CPU } else { $cpu0 }
} finally {
    $wall.Stop()
    lms unload -a | Out-File -LiteralPath (Join-Path $OutDir 'lms-unload-after.txt') -Encoding utf8
}

$logText = ''
if (Test-Path -LiteralPath $serverLog) {
    $allLines = Get-Content -LiteralPath $serverLog
    $logText = ($allLines | Select-Object -Skip $lineStart) -join "`n"
    Set-Content -LiteralPath (Join-Path $OutDir 'server-log-excerpt.log') -Value $logText -Encoding utf8
}

$content = [string] $response.choices[0].text
if ([string]::IsNullOrWhiteSpace($content) -and $response.choices[0].message -ne $null) {
    $content = [string] $response.choices[0].message.content
}
$cpuSeconds = [math]::Max(0.0, [double] $cpu1 - [double] $cpu0)
$cpuAllCorePct = if ($wall.Elapsed.TotalSeconds -gt 0) {
    [math]::Round(100.0 * $cpuSeconds / $wall.Elapsed.TotalSeconds / [Environment]::ProcessorCount, 2)
} else {
    $null
}

$draftMtpSeen = ($logText -match "adding speculative implementation 'draft-mtp'")
$mtpAssistantSeen = ($logText -match 'loaded attached MTP assistant')
$gemmaAutoSeen = ($logText -match 'LMSTUDIO_GEMMA4_MTP_AUTO')
$qwenAutoSeen = ($logText -match 'LMSTUDIO_QWEN_MTP_AUTO')
$noSpecSeen = ($logText -match 'no implementations specified for speculative decoding')
$contentGate = -not [string]::IsNullOrWhiteSpace($content)
$cpuGate = ($cpuAllCorePct -ne $null -and [double] $cpuAllCorePct -le [double] $CpuAllCoreMaxPct)

$evalTokS = $null
if ($logText -match '\|\s+eval time =\s*([0-9.]+) ms /\s*(\d+) tokens .*?([0-9.]+) tokens per second') {
    $evalTokS = [double] $Matches[3]
}

$result = [pscustomobject]@{
    status = 'completed'
    runtime = '2.16.9374'
    model_key = $ModelKey
    identifier = $Identifier
    command_line = $commandLine
    wall_sec = [math]::Round($wall.Elapsed.TotalSeconds, 3)
    cpu_all_core_pct = $cpuAllCorePct
    cpu_all_core_max_pct = [double] $CpuAllCoreMaxPct
    prompt_tokens = $response.usage.prompt_tokens
    completion_tokens = $response.usage.completion_tokens
    eval_tok_s = $evalTokS
    content_nonempty = $contentGate
    no_spec_seen = $noSpecSeen
    draft_mtp_seen = $draftMtpSeen
    mtp_assistant_seen = $mtpAssistantSeen
    gemma_auto_seen = $gemmaAutoSeen
    qwen_auto_seen = $qwenAutoSeen
    cpu_gate_pass = $cpuGate
    gate_pass = ($contentGate -and $cpuGate -and $noSpecSeen -and -not $draftMtpSeen -and -not $mtpAssistantSeen -and -not $gemmaAutoSeen -and -not $qwenAutoSeen)
    content_preview = if ($content.Length -gt 400) { $content.Substring(0, 400) } else { $content }
}

$result | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $OutDir 'run.result.json') -Encoding utf8
$result | ConvertTo-Json -Depth 20
