param(
    [string] $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path,
    [switch] $RequirePortedGemmaEngine
)

$ErrorActionPreference = 'Stop'

function Test-Text {
    param(
        [Parameter(Mandatory=$true)] [string] $Path,
        [Parameter(Mandatory=$true)] [string] $Pattern
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }
    return [bool](Select-String -LiteralPath $Path -Pattern $Pattern -Quiet)
}

function Add-Result {
    param(
        [Parameter(Mandatory=$true)] [string] $Name,
        [Parameter(Mandatory=$true)] [bool] $Pass,
        [Parameter(Mandatory=$true)] [string] $Detail
    )
    [pscustomobject]@{
        name = $Name
        pass = $Pass
        detail = $Detail
    }
}

$commonSpec = Join-Path $RepoRoot 'common\speculative.cpp'
$commonArg = Join-Path $RepoRoot 'common\arg.cpp'
$serverContext = Join-Path $RepoRoot 'tools\server\server-context.cpp'
$qwen35 = Join-Path $RepoRoot 'src\models\qwen35.cpp'
$qwen35moe = Join-Path $RepoRoot 'src\models\qwen35moe.cpp'
$llamaContext = Join-Path $RepoRoot 'src\llama-context.cpp'
$llamaArch = Join-Path $RepoRoot 'src\llama-arch.cpp'
$llamaArchH = Join-Path $RepoRoot 'src\llama-arch.h'
$manifest = Join-Path $RepoRoot 'docs\berje\mtp-rebase\PATCH-MANIFEST.md'
$defects = Join-Path $RepoRoot 'docs\berje\mtp-rebase\DEFECTS.md'
$portSlices = Join-Path $RepoRoot 'docs\berje\mtp-rebase\GEMMA4-DEDICATED-MTP-PORT-SLICES.md'
$benchRunner = Join-Path $RepoRoot 'scripts\berje\run-b9374-gemma4-mtp-benchmark.ps1'
$qwenSmokeRunner = Join-Path $RepoRoot 'scripts\berje\run-b9374-qwen-target-smoke.ps1'
$lmstudioQwenSmokeRunner = Join-Path $RepoRoot 'scripts\berje\run-b9374-lmstudio-qwen-smoke.ps1'
$lmstudioTargetOnlySmokeRunner = Join-Path $RepoRoot 'scripts\berje\run-b9374-lmstudio-targetonly-smoke.ps1'

$results = @()

$results += Add-Result `
    -Name 'manifest exists and records b9294 dedicated engine requirement' `
    -Pass ((Test-Path -LiteralPath $manifest) -and (Test-Text $manifest 'dedicated attached-MTP execution engine')) `
    -Detail $manifest

$hasB9294BestMatrix =
    (Test-Text $manifest 'long29K runtime-safe') -and
    (Test-Text $manifest 'true32K fitted') -and
    (Test-Text $manifest 'true32K confirm') -and
    (Test-Text $manifest '31\.57/31\.20 tok/s records are long29K-ish')

$results += Add-Result `
    -Name 'manifest separates long29K and true32K b9294 best controls' `
    -Pass $hasB9294BestMatrix `
    -Detail $manifest

$hasBestMatrixRunner =
    (Test-Text $benchRunner "ValidateSet\('short16k', 'long29k', 'true32k', 'true32k-fitted', 'true32k-confirm'\)") -and
    (Test-Text $benchRunner "baseline_artifact = 'long65k-batiai-atomic-q4-broadoverride-polloff-nmax4-noargmax-margin010-160-20260526'") -and
    (Test-Text $benchRunner "baseline_artifact = 'true32k-q4kv-ctx36864-b32-control64-20260526'") -and
    (Test-Text $benchRunner "baseline_artifact = 'long65k-batiai-atomic-q4-true32k-depthyield-confirm-nmax4-margin010-160-20260526'") -and
    (Test-Text $benchRunner 'context = 36864') -and
    (Test-Text $benchRunner 'batch = 32') -and
    (Test-Text $benchRunner 'filler_lines = 1400') -and
    (Test-Text $benchRunner 'max_tokens = 64')

