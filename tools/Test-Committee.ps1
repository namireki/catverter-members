$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$documentPath = Join-Path $repositoryRoot 'committee.json'
$schemaPath = Join-Path $repositoryRoot 'schemas/catverter-committee-v1.schema.json'
$problems = [System.Collections.Generic.List[string]]::new()

function Add-Problem {
    param([string]$Message)
    $script:problems.Add($Message)
}

function Read-JsonObject {
    param([string]$Path)

    try {
        $value = Get-Content -LiteralPath $Path -Raw -Encoding utf8 |
            ConvertFrom-Json -AsHashtable
        if ($value -isnot [System.Collections.IDictionary]) {
            Add-Problem "$(Split-Path -Leaf $Path): root must be an object"
            return $null
        }
        return $value
    }
    catch {
        Add-Problem "$(Split-Path -Leaf $Path): $($_.Exception.Message)"
        return $null
    }
}

function Test-ExactKeys {
    param(
        [string]$Owner,
        [System.Collections.IDictionary]$Value,
        [string[]]$Expected
    )

    foreach ($required in $Expected) {
        if (-not $Value.Contains($required)) {
            Add-Problem "$Owner`: missing required property '$required'"
        }
    }
    foreach ($actual in $Value.Keys) {
        if ($actual -notin $Expected) {
            Add-Problem "$Owner`: unknown property '$actual'"
        }
    }
}

function Test-LocalizedText {
    param(
        [string]$Owner,
        [object]$Value
    )

    if ($Value -isnot [System.Collections.IDictionary] -or $Value.Count -eq 0) {
        Add-Problem "$Owner`: must be a non-empty object"
        return
    }
    if (-not $Value.Contains('en') -or [string]::IsNullOrWhiteSpace($Value['en'])) {
        Add-Problem "$Owner`: must contain a non-empty 'en' translation"
    }
    foreach ($language in $Value.Keys) {
        if ($language -notmatch '^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$') {
            Add-Problem "$Owner`: invalid language code '$language'"
        }
        if ([string]::IsNullOrWhiteSpace($Value[$language])) {
            Add-Problem "$Owner`: translation '$language' must not be blank"
        }
    }
}

$schema = Read-JsonObject $schemaPath
if ($null -ne $schema -and $schema['type'] -ne 'object') {
    Add-Problem 'catverter-committee-v1.schema.json: root type must be object'
}

$document = Read-JsonObject $documentPath
if ($null -ne $document) {
    $documentFields = @(
        '$schema', 'documentType', 'schemaVersion', 'version', 'updatedAt',
        'committee', 'members'
    )
    Test-ExactKeys 'committee document' $document $documentFields

    if ($document['$schema'] -ne 'schemas/catverter-committee-v1.schema.json') {
        Add-Problem 'committee document: unexpected $schema reference'
    }
    if ($document['documentType'] -ne 'catverter-committee') {
        Add-Problem "committee document: documentType must be 'catverter-committee'"
    }
    if ($document['schemaVersion'] -ne 1) {
        Add-Problem 'committee document: schemaVersion must be 1'
    }
    if ($document['version'] -notmatch '^[0-9]+(?:\.[0-9]+){1,3}$') {
        Add-Problem 'committee document: version must be a dotted version'
    }

    [DateTimeOffset]$updatedAt = [DateTimeOffset]::MinValue
    $updatedAtText = [string]$document['updatedAt']
    if (-not [DateTimeOffset]::TryParse(
            $updatedAtText,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::RoundtripKind,
            [ref]$updatedAt)) {
        Add-Problem 'committee document: updatedAt must be an ISO-8601 timestamp'
    }

    $committee = $document['committee']
    $committeeFields = @('title', 'description', 'statuteTitle', 'statute')
    if ($committee -isnot [System.Collections.IDictionary]) {
        Add-Problem 'committee: must be an object'
    }
    else {
        Test-ExactKeys 'committee' $committee $committeeFields
        foreach ($field in $committeeFields) {
            Test-LocalizedText "committee.$field" $committee[$field]
        }
    }

    $members = @($document['members'])
    if ($members.Count -eq 0) {
        Add-Problem 'members: must contain at least one member'
    }
    else {
        $seenIds = [System.Collections.Generic.HashSet[string]]::new(
            [StringComparer]::Ordinal)
        $memberFields = @(
            'id', 'name', 'role', 'biography', 'accentColor', 'imageUrl'
        )
        for ($index = 0; $index -lt $members.Count; $index++) {
            $member = $members[$index]
            $owner = "members[$index]"
            if ($member -isnot [System.Collections.IDictionary]) {
                Add-Problem "$owner`: must be an object"
                continue
            }

            Test-ExactKeys $owner $member $memberFields
            $memberId = [string]$member['id']
            if ($memberId -notmatch '^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$') {
                Add-Problem "$owner`: id must use canonical lowercase ID syntax"
            }
            elseif (-not $seenIds.Add($memberId)) {
                Add-Problem "$owner`: duplicate member id '$memberId'"
            }

            if ([string]::IsNullOrWhiteSpace($member['name'])) {
                Add-Problem "$owner`: name must not be blank"
            }
            Test-LocalizedText "$owner.role" $member['role']
            Test-LocalizedText "$owner.biography" $member['biography']
            if ($member['accentColor'] -notmatch '^#[0-9A-Fa-f]{6}$') {
                Add-Problem "$owner`: accentColor must use #RRGGBB notation"
            }

            $imageUrl = $member['imageUrl']
            if ($null -ne $imageUrl) {
                [Uri]$parsedUri = $null
                if (-not [Uri]::TryCreate(
                        [string]$imageUrl,
                        [UriKind]::Absolute,
                        [ref]$parsedUri) -or
                    $parsedUri.Scheme -ne [Uri]::UriSchemeHttps) {
                    Add-Problem "$owner`: imageUrl must be null or an absolute HTTPS URL"
                }
            }
        }
    }
}

if ($problems.Count -gt 0) {
    [Console]::Error.WriteLine(
        "Committee repository has $($problems.Count) problem(s):")
    foreach ($problem in $problems) {
        [Console]::Error.WriteLine("- $problem")
    }
    exit 1
}

Write-Host 'Catverter Committee repository is valid.'
exit 0
