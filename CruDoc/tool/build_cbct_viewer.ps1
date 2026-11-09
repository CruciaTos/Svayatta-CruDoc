# Builds the CBCT 3D viewer (cbct_viewer/, Vite + Cornerstone3D) into
# assets/cbct_viewer/, which Flutter bundles. The output is committed so the
# app builds on a machine without Node; run this only after changing
# cbct_viewer/. See cbct_viewer/README.md.
#
#   powershell -File tool\build_cbct_viewer.ps1

$ErrorActionPreference = 'Stop'

$root   = Split-Path -Parent $PSScriptRoot
$viewer = Join-Path $root 'cbct_viewer'
$out    = Join-Path $root 'assets\cbct_viewer'

Push-Location $viewer
try {
    npm ci
    if ($LASTEXITCODE -ne 0) { throw "npm ci failed (exit $LASTEXITCODE)" }
    npm run build
    if ($LASTEXITCODE -ne 0) { throw "npm run build failed (exit $LASTEXITCODE)" }
}
finally {
    Pop-Location
}

Write-Host ''
Write-Host "Built into $out :"
Get-ChildItem -Path $out -Recurse -File | ForEach-Object {
    '{0,12:N0}  {1}' -f $_.Length, $_.FullName.Substring($out.Length + 1).Replace('\', '/')
}
