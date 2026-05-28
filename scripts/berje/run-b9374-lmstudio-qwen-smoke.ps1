param(
    [string] $OutDir,

    [string] $ModelKey = 'qwen3.6-27b-mtp',

    [string] $Identifier,

    [int] $Context = 4096,

    [double] $CpuAllCoreMaxPct = 20.0
)

$ErrorActionPreference = 'Stop'

$SourceRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

if ([string]::IsNullOrWhiteSpace($Identifier)) {
    $Identifier = "qwen36-b9374-lmstudio-q8-mtp-$(Get-Date -Format yyyyMMdd-HHmmss)"
}
if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $OutDir = Join-Path $SourceRoot "artifacts\lmstudio-b9374-qwen36-q8-mtp-$(Get-Date -Format yyyyMMdd-HHmmss)"
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
    messages = @(
        @{
            role = 'user'
            content = 'Answer in one short sentence: what is speculative decoding?'
        }
    )
    temperature = 0
    top_p = 1
    top_k = 1
    stream = $false
    max_tokens = 96
    reasoning_format = 'none'
    thinking_budget_tokens = 0
    chat_template_kwargs = @{
        enable_thinking = $false
    }
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

    $backendPort = $null
    if ($commandLine -match '--port\s+(\d+)') {
        $backendPort = [int] $Matches[1]
    }
    if ($backendPort -eq $null) {
        throw "Could not parse backend port from command line: $commandLine"
    }
    $apiKey = $null
    if ($commandLine -match '--api-key\s+(\S+)') {
        $apiKey = [string] $Matches[1]
    }
    if ([string]::IsNullOrWhiteSpace($apiKey)) {
        throw "Could not parse backend API key from command line: $commandLine"
    }
    $backendHeaders = @{
        Authorization = "Bearer $apiKey"
    }

    $proc.Refresh()
    $cpu0 = if ($proc.CPU -ne $null) { [double] $proc.CPU } else { 0.0 }

    $body = Get-Content -LiteralPath $requestPath -Raw
    $proxyResponse = Invoke-RestMethod -Uri 'http://127.0.0.1:1234/v1/chat/completions' -Method Post `
        -ContentType 'application/json' -Body $body -TimeoutSec 240
    $backendResponse = Invoke-RestMethod -Uri "http://127.0.0.1:$backendPort/v1/chat/completions" -Method Post `
        -ContentType 'application/json' -Headers $backendHeaders -Body $body -TimeoutSec 240

    $proxyResponse | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $OutDir 'response-proxy1234.json') -Encoding utf8
    $backendResponse | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $OutDir 'response-backend-direct.json') -Encoding utf8

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

$proxyContent = [string] $proxyResponse.choices[0].message.content
$proxyReasoning = [string] $proxyResponse.choices[0].message.reasoning_content
$backendContent = [string] $backendResponse.choices[0].message.content
$backendReasoning = [string] $backendResponse.choices[0].message.reasoning_content

$cpuSeconds = [math]::Max(0.0, [double] $cpu1 - [double] $cpu0)
$cpuAllCorePct = if ($wall.Elapsed.TotalSeconds -gt 0) {
    [math]::Round(100.0 * $cpuSeconds / $wall.Elapsed.TotalSeconds / [Environment]::ProcessorCount, 2)
} else {
    $null
}

$tensorSplitSeen = (($commandLine -match '--tensor-split\s+9,6') -or ($logText -match 'tensor_split=9,6'))
$q8KvSeen = (($commandLine -match '--cache-type-k\s+q8_0') -and ($commandLine -match '--cache-type-v\s+q8_0')) -or
    ($logText -match 'cache_k=q8_0, cache_v=q8_0')
$kvUnifiedSeen = ($commandLine -match '--kv-unified')
$qwenAutoSeen = ($logText -match 'LMSTUDIO_QWEN_MTP_AUTO')
$qwenReasoningOffSeen = ($logText -match 'reasoning=off-by-default')
$draftMtpSeen = ($logText -match "adding speculative implementation 'draft-mtp'")
$mtpContextSeen = ($logText -match 'creating MTP draft context against the target model')
$gemmaAutoSeen = ($logText -match 'LMSTUDIO_GEMMA4_MTP_AUTO')
$proxyContentGate = -not [string]::IsNullOrWhiteSpace($proxyContent)
$backendContentGate = -not [string]::IsNullOrWhiteSpace($backendContent)
$proxyReasoningEmpty = [string]::IsNullOrWhiteSpace($proxyReasoning)
$backendReasoningEmpty = [string]::IsNullOrWhiteSpace($backendReasoning)
$cpuGatePass = ($cpuAllCorePct -ne $null -and [double] $cpuAllCorePct -le [double] $CpuAllCoreMaxPct)

$result = [pscustomobject]@{
    status = 'completed'
    runtime = '2.16.9374'
    model_key = $ModelKey
    identifier = $Identifier
    backend_port = $backendPort
    api_key_seen = -not [string]::IsNullOrWhiteSpace($apiKey)
    command_line = $commandLine
    wall_sec = [math]::Round($wall.Elapsed.TotalSeconds, 3)
    cpu_all_core_pct = $cpuAllCorePct
    cpu_all_core_max_pct = [double] $CpuAllCoreMaxPct
    tensor_split_seen = $tensorSplitSeen
    q8_kv_seen = $q8KvSeen
    kv_unified_seen = $kvUnifiedSeen
    qwen_auto_log = $qwenAutoSeen
    qwen_reasoning_off_log = $qwenReasoningOffSeen
    draft_mtp_seen = $draftMtpSeen
    mtp_context_seen = $mtpContextSeen
    gemma_auto_seen = $gemmaAutoSeen
    proxy = @{
        content_empty = -not $proxyContentGate
        content_preview = if ($proxyContent.Length -gt 400) { $proxyContent.Substring(0, 400) } else { $proxyContent }
        reasoning_empty = $proxyReasoningEmpty
        prompt_tokens = $proxyResponse.usage.prompt_tokens
        completion_tokens = $proxyResponse.usage.completion_tokens
        reasoning_tokens = $proxyResponse.usage.completion_tokens_details.reasoning_tokens
    }
    backend_direct = @{
        content_empty = -not $backendContentGate
        content_preview = if ($backendContent.Length -gt 400) { $backendContent.Substring(0, 400) } else { $backendContent }
        reasoning_empty = $backendReasoningEmpty
        prompt_tokens = $backendResponse.usage.prompt_tokens
        completion_tokens = $backendResponse.usage.completion_tokens
        eval_tok_s = $backendResponse.timings.predicted_per_second
    }
    gate_pass = ($tensorSplitSeen -and $q8KvSeen -and $kvUnifiedSeen -and $qwenAutoSeen -and
        $qwenReasoningOffSeen -and $draftMtpSeen -and $mtpContextSeen -and -not $gemmaAutoSeen -and
        $proxyContentGate -and $backendContentGate -and $proxyReasoningEmpty -and $backendReasoningEmpty -and $cpuGatePass)
}

$result | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $OutDir 'run.result.json') -Encoding utf8
$result | ConvertTo-Json -Depth 20
