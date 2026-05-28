param(
    [ValidateSet('qwen-native-mtp-q8', 'target-only-qwen2')]
    [string] $Case = 'qwen-native-mtp-q8',

    [string] $OutDir,

    [int] $Port = 18481,

    [double] $CpuAllCoreMaxPct = 20.0
)

$ErrorActionPreference = 'Stop'

$SourceRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$ServerExe = Join-Path $SourceRoot 'build-vs-cuda128\bin\Release\llama-server.exe'
$QwenModel = 'C:\Users\berje\.lmstudio\models\abrasdaosfjnps\Qwen3.6-27B-uncensored-heretic-v2-Native-MTP-Preserved-GGUF\Qwen3.6-27B-uncensored-heretic-v2-Native-MTP-Preserved-Q4_K_S.gguf'
$TargetOnlyModel = 'C:\Users\berje\.lmstudio\models\spec-drafts\qwen2-1_5b-instruct-q4_0.gguf'

if (-not (Test-Path -LiteralPath $ServerExe)) {
    throw "llama-server.exe not found: $ServerExe"
}
if (Get-Process llama-server -ErrorAction SilentlyContinue) {
    throw 'Refusing to start smoke while llama-server.exe is already running.'
}

$caseConfig = switch ($Case) {
    'qwen-native-mtp-q8' {
        if (-not (Test-Path -LiteralPath $QwenModel)) {
            throw "Qwen model not found: $QwenModel"
        }
        @{
            model_path = $QwenModel
            model_label = 'Qwen3.6-27B Native MTP'
            context = 4096
            split_mode = 'tensor'
            tensor_split = '9,6'
            cache_type_k = 'q8_0'
            cache_type_v = 'q8_0'
            batch = 128
            ubatch = 128
            max_tokens = 32
            request_model = 'qwen36-native-mtp'
            prompt = 'Answer in one short sentence: what is speculative decoding?'
            command_extra = @('--spec-type', 'draft-mtp', '--spec-draft-type-k', 'q8_0', '--spec-draft-type-v', 'q8_0', '--spec-draft-n-max', '2', '--spec-draft-p-min', '0')
            eval_tok_s_gate = 35.0
            expected_spec = $true
        }
    }
    'target-only-qwen2' {
        if (-not (Test-Path -LiteralPath $TargetOnlyModel)) {
            throw "target-only model not found: $TargetOnlyModel"
        }
        @{
            model_path = $TargetOnlyModel
            model_label = 'qwen2-1_5b target-only'
            context = 2048
            split_mode = 'layer'
            tensor_split = $null
            cache_type_k = 'f16'
            cache_type_v = 'f16'
            batch = 128
            ubatch = 128
            max_tokens = 16
            request_model = 'target-only-smoke'
            prompt = 'Reply with exactly five words about clean inference.'
            command_extra = @()
            eval_tok_s_gate = 100.0
            expected_spec = $false
        }
    }
}

if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $OutDir = Join-Path $SourceRoot "artifacts\b9374-$Case-$(Get-Date -Format yyyyMMdd-HHmmss)"
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

foreach ($name in @(
        'LMSTUDIO_GEMMA4_MTP_AUTO_DISABLE',
        'LMSTUDIO_QWEN_MTP_AUTO_DISABLE',
        'LLAMA_GEMMA4_MTP_AUTO_DISABLE')) {
    Remove-Item -LiteralPath "Env:\$name" -ErrorAction SilentlyContinue
}

$request = @{
    model = [string] $caseConfig.request_model
    messages = @(
        @{
            role = 'user'
            content = [string] $caseConfig.prompt
        }
    )
    temperature = 0
    top_k = 1
    top_p = 1
    stream = $false
    max_tokens = [int] $caseConfig.max_tokens
}

$requestPath = Join-Path $OutDir 'request.json'
$responsePath = Join-Path $OutDir 'response.json'
$resultPath = Join-Path $OutDir 'run.result.json'
$stderrPath = Join-Path $OutDir 'server.stderr.log'
$stdoutPath = Join-Path $OutDir 'server.stdout.log'

$request | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $requestPath
nvidia-smi --query-gpu=index,name,memory.used,memory.total,utilization.gpu,utilization.memory,power.draw --format=csv,noheader,nounits |
    Set-Content -LiteralPath (Join-Path $OutDir 'pre-gpu.csv')
nvidia-smi pmon -c 1 | Set-Content -LiteralPath (Join-Path $OutDir 'pre-pmon.txt')

$args = @(
    '-m', [string] $caseConfig.model_path,
    '-c', [string] $caseConfig.context,
    '-ngl', '999',
    '-fa', 'on',
    '--no-mmap',
    '--cache-ram', '0',
    '--jinja',
    '-sm', [string] $caseConfig.split_mode
)
if ($caseConfig.tensor_split) {
    $args += @('-ts', [string] $caseConfig.tensor_split)
}
$args += @(
    '-ctk', [string] $caseConfig.cache_type_k,
    '-ctv', [string] $caseConfig.cache_type_v,
    '-b', [string] $caseConfig.batch,
    '-ub', [string] $caseConfig.ubatch,
    '--poll', '0',
    '--poll-batch', '0',
    '-np', '1',
    '--host', '127.0.0.1',
    '--port', [string] $Port,
    '--reasoning', 'off',
    '--reasoning-budget', '0',
    '--no-warmup'
)
$args += $caseConfig.command_extra