$results += Add-Result `
    -Name 'benchmark runner preserves b9294 long29K and true32K profile matrix' `
    -Pass $hasBestMatrixRunner `
    -Detail $benchRunner

$hasBenchmarkGuardRails =
    (Test-Text $benchRunner 'tok_s_gate_pass') -and
    (Test-Text $benchRunner 'acceptance_gate_pass') -and
    (Test-Text $benchRunner 'draft_generated_gate_pass') -and
    (Test-Text $benchRunner 'quality_gate_pass') -and
    (Test-Text $benchRunner 'mtp_attach_gate_pass') -and
    (Test-Text $benchRunner 'cpu_gate_pass') -and
    (Test-Text $benchRunner 'depth_yield_trace_gate_pass') -and
    (Test-Text $benchRunner 'historical_acceptance_gate_pass') -and
    (Test-Text $benchRunner 'current_path_acceptance_floor')

$results += Add-Result `
    -Name 'benchmark runner requires speed plus acceptance, quality, CPU, and depth-yield evidence' `
    -Pass $hasBenchmarkGuardRails `
    -Detail $benchRunner

$hasQwenTargetSmokeRunner =
    (Test-Path -LiteralPath $qwenSmokeRunner) -and
    (Test-Text $qwenSmokeRunner "ValidateSet\('qwen-native-mtp-q8', 'target-only-qwen2'\)") -and
    (Test-Text $qwenSmokeRunner 'Qwen3\.6-27B-uncensored-heretic-v2-Native-MTP-Preserved-Q4_K_S\.gguf') -and
    (Test-Text $qwenSmokeRunner 'spec-drafts\\qwen2-1_5b-instruct-q4_0\.gguf') -and
    (Test-Text $qwenSmokeRunner 'spec_gate_pass') -and
    (Test-Text $qwenSmokeRunner 'tensor_q8_seen') -and
    (Test-Text $qwenSmokeRunner 'gemma_auto_seen')

$results += Add-Result `
    -Name 'Qwen Tensor/Internal and target-only smoke runner records model isolation gates' `
    -Pass $hasQwenTargetSmokeRunner `
    -Detail $qwenSmokeRunner

$hasLmStudioQwenSmokeRunner =
    (Test-Path -LiteralPath $lmstudioQwenSmokeRunner) -and
    (Test-Text $lmstudioQwenSmokeRunner 'qwen3\.6-27b-mtp') -and
    (Test-Text $lmstudioQwenSmokeRunner 'tensor_split_seen') -and
    (Test-Text $lmstudioQwenSmokeRunner 'q8_kv_seen') -and
    (Test-Text $lmstudioQwenSmokeRunner 'qwen_reasoning_off_log') -and
    (Test-Text $lmstudioQwenSmokeRunner 'draft_mtp_seen') -and
    (Test-Text $lmstudioQwenSmokeRunner 'proxy') -and
    (Test-Text $lmstudioQwenSmokeRunner 'backend_direct')

$results += Add-Result `
    -Name 'LM Studio Qwen Tensor/Internal native MTP smoke runner records proxy/backend gates' `
    -Pass $hasLmStudioQwenSmokeRunner `
    -Detail $lmstudioQwenSmokeRunner

$hasLmStudioTargetOnlySmokeRunner =
    (Test-Path -LiteralPath $lmstudioTargetOnlySmokeRunner) -and
    (Test-Text $lmstudioTargetOnlySmokeRunner 'google/gemma-4-26b-a4b') -and
    (Test-Text $lmstudioTargetOnlySmokeRunner '/v1/completions') -and
    (Test-Text $lmstudioTargetOnlySmokeRunner 'no_spec_seen') -and
    (Test-Text $lmstudioTargetOnlySmokeRunner 'draft_mtp_seen') -and
    (Test-Text $lmstudioTargetOnlySmokeRunner 'gemma_auto_seen') -and
    (Test-Text $lmstudioTargetOnlySmokeRunner 'qwen_auto_seen')

$results += Add-Result `
    -Name 'LM Studio target-only smoke runner records no-spec isolation gates' `
    -Pass $hasLmStudioTargetOnlySmokeRunner `
    -Detail $lmstudioTargetOnlySmokeRunner

$results += Add-Result `
    -Name 'defect register records true32K target drift and calibration boundary' `
    -Pass ((Test-Path -LiteralPath $defects) -and
           (Test-Text $defects 'GEMMA4-TRUE32K-001') -and
           (Test-Text $defects '98/184 = 0\.53261') -and
           (Test-Text $defects 'b9294 target-only') -and
           (Test-Text $defects 'b9374 target-only') -and
           (Test-Text $defects 'current target-path parity') -and
           (Test-Text $defects 'PASSKEY: ZX-TS87-QWEN')) `
    -Detail $defects

