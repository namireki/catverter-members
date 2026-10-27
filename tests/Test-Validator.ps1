[CmdletBinding()]
param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$Root = [IO.Path]::GetFullPath($Root)
$validator = Join-Path $Root 'tools/Test-CatverterMembers.ps1'
$updater = Join-Path $Root 'tools/Update-ManifestHashes.ps1'
$workRoot = Join-Path $Root 'tests/.work'
$utf8NoBom = [Text.UTF8Encoding]::new($false)
$passed = 0

if (Test-Path -LiteralPath $workRoot) {
    Remove-Item -LiteralPath $workRoot -Recurse -Force
}
[void](New-Item -ItemType Directory -Path $workRoot -Force)

function Write-JsonFile {
    param(
        [string]$Path,
        [object]$Value
    )

    $json = $Value | ConvertTo-Json -Depth 30
    $json = $json -replace "`r`n", "`n" -replace "`r", "`n"
    [IO.File]::WriteAllText($Path, $json + "`n", $utf8NoBom)
}

function Read-JsonFile {
    param([string]$Path)
    return ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($Path)) -AsHashtable -DateKind String
}

function New-Fixture {
    $fixture = Join-Path $workRoot ([Guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $fixture)
    foreach ($item in Get-ChildItem -LiteralPath $Root -Force) {
        if ($item.Name -in @('.git', 'tests')) {
            continue
        }
        Copy-Item -LiteralPath $item.FullName -Destination $fixture -Recurse -Force
    }
    return $fixture
}

function Invoke-Validator {
    param([string]$Fixture)

    $output = @(& pwsh -NoProfile -File $validator -Root $Fixture 2>&1 | ForEach-Object { [string]$_ })
    [pscustomobject]@{
        Code = [int]$LASTEXITCODE
        Output = ($output -join "`n")
    }
}

function Sync-FixtureHashes {
    param([string]$Fixture)

    $output = @(& pwsh -NoProfile -File $updater -Root $Fixture 2>&1 | ForEach-Object { [string]$_ })
    if ([int]$LASTEXITCODE -ne 0) {
        throw "Fixture hash update failed:`n$($output -join "`n")"
    }
}

function Run-Case {
    param(
        [string]$Name,
        [scriptblock]$Mutation,
        [bool]$ExpectSuccess,
        [string]$ExpectedMessage,
        [bool]$UpdateHashes = $false
    )

    $fixture = New-Fixture
    try {
        if ($null -ne $Mutation) {
            & $Mutation $fixture
        }
        if ($UpdateHashes) {
            Sync-FixtureHashes $fixture
        }
        $result = Invoke-Validator $fixture
        $passedExpectation = if ($ExpectSuccess) {
            $result.Code -eq 0
        }
        else {
            $result.Code -ne 0 -and $result.Output -like "*$ExpectedMessage*"
        }
        if (-not $passedExpectation) {
            throw "$Name failed. Validator exit code $($result.Code). Output:`n$($result.Output)"
        }
        Write-Host "PASS $Name"
        $script:passed++
    }
    finally {
        if (Test-Path -LiteralPath $fixture) {
            Remove-Item -LiteralPath $fixture -Recurse -Force
        }
    }
}