($ServerExe + " " + ($args -join ' ')) | Set-Content -LiteralPath (Join-Path $OutDir 'server.command.txt')

$server = $null
$serverCpuBefore = 0.0
$serverCpuAfter = 0.0
$wall = [Diagnostics.Stopwatch]::StartNew()
try {
    $server = Start-Process -FilePath $ServerExe -ArgumentList $args -WorkingDirectory $SourceRoot -RedirectStandardError $stderrPath -RedirectStandardOutput $stdoutPath -PassThru -WindowStyle Hidden

    $ready = $false
    for ($i = 0; $i -lt 180; $i++) {
        if ($server.HasExited) {
            throw "llama-server exited early with code $($server.ExitCode)"
        }
        try {
            $health = Invoke-RestMethod -Method Get -Uri "http://127.0.0.1:$Port/health" -TimeoutSec 2
            if ($health.status -eq 'ok' -or $health.status -eq 'no slot available') {
                $ready = $true
                break
            }
        } catch {
        }
        Start-Sleep -Seconds 1
    }
    if (-not $ready) {
        throw "server did not become ready on port $Port"
    }

    $server.Refresh()
    $serverCpuBefore = if ($server.CPU -ne $null) { [double] $server.CPU } else { 0.0 }
    $response = Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:$Port/v1/chat/completions" -ContentType 'application/json' -Body (Get-Content -LiteralPath $requestPath -Raw) -TimeoutSec 240
    $response | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $responsePath
    $server.Refresh()
    $serverCpuAfter = if ($server.CPU -ne $null) { [double] $server.CPU } else { $serverCpuBefore }
} finally {
    $wall.Stop()
    if ($server -and -not $server.HasExited) {
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

$cpuSeconds = [math]::Max(0.0, [double] $serverCpuAfter - [double] $serverCpuBefore)
$cpuAllCorePct = if ($wall.Elapsed.TotalSeconds -gt 0) {
    [math]::Round(100.0 * $cpuSeconds / $wall.Elapsed.TotalSeconds / [Environment]::ProcessorCount, 2)
} else {
    $null
}

$draftMtpSeen = ($logText -match "adding speculative implementation 'draft-mtp'")
$mtpContextSeen = ($logText -match 'creating MTP draft context against the target model')
$qwenAutoSeen = ($logText -match 'LMSTUDIO_QWEN_MTP_AUTO')
$gemmaAutoSeen = ($logText -match 'LMSTUDIO_GEMMA4_MTP_AUTO')
$tensorQ8 = ($logText -match 'cache_k=q8_0, cache_v=q8_0') -or (($args -join ' ') -match '-ctk q8_0' -and ($args -join ' ') -match '-ctv q8_0')
$contentGatePass = -not [string]::IsNullOrWhiteSpace($content)
$speedGatePass = ([double] $timings.predicted_per_second -ge [double] $caseConfig.eval_tok_s_gate)
$cpuGatePass = ($cpuAllCorePct -ne $null -and [double] $cpuAllCorePct -le [double] $CpuAllCoreMaxPct)

if ([bool] $caseConfig.expected_spec) {
    $specGatePass = ($draftMtpSeen -and $mtpContextSeen -and $tensorQ8 -and -not $gemmaAutoSeen)
} else {
    $specGatePass = (-not $draftMtpSeen -and -not $mtpContextSeen -and -not $qwenAutoSeen -and -not $gemmaAutoSeen)
}

$result = [pscustomobject]@{
    status = 'completed'
    case = $Case
    artifact = $OutDir
    model = [string] $caseConfig.model_label
    model_path = [string] $caseConfig.model_path
    context = [int] $caseConfig.context
    split_mode = [string] $caseConfig.split_mode
    tensor_split = $caseConfig.tensor_split
    kv = "$($caseConfig.cache_type_k)/$($caseConfig.cache_type_v)"
    expected_spec = [bool] $caseConfig.expected_spec
    prompt_tokens = $usage.prompt_tokens
    completion_tokens = $usage.completion_tokens
    prompt_eval_tok_s = $timings.prompt_per_second
    eval_tok_s = $timings.predicted_per_second
    draft_acceptance = $acceptance
    draft_accepted = $draftAccepted
    draft_generated = $draftGenerated
    server_cpu_all_core_pct = $cpuAllCorePct
    cpu_all_core_max_pct = [double] $CpuAllCoreMaxPct
    content_nonempty = $contentGatePass
    draft_mtp_seen = $draftMtpSeen
    mtp_context_seen = $mtpContextSeen
    tensor_q8_seen = $tensorQ8
    qwen_auto_seen = $qwenAutoSeen
    gemma_auto_seen = $gemmaAutoSeen
    no_separate_draft_model = -not ($logText -match 'loading draft model')
    speed_gate_pass = $speedGatePass
    cpu_gate_pass = $cpuGatePass
    spec_gate_pass = $specGatePass
    gate_pass = ($speedGatePass -and $cpuGatePass -and $specGatePass -and $contentGatePass)
    content_preview = if ($content.Length -gt 400) { $content.Substring(0, 400) } else { $content }
}

$result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resultPath
$result | ConvertTo-Json -Depth 10
