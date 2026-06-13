param(
    [string] $OutDir = "C:\Users\berje\src\llama.cpp-b9596-gemma4-qwen-mtp-runtime\artifacts\lmstudio-b9596-gemma-qat-assistant-q4-q8-curl-compare-001",
    [int] $Context = 65536,
    [int] $ShortMaxTokens = 192,
    [int] $LongMaxTokens = 128,
    [int] $LongRepeats = 900,
    [ValidateSet("both", "qat-q4", "qat-q8")]
    [string] $OnlyChoice = "both"
)

$ErrorActionPreference = "Stop"

function Read-JsonFile($Path) {
    Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Write-JsonFile($Path, $Value) {
    $Value | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Write-ProgressMarker($Message) {
    $line = "{0} {1}" -f (Get-Date).ToString("o"), $Message
    $line | Tee-Object -FilePath (Join-Path $OutDir "progress.log") -Append
}

function Get-ServerLogPath {
    Get-ChildItem -LiteralPath "C:\Users\berje\.lmstudio\server-logs" -Recurse -File -Filter "*.log" |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1 -ExpandProperty FullName
}

function Get-LineCount($Path) {
    if (!(Test-Path -LiteralPath $Path)) {
        return 0
    }
    return @(Get-Content -LiteralPath $Path).Count
}

function Get-NewLogLines($Path, $BeforeLineCount) {
    $lines = @(Get-Content -LiteralPath $Path)
    if ($BeforeLineCount -ge $lines.Count) {
        return @()
    }
    return @($lines | Select-Object -Skip $BeforeLineCount)
}

function Set-GemmaAssistant($Choice) {
    $hardwarePath = "C:\Users\berje\.lmstudio\.internal\hardware-config.json"
    $hardware = Read-JsonFile $hardwarePath
    $entry = @($hardware.json | Where-Object { $_[0] -eq "llama.cpp-win-x86_64-nvidia-cuda-avx2" } | Select-Object -First 1)
    if ($entry.Count -eq 0) {
        throw "llama.cpp-win-x86_64-nvidia-cuda-avx2 hardware config entry not found"
    }

    $fields = @($entry[0][1].fields)
    $splitField = @($fields | Where-Object { $_.key -eq "load.gpuSplitConfig" } | Select-Object -First 1)
    if ($splitField.Count -eq 0) {
        throw "load.gpuSplitConfig field not found"
    }

    $splitField[0].value.strategy = "custom"
    $splitField[0].value.customRatio = @(9, 6)
    $splitField[0].value.gemma4MtpAssistant = $Choice
    Write-JsonFile $hardwarePath $hardware
}

function Remove-EngineProtocolDraftModelField {
    $configPath = "C:\Users\berje\.lmstudio\.internal\user-concrete-model-default-config\google\gemma-4-31b-qat.json"
    if (!(Test-Path -LiteralPath $configPath)) {
        return
    }

    $config = Read-JsonFile $configPath
    if ($null -eq $config.operation -or $null -eq $config.operation.fields) {
        return
    }

    $config.operation.fields = @($config.operation.fields | Where-Object {
        $_.key -ne "llm.prediction.speculativeDecoding.draftModel"
    })
    Write-JsonFile $configPath $config
}

function Assert-RequiredFiles {
    $required = @(
        "C:\Users\berje\.lmstudio\models\lmstudio-community\gemma-4-31B-it-QAT-GGUF\gemma-4-31B-it-QAT-Q4_0.gguf",
        "C:\Users\berje\.lmstudio\models\google\gemma-4-31B-it-QAT-assistant-GGUF\gemma-4-31B-it-QAT-assistant-Q4_0.gguf",
        "C:\Users\berje\.lmstudio\models\Janvitos\gemma-4-31B-it-qat-assistant-MTP-Q8_0-GGUF\gemma-4-31B-it-qat-assistant-MTP-Q8_0.gguf"
    )

    foreach ($path in $required) {
        if (!(Test-Path -LiteralPath $path)) {
            throw "required QAT model file missing: $path"
        }
    }
}

function Parse-RunLog($Lines) {
    $text = ($Lines -join "`n")
    $result = [ordered]@{}

    $autoLine = @($Lines | Where-Object { $_ -match "LMSTUDIO_GEMMA4_MTP_AUTO_B9596" } | Select-Object -Last 1)
    $result.auto_line = if ($autoLine.Count -gt 0) { $autoLine[0] } else { $null }
    $result.draft_mtp_attached = [bool]($text -match "adding speculative implementation 'draft-mtp'")
    $result.engine_gap = [bool]($text -match "speculativeDecoding capability gap|native draft-model speculative decoding")

    $timing = @($Lines | Where-Object { $_ -match "eval time\s*=\s*([0-9.]+) ms /\s*([0-9]+) tokens .*?([0-9.]+) tokens per second" } | Select-Object -Last 1)
    if ($timing.Count -gt 0 -and $timing[0] -match "eval time\s*=\s*([0-9.]+) ms /\s*([0-9]+) tokens .*?([0-9.]+) tokens per second") {
        $result.eval_ms = [double]$matches[1]
        $result.eval_tokens = [int]$matches[2]
        $result.eval_tok_s = [double]$matches[3]
    }

    $promptTiming = @($Lines | Where-Object { $_ -match "prompt eval time\s*=\s*([0-9.]+) ms /\s*([0-9]+) tokens .*?([0-9.]+) tokens per second" } | Select-Object -Last 1)
    if ($promptTiming.Count -gt 0 -and $promptTiming[0] -match "prompt eval time\s*=\s*([0-9.]+) ms /\s*([0-9]+) tokens .*?([0-9.]+) tokens per second") {
        $result.prompt_eval_ms = [double]$matches[1]
        $result.prompt_tokens = [int]$matches[2]
        $result.prompt_tok_s = [double]$matches[3]
    }

    $acceptance = @($Lines | Where-Object { $_ -match "draft acceptance =\s*([0-9.]+) \(\s*([0-9]+) accepted /\s*([0-9]+) generated\)" } | Select-Object -Last 1)
    if ($acceptance.Count -gt 0 -and $acceptance[0] -match "draft acceptance =\s*([0-9.]+) \(\s*([0-9]+) accepted /\s*([0-9]+) generated\)") {
        $result.acceptance = [double]$matches[1]
        $result.accepted_tokens = [int]$matches[2]
        $result.generated_tokens = [int]$matches[3]
    }

    return $result
}

function New-LongPrompt {
    $passkey = "QAT-MTP-PASSKEY-742193"
    $unit = "This is stable benchmark filler for Gemma QAT assistant comparison. It contains ordinary English prose, Korean fragments, numbers 12345, and repeated structure for cache and attention pressure. "
    $builder = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt $LongRepeats; $i++) {
        [void] $builder.Append("[$i] ")
        [void] $builder.Append($unit)
        if ($i -eq [Math]::Floor($LongRepeats / 2)) {
            [void] $builder.Append("IMPORTANT PASSKEY: $passkey. ")
        }
    }
    [void] $builder.Append("Question: Reply with the exact passkey, then add one short sentence saying which assistant is being evaluated. Respond as plain text only.")
    return @{ prompt = $builder.ToString(); passkey = $passkey }
}

function Invoke-ChatCurl($Identifier, $Prompt, $MaxTokens, $Prefix, $TimeoutSec) {
    $requestPath = Join-Path $OutDir "$Prefix.request.json"
    $responsePath = Join-Path $OutDir "$Prefix.response.json"
    $curlMetaPath = Join-Path $OutDir "$Prefix.curl.txt"

    $body = @{
        model = $Identifier
        messages = @(@{ role = "user"; content = $Prompt })
        max_tokens = $MaxTokens
        temperature = 0
        top_p = 1
    } | ConvertTo-Json -Depth 12
    Set-Content -LiteralPath $requestPath -Value $body -Encoding UTF8

    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $curlOutput = & curl.exe --silent --show-error --max-time $TimeoutSec --output $responsePath --write-out "http_code=%{http_code}`ntime_total=%{time_total}`n" -H "Content-Type: application/json" --data-binary "@$requestPath" "http://127.0.0.1:1234/v1/chat/completions" 2>&1
    $exitCode = $LASTEXITCODE
    $watch.Stop()
    $curlOutput | Set-Content -LiteralPath $curlMetaPath -Encoding UTF8

    $responseText = if (Test-Path -LiteralPath $responsePath) { Get-Content -LiteralPath $responsePath -Raw } else { "" }
    $content = ""
    $totalDraft = $null
    $acceptedDraft = $null
    try {
        $responseJson = $responseText | ConvertFrom-Json
        if ($null -ne $responseJson.choices -and $responseJson.choices.Count -gt 0 -and $null -ne $responseJson.choices[0].message.content) {
            $content = [string] $responseJson.choices[0].message.content
        }
        if ($null -ne $responseJson.stats) {
            $totalDraft = $responseJson.stats.total_draft_tokens_count
            $acceptedDraft = $responseJson.stats.accepted_draft_tokens_count
        }
    } catch {
    }

    return [ordered]@{
        exit_code = $exitCode
        wall_s = [math]::Round($watch.Elapsed.TotalSeconds, 3)
        curl_meta = ($curlOutput -join "`n")
        response_path = $responsePath
        total_draft_tokens = $totalDraft
        accepted_draft_tokens = $acceptedDraft
        api_acceptance = if ($totalDraft -gt 0) { [math]::Round($acceptedDraft / $totalDraft, 6) } else { $null }
        content_prefix = if ($content.Length -gt 0) { $content.Substring(0, [Math]::Min(240, $content.Length)) } else { "" }
    }
}

function Run-OneAssistant($Choice, $Label) {
    $identifier = "gemma-qat-$Choice-compare"
    Write-ProgressMarker "BEGIN $Choice"
    Set-GemmaAssistant $Choice
    Remove-EngineProtocolDraftModelField

    Write-ProgressMarker "UNLOAD_PREFLIGHT $Choice"
    lms unload -a | Out-Null
    Start-Sleep -Seconds 2
    $loaded = lms ps --json | ConvertFrom-Json
    if (@($loaded).Count -ne 0) {
        throw "preflight failed: lms ps is not empty before $Choice"
    }

    $logBeforeLoad = Get-ServerLogPath
    $lineBeforeLoad = Get-LineCount $logBeforeLoad
    Write-ProgressMarker "LOAD $Choice context=$Context"
    lms load google/gemma-4-31b-qat -c $Context --parallel 1 --gpu max --identifier $identifier -y | Out-Null
    Start-Sleep -Seconds 2

    $logAfterLoad = Get-ServerLogPath
    $loadLines = Get-NewLogLines $logAfterLoad $(if ($logAfterLoad -eq $logBeforeLoad) { $lineBeforeLoad } else { 0 })
    $loadParsed = Parse-RunLog $loadLines

    $shortPrompt = "Generate exactly 90 comma-separated integers starting at 1000. No explanation."
    $lineBeforeShort = Get-LineCount $logAfterLoad
    Write-ProgressMarker "SHORT $Choice max=$ShortMaxTokens"
    $shortCurl = Invoke-ChatCurl $identifier $shortPrompt $ShortMaxTokens "$Choice-short" 180
    Start-Sleep -Seconds 1
    $shortLines = Get-NewLogLines $logAfterLoad $lineBeforeShort
    $shortParsed = Parse-RunLog $shortLines

    $long = New-LongPrompt
    $lineBeforeLong = Get-LineCount $logAfterLoad
    Write-ProgressMarker "LONG $Choice repeats=$LongRepeats max=$LongMaxTokens"
    $longCurl = Invoke-ChatCurl $identifier $long.prompt $LongMaxTokens "$Choice-long" 300
    Start-Sleep -Seconds 1
    $longLines = Get-NewLogLines $logAfterLoad $lineBeforeLong
    $longParsed = Parse-RunLog $longLines

    $result = [ordered]@{
        label = $Label
        choice = $Choice
        identifier = $identifier
        load = $loadParsed
        short = [ordered]@{
            curl = $shortCurl
            metrics = $shortParsed
        }
        long = [ordered]@{
            curl = $longCurl
            passkey = $long.passkey
            passkey_found = [bool]($longCurl.content_prefix -match [regex]::Escape($long.passkey))
            metrics = $longParsed
        }
    }

    $partialPath = Join-Path $OutDir ("result-$Choice.json")
    $result | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $partialPath -Encoding UTF8

    Write-ProgressMarker "UNLOAD_AFTER $Choice"
    lms unload -a | Out-Null
    Start-Sleep -Seconds 2
    Write-ProgressMarker "END $Choice"
    return $result
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$backupDir = Join-Path $OutDir "backups"
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

$pathsToBackup = @(
    "C:\Users\berje\.lmstudio\.internal\hardware-config.json",
    "C:\Users\berje\.lmstudio\.internal\user-concrete-model-default-config\google\gemma-4-31b-qat.json"
)
foreach ($path in $pathsToBackup) {
    if (Test-Path -LiteralPath $path) {
        Copy-Item -LiteralPath $path -Destination (Join-Path $backupDir ((Split-Path $path -Leaf) + ".before")) -Force
    }
}

Assert-RequiredFiles
Remove-EngineProtocolDraftModelField

$results = New-Object System.Collections.Generic.List[object]
if ($OnlyChoice -eq "both" -or $OnlyChoice -eq "qat-q4") {
    $results.Add([pscustomobject](Run-OneAssistant "qat-q4" "Google QAT assistant Q4_0"))
}
if ($OnlyChoice -eq "both" -or $OnlyChoice -eq "qat-q8") {
    $results.Add([pscustomobject](Run-OneAssistant "qat-q8" "Janvitos QAT assistant Q8_0"))
}

$valid = @($results | Where-Object {
    $_.load.draft_mtp_attached -and
    -not $_.load.engine_gap -and
    $_.short.metrics.eval_tok_s -gt 0 -and
    $_.long.metrics.eval_tok_s -gt 0
})

if ($valid.Count -eq 0) {
    $bestChoice = $null
    $verdict = "no-pass"
} else {
    $ranked = @($valid | Sort-Object `
        @{ Expression = { $_.long.metrics.eval_tok_s }; Descending = $true },
        @{ Expression = { $_.short.metrics.eval_tok_s }; Descending = $true },
        @{ Expression = { $_.long.metrics.acceptance }; Descending = $true })
    $bestChoice = $ranked[0].choice
    $verdict = "best=$bestChoice"
    Set-GemmaAssistant $bestChoice
    Remove-EngineProtocolDraftModelField
}

$summary = [ordered]@{
    timestamp = (Get-Date).ToString("o")
    context = $Context
    long_repeats = $LongRepeats
    target = "google/gemma-4-31b-qat -> runtime remap to lmstudio-community/gemma-4-31B-it-QAT-GGUF/gemma-4-31B-it-QAT-Q4_0.gguf"
    compared = if ($OnlyChoice -eq "both") { @("qat-q4", "qat-q8") } else { @($OnlyChoice) }
    verdict = $verdict
    selected_assistant = $bestChoice
    results = $results
    backups = $backupDir
}

$summaryPath = Join-Path $OutDir "summary.json"
$summary | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
Get-Content -LiteralPath $summaryPath -Raw
