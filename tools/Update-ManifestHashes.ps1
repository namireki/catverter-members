[CmdletBinding()]
param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot),
    [switch]$Check
)

$ErrorActionPreference = 'Stop'
$Root = [IO.Path]::GetFullPath($Root)
$utf8Strict = [Text.UTF8Encoding]::new($false, $true)
$utf8NoBom = [Text.UTF8Encoding]::new($false)

function Get-NormalizedJsonBytes {
    param([string]$Text)

    $normalized = $Text -replace "`r`n", "`n" -replace "`r", "`n"
    return [Text.Encoding]::UTF8.GetBytes($normalized)
}

function Get-Sha256Hex {
    param([byte[]]$Bytes)

    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha256.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha256.Dispose()
    }
}

function Visit-JsonElement {
    param([System.Text.Json.JsonElement]$Element, [string]$Owner)

    if ($Element.ValueKind -eq [System.Text.Json.JsonValueKind]::Object) {
        $keys = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($property in $Element.EnumerateObject()) {
            if (-not $keys.Add($property.Name)) {
                throw "${Owner}: duplicate JSON property '$($property.Name)'"
            }
            Visit-JsonElement $property.Value "${Owner}.$($property.Name)"
        }
    }
    elseif ($Element.ValueKind -eq [System.Text.Json.JsonValueKind]::Array) {
        $index = 0
        foreach ($item in $Element.EnumerateArray()) {
            Visit-JsonElement $item "${Owner}[$index]"
            $index++
        }
    }
}

function Read-JsonText {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "${Path}: file is missing"
    }
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 3 -and
        $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        throw "${Path}: UTF-8 BOM is not allowed"
    }
    try {
        $text = $utf8Strict.GetString($bytes)
    }
    catch {
        throw "${Path}: invalid UTF-8 ($($_.Exception.Message))"
    }
    try {
        $document = [System.Text.Json.JsonDocument]::Parse(
            $text,
            [System.Text.Json.JsonDocumentOptions]::new())
        try {
            Visit-JsonElement $document.RootElement $Path
        }
        finally {
            $document.Dispose()
        }
    }
    catch {
        throw "${Path}: invalid JSON ($($_.Exception.Message))"
    }
    return $text
}

function Read-JsonValue {
    param([string]$Path)

    $text = Read-JsonText $Path
    try {
        return ConvertFrom-Json -InputObject $text -AsHashtable -DateKind String
    }
    catch {
        throw "${Path}: invalid JSON ($($_.Exception.Message))"
    }
}

function Assert-Keys {
    param(
        [string]$Owner,
        [object]$Value,
        [string[]]$Keys
    )

    if ($Value -isnot [System.Collections.IDictionary]) {
        throw "${Owner}: must be an object"
    }
    foreach ($key in $Keys) {
        if (-not $Value.Contains($key)) {
            throw "${Owner}: missing required property '$key'"
        }
    }
    foreach ($key in $Value.Keys) {
        if ($key -notin $Keys) {
            throw "${Owner}: unknown property '$key'"
        }
    }
}

try {
    $manifestPath = Join-Path $Root 'members-manifest.json'
    $manifestText = Read-JsonText $manifestPath
    $manifest = ConvertFrom-Json -InputObject $manifestText -AsHashtable
    Assert-Keys 'members-manifest.json' $manifest @(
        '$schema', 'documentType', 'schemaVersion', 'version', 'updatedAt',
        'repository', 'revisionPolicy',
        'jsonNormalization', 'hashAlgorithm', 'catalogSchema', 'catalogs', 'migration'
    )

    $catalogSchema = $manifest['catalogSchema']
    Assert-Keys 'members-manifest.json.catalogSchema' $catalogSchema @(
        'path', 'sha256', 'mediaType'
    )
    if ([string]$catalogSchema['path'] -cne 'schemas/catverter-members-catalog-v1.schema.json') {
        throw 'members-manifest.json.catalogSchema.path: unexpected catalog schema path'
    }
    if ([string]$manifest['jsonNormalization'] -cne 'utf8-lf') {
        throw 'members-manifest.json.jsonNormalization: must be utf8-lf'
    }
    if ([string]$manifest['hashAlgorithm'] -cne 'sha256') {
        throw 'members-manifest.json.hashAlgorithm: must be sha256'
    }
    if ($manifest['catalogs'] -isnot [array] -or @($manifest['catalogs']).Count -ne 2) {
        throw 'members-manifest.json.catalogs: exactly two catalog pointers are required'
    }

    $hashes = [ordered]@{}
    $schemaPath = Join-Path $Root ($catalogSchema['path'] -replace '/', [IO.Path]::DirectorySeparatorChar)
    $schemaText = Read-JsonText $schemaPath
    $hashes['catalogSchema'] = Get-Sha256Hex (Get-NormalizedJsonBytes $schemaText)

    foreach ($pointer in @($manifest['catalogs'])) {
        Assert-Keys 'members-manifest.json.catalogs[]' $pointer @(
            'id', 'classification', 'trust', 'path', 'sha256', 'mediaType'
        )
        $path = [string]$pointer['path']
        if ($path -notin @('catalogs/standard-committee.json', 'catalogs/patreon-members.json')) {
            throw "members-manifest.json.catalogs[].path: unsupported catalog path '$path'"
        }
        $catalogPath = Join-Path $Root ($path -replace '/', [IO.Path]::DirectorySeparatorChar)
        $catalogText = Read-JsonText $catalogPath
        $hashes[$path] = Get-Sha256Hex (Get-NormalizedJsonBytes $catalogText)
    }

    $stale = ([string]$catalogSchema['sha256'] -cne $hashes['catalogSchema'])
    foreach ($pointer in @($manifest['catalogs'])) {
        if ([string]$pointer['sha256'] -cne $hashes[[string]$pointer['path']]) {
            $stale = $true
        }
    }

    if ($Check) {
        if ($stale) {
            Write-Error 'Manifest schema and catalog hashes are stale.'
            exit 1
        }
        Write-Host 'Manifest schema and catalog hashes are current.'
        exit 0
    }

    $catalogSchema['sha256'] = $hashes['catalogSchema']
    foreach ($pointer in @($manifest['catalogs'])) {
        $pointer['sha256'] = $hashes[[string]$pointer['path']]
    }
    $updated = $manifest | ConvertTo-Json -Depth 30
    $updated = $updated -replace "`r`n", "`n" -replace "`r", "`n"
    [IO.File]::WriteAllText($manifestPath, $updated + "`n", $utf8NoBom)
    Write-Host 'Updated catalog schema and catalog hashes in members-manifest.json.'
    exit 0
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