$results += Add-Result `
    -Name 'defect register records Qwen reasoning-only quality fix and guard' `
    -Pass ((Test-Path -LiteralPath $defects) -and
           (Test-Text $defects 'QWEN-TENSOR-001') -and
           (Test-Text $defects 'reasoning=off-by-default') -and
           (Test-Text $defects 'lmstudio-b9374-qwen36-proxy-vs-backend-reasoningoff-20260529-1') -and
           (Test-Text $commonArg 'LMSTUDIO_QWEN_MTP_KEEP_REASONING') -and
           (Test-Text $commonArg 'enable_thinking.*false')) `
    -Detail $defects

$results += Add-Result `
    -Name 'upstream qwen35 native MTP graph is present' `
    -Pass ((Test-Text $qwen35 'LLM_GRAPH_TYPE_DECODER_MTP') -and (Test-Text $qwen35 'nextn\.eh_proj')) `
    -Detail $qwen35

$results += Add-Result `
    -Name 'upstream qwen35moe native MTP graph is present' `
    -Pass ((Test-Text $qwen35moe 'LLM_GRAPH_TYPE_DECODER_MTP') -and (Test-Text $qwen35moe 'nextn\.eh_proj')) `
    -Detail $qwen35moe

$results += Add-Result `
    -Name 'gemma4 assistant arch and loader alias groundwork is ported' `
    -Pass ((Test-Text $llamaArchH 'LLM_ARCH_GEMMA4_ASSISTANT') -and
           (Test-Text $llamaArch 'gemma4_assistant') -and
           (Test-Text (Join-Path $RepoRoot 'src\llama-model-loader.cpp') 'llama_model_loader_gemma4_assistant_alias_key')) `
    -Detail 'src/llama-arch.*, src/llama-model-loader.cpp'

$results += Add-Result `
    -Name 'port slices exclude unrelated dflash/eagle experiments' `
    -Pass ((Test-Path -LiteralPath $portSlices) -and
           -not (Test-Text $llamaArchH 'LLM_ARCH_DFLASH_DRAFT') -and
           -not (Test-Text $llamaArchH 'LLM_ARCH_EAGLE3_DRAFT')) `
    -Detail $portSlices

$hasQwenQ8Guard =
    (Test-Text $llamaContext 'allow_qwen35_q8_kv') -and
    (Test-Text $llamaContext 'LLM_ARCH_QWEN35') -and
    (Test-Text $llamaContext 'GGML_TYPE_Q8_0')

$results += Add-Result `
    -Name 'qwen tensor/internal q8 kv guarded allowlist is ported' `
    -Pass $hasQwenQ8Guard `
    -Detail $llamaContext

$hasQwenLmStudioRepair =
    (Test-Text $commonArg 'common_qwen35_tensor_internal_q8_requested') -and
    (Test-Text $commonArg 'params\.kv_unified') -and
    (Test-Text $commonArg 'params\.tensor_split\[0\] = 9\.0f') -and
    (Test-Text $commonArg 'params\.tensor_split\[1\] = 6\.0f') -and
    (Test-Text $commonArg 'native MTP not auto-enabled for non-MTP model, reasoning=%s') -and
    (Test-Text $commonArg 'LMSTUDIO_QWEN_MTP_KEEP_REASONING')

$results += Add-Result `
    -Name 'LM Studio Qwen q8/kv-unified path repairs missing tensor split and reasoning default' `
    -Pass $hasQwenLmStudioRepair `
    -Detail 'common/arg.cpp'

$hasDedicatedGemmaEngine =
    (Test-Path -LiteralPath (Join-Path $RepoRoot 'common\mtp.cpp')) -and
    (Test-Path -LiteralPath (Join-Path $RepoRoot 'common\mtp.h')) -and
    (Test-Text $commonSpec 'common_mtp_decode') -and
    (Test-Text (Join-Path $RepoRoot 'src\models\gemma4.cpp') 't_h_pre_norm') -and
    (Test-Text $llamaContext 'process_ubatch_mtp') -and
    (Test-Text $llamaContext 'graph_compute_mtp')

$results += Add-Result `
    -Name 'gemma4 dedicated attached-mtp execution engine is ported' `
    -Pass $hasDedicatedGemmaEngine `
    -Detail 'common/mtp.*, common/speculative.cpp, src/llama-context.cpp'

