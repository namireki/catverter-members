$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$validator = Join-Path $PSScriptRoot 'validate.mjs'

& node $validator $repositoryRoot
exit $LASTEXITCODE
