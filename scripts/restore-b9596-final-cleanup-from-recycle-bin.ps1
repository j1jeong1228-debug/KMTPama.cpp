param(
    [string] $Manifest = "C:\Users\berje\src\llama.cpp-b9596-gemma4-qwen-mtp-runtime\artifacts\_trash\b9596-final-cleanup-20260613-150433\CLEANUP-MANIFEST.json",
    [string] $Source = "",
    [switch] $PayloadOnly
)

$ErrorActionPreference = "Stop"

function Get-RecycleDeletedFrom {
    param($Item)

    try {
        return [string] $Item.ExtendedProperty("System.Recycle.DeletedFrom")
    } catch {
        return ""
    }
}

function Restore-RecycleItemToPath {
    param([string] $OriginalPath)

    if (Test-Path -LiteralPath $OriginalPath) {
        return "already-present"
    }

    $leaf = Split-Path -Leaf $OriginalPath
    $parent = Split-Path -Parent $OriginalPath
    $shell = New-Object -ComObject Shell.Application
    $bin = $shell.Namespace(10)
    if ($null -eq $bin) {
        throw "Recycle Bin shell namespace is unavailable."
    }

    $matches = @($bin.Items()) | Where-Object {
        $_.Name -eq $leaf -and (Get-RecycleDeletedFrom $_) -ieq $parent
    }
    if ($matches.Count -eq 0) {
        throw "Recycle Bin item not found: name='$leaf', deletedFrom='$parent'"
    }
    if ($matches.Count -gt 1) {
        throw "Ambiguous Recycle Bin item: name='$leaf', deletedFrom='$parent', count=$($matches.Count)"
    }

    $item = $matches[0]
    $verb = $item.Verbs() | Where-Object {
        $_.Name.Replace("&", "") -match "^Restore$"
    } | Select-Object -First 1
    if ($null -eq $verb) {
        throw "Restore verb not found for Recycle Bin item: $OriginalPath"
    }

    $verb.DoIt()
    for ($i = 0; $i -lt 60; $i++) {
        Start-Sleep -Milliseconds 500
        if (Test-Path -LiteralPath $OriginalPath) {
            return "restored"
        }
    }

    throw "Recycle Bin restore did not materialize path: $OriginalPath"
}

function Restore-MovedEntry {
    param($Entry)

    if (Test-Path -LiteralPath $Entry.source) {
        return [pscustomobject]@{
            category = $Entry.category
            source = $Entry.source
            destination = $Entry.destination
            status = "source-already-present"
        }
    }

    if (-not (Test-Path -LiteralPath $Entry.destination)) {
        foreach ($root in @($script:ManifestObject.recycleBin.payloadRoots)) {
            if ($Entry.destination.StartsWith($root.path, [System.StringComparison]::OrdinalIgnoreCase)) {
                Restore-RecycleItemToPath $root.path | Out-Null
                break
            }
        }
    }

    if (-not (Test-Path -LiteralPath $Entry.destination)) {
        throw "Restored payload is still missing entry destination: $($Entry.destination)"
    }

    $sourceParent = Split-Path -Parent $Entry.source
    New-Item -ItemType Directory -Force -Path $sourceParent | Out-Null
    Move-Item -LiteralPath $Entry.destination -Destination $Entry.source

    return [pscustomobject]@{
        category = $Entry.category
        source = $Entry.source
        destination = $Entry.destination
        status = "restored-to-source"
    }
}

$script:ManifestObject = Get-Content -LiteralPath $Manifest -Raw | ConvertFrom-Json

$entries = @($script:ManifestObject.moved)
if (-not [string]::IsNullOrWhiteSpace($Source)) {
    $entries = @($entries | Where-Object { $_.source -ieq $Source })
    if ($entries.Count -eq 0) {
        throw "No manifest entry matches source: $Source"
    }
}

$neededRoots = @($script:ManifestObject.recycleBin.payloadRoots)
if (-not $PayloadOnly -and -not [string]::IsNullOrWhiteSpace($Source)) {
    $neededRoots = @($neededRoots | Where-Object {
        $rootPath = $_.path
        @($entries | Where-Object {
            $_.destination.StartsWith($rootPath, [System.StringComparison]::OrdinalIgnoreCase)
        }).Count -gt 0
    })
}

$payloadResults = foreach ($root in $neededRoots) {
    if ($root.PSObject.Properties.Name -contains "recycleBinMatches" -and $root.recycleBinMatches -eq 0) {
        $message = "Payload root is not available in Windows Recycle Bin: $($root.path). $($root.note)"
        if ($PayloadOnly) {
            [pscustomobject]@{
                path = $root.path
                status = "not-available-in-recycle-bin"
                message = $message
            }
            continue
        }
        throw $message
    }

    [pscustomobject]@{
        path = $root.path
        status = (Restore-RecycleItemToPath $root.path)
    }
}

if ($PayloadOnly) {
    $payloadResults | ConvertTo-Json -Depth 4
    exit 0
}

$entryResults = foreach ($entry in $entries) {
    Restore-MovedEntry $entry
}

[pscustomobject]@{
    manifest = $Manifest
    payloadResults = $payloadResults
    entryResults = $entryResults
} | ConvertTo-Json -Depth 8