try {
Run-Case 'baseline' $null $true '' $false

Run-Case 'future valid Patreon member' {
    param($fixture)
    $path = Join-Path $fixture 'catalogs/patreon-members.json'
    $catalog = Read-JsonFile $path
    $catalog['members'] = @([ordered]@{
        id = 'future-patron'
        classification = 'patreon-member'
        catName = 'Future Patron'
        committeePosition = [ordered]@{
            en = 'Guest Cat'
        }
        shortDescription = [ordered]@{
            en = 'A future consented contributor.'
        }
        consent = [ordered]@{
            publicDisplay = $true
            photoDisplay = $false
            consentDate = '2026-10-24'
        }
    })
    Write-JsonFile $path $catalog
} $true '' $true

Run-Case 'BOM' {
    param($fixture)
    $path = Join-Path $fixture 'members-manifest.json'
    $bytes = [IO.File]::ReadAllBytes($path)
    [IO.File]::WriteAllBytes($path, [byte[]]((0xEF, 0xBB, 0xBF) + $bytes))
} $false 'UTF-8 BOM' $false

Run-Case 'invalid UTF-8' {
    param($fixture)
    $path = Join-Path $fixture 'members-manifest.json'
    $bytes = [IO.File]::ReadAllBytes($path)
    [IO.File]::WriteAllBytes($path, [byte[]]($bytes + 0xFF))
} $false 'invalid UTF-8' $false

Run-Case 'CRLF' {
    param($fixture)
    $path = Join-Path $fixture 'members-manifest.json'
    $text = [IO.File]::ReadAllText($path)
    [IO.File]::WriteAllBytes(
        $path,
        [Text.Encoding]::UTF8.GetBytes($text.Replace("`n", "`r`n")))
} $false 'CRLF and lone CR' $false

Run-Case 'duplicate JSON key' {
    param($fixture)
    $path = Join-Path $fixture 'members-manifest.json'
    $text = [IO.File]::ReadAllText($path)
    $duplicate = '  "documentType": "catverter-members-manifest",'
    $text = $text.Replace(
        $duplicate,
        "$duplicate`n$duplicate")
    [IO.File]::WriteAllText($path, $text, $utf8NoBom)
} $false "duplicate JSON property 'documentType'" $false

Run-Case 'duplicate cross-catalog ID' {
    param($fixture)
    $standard = Read-JsonFile (Join-Path $fixture 'catalogs/standard-committee.json')
    $standardMember = $standard['members'][0]
    $patreon = Read-JsonFile (Join-Path $fixture 'catalogs/patreon-members.json')
    $patreon['members'] = @([ordered]@{
        id = $standardMember['id']
        classification = 'patreon-member'
        catName = $standardMember['catName']
        committeePosition = $standardMember['committeePosition']
        consent = [ordered]@{
            publicDisplay = $true
            photoDisplay = $false
            consentDate = '2026-10-24'
        }
    })
    Write-JsonFile (Join-Path $fixture 'catalogs/patreon-members.json') $patreon
} $false 'duplicate stable ID across catalogs' $true

Run-Case 'classification mismatch' {
    param($fixture)
    $path = Join-Path $fixture 'catalogs/standard-committee.json'
    $catalog = Read-JsonFile $path
    $catalog['members'][0]['classification'] = 'patreon-member'
    Write-JsonFile $path $catalog
} $false 'does not match catalog classification' $true

Run-Case 'traversal' {
    param($fixture)
    $path = Join-Path $fixture 'catalogs/standard-committee.json'
    $catalog = Read-JsonFile $path
    $catalog['members'][0]['photo'] = [ordered]@{
        path = 'assets/standard-committee/../patreon-members/pigro.png'
    }
    Write-JsonFile $path $catalog
} $false 'safe controlled relative asset path' $true

Run-Case 'cross-classification photo path' {
    param($fixture)
    $path = Join-Path $fixture 'catalogs/standard-committee.json'
    $catalog = Read-JsonFile $path
    $catalog['members'][0]['photo'] = [ordered]@{
        path = 'assets/patreon-members/pigro.png'
    }
    Write-JsonFile $path $catalog
} $false 'asset classification does not match' $true

Run-Case 'hash mismatch' {
    param($fixture)
    $assetDirectory = Join-Path $fixture 'assets/standard-committee'
    [void](New-Item -ItemType Directory -Path $assetDirectory -Force)
    $assetPath = Join-Path $assetDirectory 'pigro.png'
    $assetBytes = [byte[]](0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a)
    [IO.File]::WriteAllBytes($assetPath, $assetBytes)
    $catalogPath = Join-Path $fixture 'catalogs/standard-committee.json'
    $catalog = Read-JsonFile $catalogPath
    $catalog['members'][0]['photo'] = [ordered]@{
        path = 'assets/standard-committee/pigro.png'
        sha256 = ('0' * 64)
        byteLength = $assetBytes.Length
        mediaType = 'image/png'
        rights = [ordered]@{
            copyrightHolder = 'Namireki Studio'
            license = 'Apache-2.0'
            source = 'Namireki Studio'
        }
    }
    Write-JsonFile $catalogPath $catalog
} $false 'raw asset SHA-256' $true

Run-Case 'orphan asset' {
    param($fixture)
    $assetDirectory = Join-Path $fixture 'assets/standard-committee'
    [void](New-Item -ItemType Directory -Path $assetDirectory -Force)
    [IO.File]::WriteAllBytes(
        (Join-Path $assetDirectory 'orphan.png'),
        [byte[]](0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a))
} $false 'orphan asset is not referenced' $false
}
finally {
    if (Test-Path -LiteralPath $workRoot) {
        Remove-Item -LiteralPath $workRoot -Recurse -Force
    }
}
Write-Host "All $passed regression tests passed."
exit 0
