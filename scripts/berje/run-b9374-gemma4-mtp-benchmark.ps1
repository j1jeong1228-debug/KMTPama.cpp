param(
    [ValidateSet('short16k', 'long29k', 'true32k', 'true32k-fitted', 'true32k-confirm')]
    [string] $Case = 'short16k',

    [string] $OutDir,

    [int] $Port = 18401,

    [int] $MaxTokens = 0,

    [int] $ContextOverride = 0,

    [int] $BatchOverride = 0,

    [int] $UBatchOverride = 0,

    [int] $CacheRam = 0,

    [ValidateSet('on', 'off', 'auto')]
    [string] $FlashAttn = 'on',

    [switch] $NoDirectIo,

    [ValidateRange(1, 16)]
    [int] $DraftNMax = 4,

    [switch] $ExplicitMtp,

    [switch] $TargetOnly,

    [switch] $DepthYieldTrace,

    [double] $AcceptanceFloorDelta = -0.03,

    [double] $DraftGeneratedMaxRatio = 1.10,

    [double] $CpuAllCoreMaxPct = 15.0,

    [int] $LongCtxDraftNMaxEnv = [int]::MinValue
)

$ErrorActionPreference = 'Stop'

$SourceRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$ServerExe = Join-Path $SourceRoot 'build-vs-cuda128\bin\Release\llama-server.exe'
$TargetPath = 'C:\Users\berje\.lmstudio\models\batiai\gemma-4-31B-it-GGUF\google-gemma-4-31B-it-IQ4_XS.gguf'
$AssistantPath = 'C:\Users\berje\.lmstudio\models\AtomicChat\gemma-4-31B-it-assistant-GGUF\gemma-4-31B-it-assistant.Q4_K_M.gguf'
$Passkey = 'ZX-TS87-QWEN'

if (-not (Test-Path -LiteralPath $ServerExe)) {
    throw "llama-server.exe not found: $ServerExe"
}
if (-not (Test-Path -LiteralPath $TargetPath)) {
    throw "target model not found: $TargetPath"
}
if ($ExplicitMtp -and $TargetOnly) {
    throw '-ExplicitMtp and -TargetOnly are mutually exclusive.'
}
if ($ExplicitMtp -and -not (Test-Path -LiteralPath $AssistantPath)) {
    throw "assistant model not found: $AssistantPath"
}
if (Get-Process llama-server -ErrorAction SilentlyContinue) {
    throw 'Refusing to start benchmark while llama-server.exe is already running.'
}

if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $OutDir = Join-Path $SourceRoot "artifacts\b9374-gemma4-$Case-$(Get-Date -Format yyyyMMdd-HHmmss)"
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$caseConfig = switch ($Case) {
    'short16k' {
        @{
            profile = 'short16K gate'
            context = 16384
            batch = 160
            filler_lines = 600
            max_tokens = 256
            gate_tok_s = 34.0
            preferred_tok_s = 36.0
            baseline_artifact = $null
            baseline_prompt_tokens = $null
            baseline_eval_tok_s = $null
            baseline_acceptance = $null
            baseline_draft_generated = $null
            require_depth_yield_when_traced = $false
        }
    }
    'long29k' {
        @{
            profile = 'long29K b9294 runtime-safe control'
            context = 65536
            batch = 160
            filler_lines = 1200
            max_tokens = 160
            gate_tok_s = 30.0
            preferred_tok_s = 32.0
            baseline_artifact = 'long65k-batiai-atomic-q4-broadoverride-polloff-nmax4-noargmax-margin010-160-20260526'
            baseline_prompt_tokens = 28936
            baseline_eval_tok_s = 31.20
            baseline_acceptance = 0.52195
            baseline_draft_generated = 205
            require_depth_yield_when_traced = $false
        }
    }
    'true32k' {
        @{
            profile = 'true32K+ b9294 160-token confirm'
            context = 65536
            batch = 160
            filler_lines = 1500
            max_tokens = 160
            gate_tok_s = 28.0
            preferred_tok_s = 30.0
            baseline_artifact = 'long65k-batiai-atomic-q4-true32k-depthyield-confirm-nmax4-margin010-160-20260526'
            baseline_prompt_tokens = 36436
            baseline_eval_tok_s = 28.71
            baseline_acceptance = 0.63576
            baseline_draft_generated = 151
            require_depth_yield_when_traced = $true
            target_trajectory_changed = $true
            current_path_acceptance_floor = 0.50
        }
    }
    'true32k-confirm' {
        @{
            profile = 'true32K+ b9294 160-token confirm'
            context = 65536
            batch = 160
            filler_lines = 1500
            max_tokens = 160
            gate_tok_s = 28.0
            preferred_tok_s = 30.0
            baseline_artifact = 'long65k-batiai-atomic-q4-true32k-depthyield-confirm-nmax4-margin010-160-20260526'
            baseline_prompt_tokens = 36436
            baseline_eval_tok_s = 28.71
            baseline_acceptance = 0.63576
            baseline_draft_generated = 151
            require_depth_yield_when_traced = $true
            target_trajectory_changed = $true
            current_path_acceptance_floor = 0.50
        }
    }
    'true32k-fitted' {
        @{
            profile = 'true32K fitted b9294 ctx36864/b32 control'
            context = 36864
            batch = 32
            filler_lines = 1400
            max_tokens = 64
            gate_tok_s = 28.0
            preferred_tok_s = 30.0
            baseline_artifact = 'true32k-q4kv-ctx36864-b32-control64-20260526'
            baseline_prompt_tokens = 33936
            baseline_eval_tok_s = 29.87
            baseline_acceptance = 0.59155
            baseline_draft_generated = 71
            require_depth_yield_when_traced = $false
        }
    }
}

