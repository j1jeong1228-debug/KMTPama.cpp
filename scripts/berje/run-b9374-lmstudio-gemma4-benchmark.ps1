param(
    [ValidateSet('short16k', 'long29k', 'true32k-fitted', 'true32k-confirm')]
    [string] $Case = 'short16k',

    [string] $OutDir,

    [int] $Context = 0,

    [string] $Identifier,

    [int] $MaxTokens = 0,

    [double] $AcceptanceFloorDelta = -0.03,

    [double] $DraftGeneratedMaxRatio = 1.10,

    [double] $CpuAllCoreMaxPct = 15.0
)

$ErrorActionPreference = 'Stop'

$SourceRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Passkey = 'ZX-TS87-QWEN'

if ([string]::IsNullOrWhiteSpace($Identifier)) {
    $Identifier = "gemma-b9374-lmstudio-$Case-$(Get-Date -Format yyyyMMdd-HHmmss)"
}
if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $OutDir = Join-Path $SourceRoot "artifacts\lmstudio-b9374-gemma-$Case-$(Get-Date -Format yyyyMMdd-HHmmss)"
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$caseConfig = switch ($Case) {
    'short16k' {
        @{
            context = 65536
            filler_lines = 600
            max_tokens = 256
            gate_tok_s = 34.0
            preferred_tok_s = 36.0
            baseline_acceptance = $null
            baseline_draft_generated = $null
        }
    }
    'long29k' {
        @{
            context = 65536
            filler_lines = 1200
            max_tokens = 160
            gate_tok_s = 30.0
            preferred_tok_s = 32.0
            baseline_acceptance = 0.52195
            baseline_draft_generated = 205
        }
    }
    'true32k-fitted' {
        @{
            context = 36864
            filler_lines = 1400
            max_tokens = 64
            gate_tok_s = 28.0
            preferred_tok_s = 30.0
            baseline_acceptance = 0.59155
            baseline_draft_generated = 71
        }
    }
    'true32k-confirm' {
        @{
            context = 65536
            filler_lines = 1500
            max_tokens = 160
            gate_tok_s = 28.0
            preferred_tok_s = 30.0
            baseline_acceptance = 0.63576
            baseline_draft_generated = 151
            target_trajectory_changed = $true
            current_path_acceptance_floor = 0.50
        }
    }
}
if ($MaxTokens -gt 0) {
    $caseConfig.max_tokens = $MaxTokens
}
if ($Context -gt 0) {
    $caseConfig.context = $Context
}

$month = Get-Date -Format 'yyyy-MM'
$day = Get-Date -Format 'yyyy-MM-dd'
$serverLog = "C:\Users\berje\.lmstudio\server-logs\$month\$day.1.log"
$lineStart = 0
if (Test-Path -LiteralPath $serverLog) {
    $lineStart = (Get-Content -LiteralPath $serverLog | Measure-Object -Line).Lines
}

lms unload -a | Out-File -LiteralPath (Join-Path $OutDir 'lms-unload.txt') -Encoding utf8
Start-Sleep -Seconds 2
Set-Content -LiteralPath (Join-Path $OutDir 'lms-ps-before-load.json') -Value (lms ps --json)

lms load batiai/gemma-4-31b-it -c $($caseConfig.context) --parallel 1 --gpu max --identifier $Identifier -y |
    Out-File -LiteralPath (Join-Path $OutDir 'lms-load.txt') -Encoding utf8
Start-Sleep -Seconds 2
Set-Content -LiteralPath (Join-Path $OutDir 'lms-ps-after-load.json') -Value (lms ps --json)

$proc = Get-Process llama-server -ErrorAction Stop | Sort-Object StartTime -Descending | Select-Object -First 1
$commandLine = (Get-CimInstance Win32_Process -Filter "ProcessId=$($proc.Id)").CommandLine
Set-Content -LiteralPath (Join-Path $OutDir 'command_line.txt') -Value $commandLine

nvidia-smi --query-gpu=index,name,memory.used,memory.total,utilization.gpu,utilization.memory,power.draw --format=csv,noheader,nounits |
    Set-Content -LiteralPath (Join-Path $OutDir 'gpu-before.csv')

$lines = New-Object System.Collections.Generic.List[string]
for ($i = 0; $i -lt [int] $caseConfig.filler_lines; $i++) {
    $lines.Add("This is neutral retrieval filler for a long-context generation benchmark. Keep reading.  index=$i.")
}
$prompt = ($lines -join "`n") + "`n`nPASSKEY: $Passkey`n`nIn your answer, first repeat the passkey exactly, then explain speculative decoding in concise bullet points."