$hasGemmaBestDefaults =
    (Test-Text $commonArg 'LMSTUDIO_GEMMA4_MTP_AUTO_B9294') -and
    (Test-Text $commonArg 'LLAMA_GEMMA4_MTP_DEPTH_YIELD_CONTROLLER') -and
    (Test-Text $commonArg 'LLAMA_GEMMA4_MTP_LONGCTX_GRAPH_MARGIN_MIN", "0\.10"') -and
    (Test-Text $commonArg 'LLAMA_GEMMA4_MTP_SHORTCTX_DRAFT_THRESHOLD", "16384"') -and
    (Test-Text $commonArg 'LLAMA_GEMMA4_MTP_SHORTCTX_DRAFT_N_MAX') -and
    (Test-Text $commonArg 'LLAMA_GEMMA4_MTP_LONGCTX_DRAFT_N_MAX') -and
    (Test-Text $commonArg 'nextn\.pre_projection') -and
    (Test-Text $commonArg 'token_embd\.weight') -and
    (Test-Text $commonArg 'params\.speculative\.draft\.cpuparams\.poll = 0')

$results += Add-Result `
    -Name 'gemma4 b9294 best default bundle is preserved for explicit/auto MTP' `
    -Pass $hasGemmaBestDefaults `
    -Detail 'common/arg.cpp'

$hasGemmaDepthYield =
    (Test-Text $serverContext 'apply_depth_yield_longctx_draft_cap') -and
    (Test-Text $serverContext 'LLAMA_GEMMA4_MTP_DEPTH_YIELD_CONTROLLER') -and
    (Test-Text $serverContext 'LLAMA_GEMMA4_MTP_SHORTCTX_DRAFT_THRESHOLD') -and
    (Test-Text $serverContext 'LLAMA_GEMMA4_MTP_DEPTH_YIELD_MIN_SAMPLES') -and
    (Test-Text $serverContext 'record_draft_acceptance') -and
    (Test-Text $serverContext 'DRAFT_DEPTH_WINDOW_MAX') -and
    (Test-Text $serverContext 'slot\.record_draft_acceptance')

$results += Add-Result `
    -Name 'gemma4 true32k depth-yield controller is ported' `
    -Pass $hasGemmaDepthYield `
    -Detail 'tools/server/server-context.cpp'

$hasAttachedServerPath =
    (Test-Text $serverContext 'spec_mtp_attached') -and
    (Test-Text $serverContext 'common_mtp_assistant_is_attached') -and
    (Test-Text $serverContext 'ctx_dft = nullptr') -and
    (Test-Text $serverContext 'spec_mtp_target_context') -and
    (Test-Text $serverContext 'skipping fit pre-reservation for external attached MTP assistant')

$results += Add-Result `
    -Name 'server attached-MTP path avoids separate draft/MTP context for Gemma4 assistant' `
    -Pass $hasAttachedServerPath `
    -Detail 'tools/server/server-context.cpp'

$results | Format-Table -AutoSize

$failed = @($results | Where-Object { -not $_.pass })
if ($RequirePortedGemmaEngine) {
    if ($failed.Count -gt 0) {
        throw "MTP rebase contract failed: $($failed.name -join '; ')"
    }
} else {
    $pendingPortPatterns = @(
        'gemma4 assistant arch*',
        'qwen tensor/internal q8*',
        'gemma4 dedicated*',
        'gemma4 b9294 best default*',
        'gemma4 true32k depth-yield*',
        'server attached-MTP*'
    )
    $unexpectedFailed = @($failed | Where-Object {
            $name = $_.name
            -not ($pendingPortPatterns | Where-Object { $name -like $_ })
        })
    if ($unexpectedFailed.Count -gt 0) {
        throw "Unexpected baseline contract failure: $($unexpectedFailed.name -join '; ')"
    }
    if ($failed.Count -gt 0) {
        Write-Warning "Expected missing port(s): $($failed.name -join '; ')"
    }
}