if ($MaxTokens -gt 0) {
    $caseConfig.max_tokens = $MaxTokens
}
if ($ContextOverride -gt 0) {
    $caseConfig.context = $ContextOverride
}
if ($BatchOverride -gt 0) {
    $caseConfig.batch = $BatchOverride
}
$ubatch = [int] $caseConfig.batch
if ($UBatchOverride -gt 0) {
    $ubatch = $UBatchOverride
}

if ($DepthYieldTrace) {
    $env:LLAMA_GEMMA4_MTP_DEPTH_YIELD_TRACE = '1'
} else {
    Remove-Item Env:\LLAMA_GEMMA4_MTP_DEPTH_YIELD_TRACE -ErrorAction SilentlyContinue
}

if ($TargetOnly) {
    $env:LMSTUDIO_GEMMA4_MTP_AUTO_DISABLE = '1'
} else {
    Remove-Item Env:\LMSTUDIO_GEMMA4_MTP_AUTO_DISABLE -ErrorAction SilentlyContinue
}
Remove-Item Env:\LLAMA_GEMMA4_MTP_AUTO_DISABLE -ErrorAction SilentlyContinue
foreach ($name in @(
        'LLAMA_GEMMA4_MTP_GRAPH_MARGIN_MIN',
        'LLAMA_GEMMA4_MTP_LONGCTX_GRAPH_MARGIN_MIN',
        'LLAMA_GEMMA4_MTP_SHORTCTX_DRAFT_THRESHOLD',
        'LLAMA_GEMMA4_MTP_B9222_LAZY_PRENORM',
        'LLAMA_GEMMA4_MTP_ARGMAX_DISABLE')) {
    Remove-Item -LiteralPath "Env:\$name" -ErrorAction SilentlyContinue
}
if ($LongCtxDraftNMaxEnv -ne [int]::MinValue) {
    $env:LLAMA_GEMMA4_MTP_LONGCTX_DRAFT_N_MAX = [string] $LongCtxDraftNMaxEnv
}

$preGpuPath = Join-Path $OutDir 'pre-gpu.csv'
$prePmonPath = Join-Path $OutDir 'pre-pmon.txt'
nvidia-smi --query-gpu=index,name,memory.used,memory.free,utilization.gpu,utilization.memory --format=csv,noheader | Set-Content -LiteralPath $preGpuPath
nvidia-smi pmon -c 1 | Set-Content -LiteralPath $prePmonPath

$lines = New-Object System.Collections.Generic.List[string]
for ($i = 0; $i -lt [int] $caseConfig.filler_lines; $i++) {
    $lines.Add("This is neutral retrieval filler for a long-context generation benchmark. Keep reading.  index=$i.")
}
$prompt = ($lines -join "`n") + "`n`nPASSKEY: $Passkey`n`nIn your answer, first repeat the passkey exactly, then explain speculative decoding in concise bullet points."