$request = @{
    model = $Identifier
    messages = @(
        @{
            role = 'user'
            content = $prompt
        }
    )
    temperature = 0
    top_p = 1
    top_k = 1
    stream = $false
    max_tokens = [int] $caseConfig.max_tokens
}
$requestPath = Join-Path $OutDir 'request.json'
$request | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $requestPath -Encoding utf8

$cpu0 = (Get-Process -Id $proc.Id).CPU
$t0 = Get-Date
$response = Invoke-RestMethod -Uri 'http://127.0.0.1:1234/v1/chat/completions' -Method Post `
    -ContentType 'application/json' -InFile $requestPath -TimeoutSec 900
$t1 = Get-Date
$cpu1 = (Get-Process -Id $proc.Id).CPU

$response | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $OutDir 'response.json') -Encoding utf8
nvidia-smi --query-gpu=index,name,memory.used,memory.total,utilization.gpu,utilization.memory,power.draw --format=csv,noheader,nounits |
    Set-Content -LiteralPath (Join-Path $OutDir 'gpu-after.csv')

$logText = ''
if (Test-Path -LiteralPath $serverLog) {
    $allLines = Get-Content -LiteralPath $serverLog
    $logText = ($allLines | Select-Object -Skip $lineStart) -join "`n"
    Set-Content -LiteralPath (Join-Path $OutDir 'server-log-excerpt.log') -Value $logText -Encoding utf8
}

$promptEvalMs = $null
$promptTokens = $response.usage.prompt_tokens
$promptEvalTokS = $null
if ($logText -match '\|\s+prompt eval time =\s*([0-9.]+) ms /\s*(\d+) tokens .*?([0-9.]+) tokens per second') {
    $promptEvalMs = [double] $Matches[1]
    $promptTokens = [int] $Matches[2]
    $promptEvalTokS = [double] $Matches[3]
}

$evalMs = $null
$completionTokens = $response.usage.completion_tokens
$evalTokS = $null
if ($logText -match '\|\s+eval time =\s*([0-9.]+) ms /\s*(\d+) tokens .*?([0-9.]+) tokens per second') {
    $evalMs = [double] $Matches[1]
    $completionTokens = [int] $Matches[2]
    $evalTokS = [double] $Matches[3]
}

$acceptance = $null
$draftAccepted = $null
$draftGenerated = $null
if ($logText -match 'draft acceptance = ([0-9.]+) \(\s*(\d+) accepted /\s*(\d+) generated\)') {
    $acceptance = [double] $Matches[1]
    $draftAccepted = [int] $Matches[2]
    $draftGenerated = [int] $Matches[3]
}

$autoBatch = $null
$autoUBatch = $null
if ($logText -match 'batch=(\d+) ubatch=(\d+)') {
    $autoBatch = [int] $Matches[1]
    $autoUBatch = [int] $Matches[2]
}

$effectiveCap = $null
if ($logText -match '(short|mid|long)-context draft cap:.*->\s*(\d+)') {
    $effectiveCap = @{
        context = $Matches[1]
        n_max = [int] $Matches[2]
    }
}

$content = [string] $response.choices[0].message.content
$cachedTokens = $null
if ($response.usage.prompt_tokens_details -and $response.usage.prompt_tokens_details.cached_tokens -ne $null) {
    $cachedTokens = [int] $response.usage.prompt_tokens_details.cached_tokens
}