$request = @{
    model = 'gemma4'
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
$request | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $requestPath

$args = @(
    '-m', $TargetPath,
    '-c', "$($caseConfig.context)",
    '-ngl', '999',
    '-fa', $FlashAttn,
    '--no-mmap',
    '--cache-ram', "$CacheRam",
    '--jinja',
    '-sm', 'layer',
    '-mg', '0',
    '-ts', '12,3',
    '-ctk', 'q4_0',
    '-ctv', 'q4_0',
    '-b', "$($caseConfig.batch)",
    '-ub', "$ubatch",
    '--poll', '0',
    '--poll-batch', '0',
    '-np', '1',
    '--slot-prompt-similarity', '0.1',
    '--host', '127.0.0.1',
    '--port', "$Port",
    '--reasoning', 'off',
    '--reasoning-budget', '0',
    '--no-warmup'
)

if ($NoDirectIo) {
    $args += @('--no-direct-io')
}

if ($ExplicitMtp) {
    $args += @(
        '--spec-type', 'draft-mtp',
        '--spec-draft-model', $AssistantPath,
        '--spec-draft-ngl', 'all',
        '--spec-draft-type-k', 'q4_0',
        '--spec-draft-type-v', 'q4_0',
        '--spec-draft-n-max', "$DraftNMax",
        '--spec-draft-p-min', '0',
        '--spec-draft-device', 'CUDA1',
        '--spec-draft-poll', '0',
        '--spec-draft-poll-batch', '0',
        '--spec-draft-override-tensor', '(mtp_pre_proj|mtp\.pre_projection|nextn\.pre_projection)\.weight=CUDA1,token_embd\.weight=CUDA1'
    )
}

Set-Content -LiteralPath (Join-Path $OutDir 'server.command.txt') -Value ($ServerExe + ' ' + ($args -join ' '))

$stderrPath = Join-Path $OutDir 'server.stderr.log'
$stdoutPath = Join-Path $OutDir 'server.stdout.log'
$pmonPath = Join-Path $OutDir 'during-pmon.txt'
$responsePath = Join-Path $OutDir 'response.json'
$resultPath = Join-Path $OutDir 'run.result.json'

$server = Start-Process -FilePath $ServerExe -ArgumentList $args -WorkingDirectory $SourceRoot `
    -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -WindowStyle Hidden -PassThru

$pmon = $null
$wall = [System.Diagnostics.Stopwatch]::StartNew()
$serverCpuBefore = 0.0
$serverCpuAfter = 0.0

try {
    $ready = $false
    $deadline = (Get-Date).AddMinutes(8)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 2
        if ($server.HasExited) {
            throw "server exited early with code $($server.ExitCode)"
        }
        try {
            Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$Port/health" -TimeoutSec 2 | Out-Null
            $ready = $true
            break
        } catch {
            $log = ''
            if (Test-Path -LiteralPath $stderrPath) {
                $log = Get-Content -LiteralPath $stderrPath -Raw
            }
            if ($log -match 'server is listening|listening on|HTTP server listening|llama server listening') {
                $ready = $true
                break
            }
        }
    }
    if (-not $ready) {
        throw 'server did not become ready before timeout'
    }

    $pmonCommand = "for (`$i=0; `$i -lt 360; `$i++) { Get-Date -Format o; nvidia-smi pmon -c 1; Start-Sleep -Milliseconds 500 }"
    $pmon = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $pmonCommand) `
        -RedirectStandardOutput $pmonPath -RedirectStandardError (Join-Path $OutDir 'during-pmon.err.txt') -WindowStyle Hidden -PassThru

    $serverCpuBefore = (Get-Process -Id $server.Id).CPU
    $wall.Restart()
    $resp = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/v1/chat/completions" -Method Post `
        -ContentType 'application/json' -Body (Get-Content -LiteralPath $requestPath -Raw) -TimeoutSec 900
    $wall.Stop()
    $serverCpuAfter = (Get-Process -Id $server.Id).CPU

    $resp | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $responsePath
    Start-Sleep -Seconds 2
} finally {
    if ($pmon -and -not $pmon.HasExited) {
        Stop-Process -Id $pmon.Id -Force -ErrorAction SilentlyContinue
        $pmon.WaitForExit(5000) | Out-Null
    }
    if (-not $server.HasExited) {
        Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue
        $server.WaitForExit(10000) | Out-Null
    }
}

$response = Get-Content -LiteralPath $responsePath -Raw | ConvertFrom-Json
$content = [string] $response.choices[0].message.content
$timings = $response.timings
$usage = $response.usage
$logText = ''
if (Test-Path -LiteralPath $stderrPath) {
    $logText += Get-Content -LiteralPath $stderrPath -Raw
}
if (Test-Path -LiteralPath $stdoutPath) {
    $logText += "`n" + (Get-Content -LiteralPath $stdoutPath -Raw)
}

$acceptance = $null
$draftAccepted = $null
$draftGenerated = $null
if ($logText -match 'draft acceptance =\s*([0-9.]+)\s*\(\s*(\d+) accepted /\s*(\d+) generated\)') {
    $acceptance = [double] $Matches[1]
    $draftAccepted = [int] $Matches[2]
    $draftGenerated = [int] $Matches[3]
}

$longctxMarginLog = $null
if ($logText -match 'longctx_margin=([^ ]+)') {
    $longctxMarginLog = $Matches[1]
}
$shortctxThresholdLog = $null
if ($logText -match 'shortctx_threshold=(\d+)') {
    $shortctxThresholdLog = [int] $Matches[1]
}
$autoBatchLog = $null
$autoUBatchLog = $null
if ($logText -match 'batch=(\d+) ubatch=(\d+)') {
    $autoBatchLog = [int] $Matches[1]
    $autoUBatchLog = [int] $Matches[2]
}
$effectiveDraftCapLog = $null
if ($logText -match '(short|mid|long)-context draft cap: .*?n_draft_max \d+ -> (\d+)') {
    $effectiveDraftCapLog = [pscustomobject]@{
        context = $Matches[1]
        n_max = [int] $Matches[2]
    }
}

$tokSGatePass = ([double] $timings.predicted_per_second -ge [double] $caseConfig.gate_tok_s)
$tokSPreferredPass = ([double] $timings.predicted_per_second -ge [double] $caseConfig.preferred_tok_s)
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
if ($targetTrajectoryChanged -and -not $TargetOnly) {
    $acceptanceGatePass = ($acceptance -ne $null -and [double] $acceptance -ge [double] $currentPathAcceptanceFloor)
    $draftGeneratedGatePass = $true
}
$trimmedContent = $content.TrimStart()
$passkeyExactPrefixOk = $trimmedContent.StartsWith($Passkey)
$passkeyLabelPrefixOk = $trimmedContent.StartsWith("PASSKEY: $Passkey")
$passkeyPrefixOk = ($passkeyExactPrefixOk -or $passkeyLabelPrefixOk)
$qualityGatePass = ($content.Contains($Passkey) -and $passkeyPrefixOk)
$mtpAttachGatePass = if ($TargetOnly) {
    (-not ($logText -match 'draft-mtp') -and -not ($logText -match 'loaded attached MTP assistant'))
} else {
    (($logText -match 'draft-mtp') -and ($logText -match 'loaded attached MTP assistant') -and -not ($logText -match "context type MTP requested but model doesn't contain MTP layers") -and -not ($logText -match '\[spec\] failed to measure'))
}
$depthYieldTraceGatePass = $true
if ($DepthYieldTrace -and [bool] $caseConfig.require_depth_yield_when_traced) {
    $depthYieldTraceGatePass = ($logText -match 'depth-yield long-context draft cap')
}

$logicalProcessors = [Environment]::ProcessorCount
$cpuSeconds = [math]::Max(0.0, [double] $serverCpuAfter - [double] $serverCpuBefore)
$cpuAllCorePct = if ($wall.Elapsed.TotalSeconds -gt 0) {
    [math]::Round(100.0 * $cpuSeconds / $wall.Elapsed.TotalSeconds / $logicalProcessors, 2)
} else {
    $null
}
$cpuGatePass = ($cpuAllCorePct -ne $null -and [double] $cpuAllCorePct -le [double] $CpuAllCoreMaxPct)
$combinedGatePass = ($tokSGatePass -and $acceptanceGatePass -and $draftGeneratedGatePass -and $qualityGatePass -and $mtpAttachGatePass -and $cpuGatePass -and $depthYieldTraceGatePass)
$combinedPreferredPass = ($tokSPreferredPass -and $acceptanceGatePass -and $draftGeneratedGatePass -and $qualityGatePass -and $mtpAttachGatePass -and $cpuGatePass -and $depthYieldTraceGatePass)