$wallSec = [math]::Max(($t1 - $t0).TotalSeconds, 0.001)
$cpuPct = [math]::Round((($cpu1 - $cpu0) / $wallSec) / [Environment]::ProcessorCount * 100, 2)
$tokSGatePass = ($evalTokS -ne $null -and $evalTokS -ge [double] $caseConfig.gate_tok_s)
$tokSPreferredPass = ($evalTokS -ne $null -and $evalTokS -ge [double] $caseConfig.preferred_tok_s)
$acceptanceGatePass = $true
$acceptanceFloor = $null
if ($caseConfig.baseline_acceptance -ne $null) {
    $acceptanceFloor = [double] $caseConfig.baseline_acceptance + [double] $AcceptanceFloorDelta
    $acceptanceGatePass = ($acceptance -ne $null -and [double] $acceptance -ge $acceptanceFloor)
}
$historicalAcceptanceGatePass = $acceptanceGatePass
$draftGeneratedGatePass = $true
$draftGeneratedCeiling = $null
if ($caseConfig.baseline_draft_generated -ne $null) {
    $draftGeneratedCeiling = [int] [math]::Ceiling([double] $caseConfig.baseline_draft_generated * [double] $DraftGeneratedMaxRatio)
    $draftGeneratedGatePass = ($draftGenerated -ne $null -and [int] $draftGenerated -le $draftGeneratedCeiling)
}
$historicalDraftGeneratedGatePass = $draftGeneratedGatePass
$targetTrajectoryChanged = [bool] $caseConfig.target_trajectory_changed
$currentPathAcceptanceFloor = $caseConfig.current_path_acceptance_floor
if ($targetTrajectoryChanged) {
    $acceptanceGatePass = ($acceptance -ne $null -and [double] $acceptance -ge [double] $currentPathAcceptanceFloor)
    $draftGeneratedGatePass = $true
}
$trimmedContent = $content.TrimStart()
$passkeyExactPrefixOk = $trimmedContent.StartsWith($Passkey)
$passkeyLabelPrefixOk = $trimmedContent.StartsWith("PASSKEY: $Passkey")
$passkeyPrefixOk = ($passkeyExactPrefixOk -or $passkeyLabelPrefixOk)
$qualityGatePass = ($content.Contains($Passkey) -and $passkeyPrefixOk)
$mtpAttachGatePass = (($logText -match "adding speculative implementation 'draft-mtp'") -and ($logText -match 'loaded attached MTP assistant'))
$cpuGatePass = ($cpuPct -le [double] $CpuAllCoreMaxPct)
$combinedGatePass = ($tokSGatePass -and $acceptanceGatePass -and $draftGeneratedGatePass -and $qualityGatePass -and $mtpAttachGatePass -and $cpuGatePass)
$combinedPreferredPass = ($tokSPreferredPass -and $acceptanceGatePass -and $draftGeneratedGatePass -and $qualityGatePass -and $mtpAttachGatePass -and $cpuGatePass)

$result = [pscustomobject]@{
    status = 'completed'
    runtime = '2.16.9374'
    case = $Case
    model_identifier = $Identifier
    context = [int] $caseConfig.context
    command_line = $commandLine
    wall_sec = [math]::Round($wallSec, 3)
    cpu_all_core_pct = $cpuPct
    prompt_tokens = $promptTokens
    cached_tokens = $cachedTokens
    completion_tokens = $completionTokens
    prompt_eval_ms = $promptEvalMs
    prompt_eval_tok_s = $promptEvalTokS
    eval_ms = $evalMs
    eval_tok_s = $evalTokS
    draft_acceptance = $acceptance
    draft_accepted = $draftAccepted
    draft_generated = $draftGenerated
    baseline_acceptance = $caseConfig.baseline_acceptance
    baseline_draft_generated = $caseConfig.baseline_draft_generated
    acceptance_floor_delta = [double] $AcceptanceFloorDelta
    acceptance_floor = $acceptanceFloor
    target_trajectory_changed = $targetTrajectoryChanged
    current_path_acceptance_floor = $currentPathAcceptanceFloor
    draft_generated_max_ratio = [double] $DraftGeneratedMaxRatio
    draft_generated_ceiling = $draftGeneratedCeiling
    cpu_all_core_max_pct = [double] $CpuAllCoreMaxPct
    effective_draft_cap = $effectiveCap
    auto_batch_log = $autoBatch
    auto_ubatch_log = $autoUBatch
    passkey_present = $content.Contains($Passkey)
    passkey_prefix_ok = $passkeyPrefixOk
    passkey_exact_prefix_ok = $passkeyExactPrefixOk
    passkey_label_prefix_ok = $passkeyLabelPrefixOk
    quality_gate_pass = $qualityGatePass
    draft_mtp_load_seen = ($logText -match "adding speculative implementation 'draft-mtp'")
    attached_mtp_seen = ($logText -match 'loaded attached MTP assistant')
    prompt_cache_enabled = ($logText -match 'prompt cache is enabled')
    gate_tok_s = [double] $caseConfig.gate_tok_s
    preferred_tok_s = [double] $caseConfig.preferred_tok_s
    tok_s_gate_pass = $tokSGatePass
    tok_s_preferred_pass = $tokSPreferredPass
    acceptance_gate_pass = $acceptanceGatePass
    historical_acceptance_gate_pass = $historicalAcceptanceGatePass
    draft_generated_gate_pass = $draftGeneratedGatePass
    historical_draft_generated_gate_pass = $historicalDraftGeneratedGatePass
    mtp_attach_gate_pass = $mtpAttachGatePass
    cpu_gate_pass = $cpuGatePass
    gate_pass = $combinedGatePass
    preferred_pass = $combinedPreferredPass
    content_preview = if ($content.Length -gt 600) { $content.Substring(0, 600) } else { $content }
}

$result | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $OutDir 'run.result.json') -Encoding utf8
$result | ConvertTo-Json -Depth 20