$result = [pscustomobject]@{
    status = 'completed'
    case = $Case
    profile = [string] $caseConfig.profile
    repo = $SourceRoot
    target_path = $TargetPath
    explicit_mtp = [bool] $ExplicitMtp
    target_only = [bool] $TargetOnly
    assistant_path = if ($ExplicitMtp) { $AssistantPath } else { $null }
    context = [int] $caseConfig.context
    batch = [int] $caseConfig.batch
    ubatch = [int] $ubatch
    cache_ram = [int] $CacheRam
    flash_attn = [string] $FlashAttn
    no_direct_io = [bool] $NoDirectIo
    filler_lines = [int] $caseConfig.filler_lines
    max_tokens = [int] $caseConfig.max_tokens
    draft_n_max = [int] $DraftNMax
    effective_draft_cap = $effectiveDraftCapLog
    gate_tok_s = [double] $caseConfig.gate_tok_s
    preferred_tok_s = [double] $caseConfig.preferred_tok_s
    baseline_artifact = $caseConfig.baseline_artifact
    baseline_prompt_tokens = $caseConfig.baseline_prompt_tokens
    baseline_eval_tok_s = $caseConfig.baseline_eval_tok_s
    baseline_acceptance = $caseConfig.baseline_acceptance
    baseline_draft_generated = $caseConfig.baseline_draft_generated
    acceptance_floor_delta = [double] $AcceptanceFloorDelta
    acceptance_floor = $acceptanceFloor
    target_trajectory_changed = $targetTrajectoryChanged
    current_path_acceptance_floor = $currentPathAcceptanceFloor
    draft_generated_max_ratio = [double] $DraftGeneratedMaxRatio
    draft_generated_ceiling = $draftGeneratedCeiling
    cpu_all_core_max_pct = [double] $CpuAllCoreMaxPct
    longctx_draft_n_max_env_override = if ($LongCtxDraftNMaxEnv -ne [int]::MinValue) { [int] $LongCtxDraftNMaxEnv } else { $null }
    wall_sec = [math]::Round($wall.Elapsed.TotalSeconds, 3)
    server_cpu_sec = [math]::Round($cpuSeconds, 3)
    server_cpu_all_core_pct = $cpuAllCorePct
    prompt_tokens = $usage.prompt_tokens
    completion_tokens = $usage.completion_tokens
    prompt_eval_ms = $timings.prompt_ms
    prompt_eval_tok_s = $timings.prompt_per_second
    eval_ms = $timings.predicted_ms
    eval_tok_s = $timings.predicted_per_second
    draft_acceptance = $acceptance
    draft_accepted = $draftAccepted
    draft_generated = $draftGenerated
    longctx_margin_log = $longctxMarginLog
    shortctx_threshold_log = $shortctxThresholdLog
    auto_batch_log = $autoBatchLog
    auto_ubatch_log = $autoUBatchLog
    passkey_present = $content.Contains($Passkey)
    passkey_prefix_ok = $passkeyPrefixOk
    passkey_exact_prefix_ok = $passkeyExactPrefixOk
    passkey_label_prefix_ok = $passkeyLabelPrefixOk
    quality_gate_pass = $qualityGatePass
    content_preview = if ($content.Length -gt 600) { $content.Substring(0, 600) } else { $content }
    auto_log = ($logText -match 'LMSTUDIO_GEMMA4_MTP_AUTO_B9294')
    attached = ($logText -match 'loaded attached MTP assistant')
    draft_mtp = ($logText -match 'draft-mtp')
    ctx_dft_no = ($logText -match 'ctx_dft=no')
    no_separate_draft_load = -not ($logText -match 'loading draft model')
    no_mtp_context_error = -not ($logText -match "context type MTP requested but model doesn't contain MTP layers")
    skip_external_fit = ($logText -match 'skipping fit pre-reservation for external attached MTP assistant')
    no_fit_measure_fail = -not ($logText -match '\[spec\] failed to measure')
    depth_yield_trace_seen = ($logText -match 'depth-yield long-context draft cap')
    depth_yield_trace_required = ($DepthYieldTrace -and [bool] $caseConfig.require_depth_yield_when_traced)
    tok_s_gate_pass = $tokSGatePass
    tok_s_preferred_pass = $tokSPreferredPass
    acceptance_gate_pass = $acceptanceGatePass
    historical_acceptance_gate_pass = $historicalAcceptanceGatePass
    draft_generated_gate_pass = $draftGeneratedGatePass
    historical_draft_generated_gate_pass = $historicalDraftGeneratedGatePass
    mtp_attach_gate_pass = $mtpAttachGatePass
    cpu_gate_pass = $cpuGatePass
    depth_yield_trace_gate_pass = $depthYieldTraceGatePass
    gate_pass = $combinedGatePass
    preferred_pass = $combinedPreferredPass
}

$result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resultPath
$result | ConvertTo-Json -Depth 10
