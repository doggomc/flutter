$ErrorActionPreference = 'Stop'

$projectRoot = (Get-Location).Path
$strayMain = Join-Path $projectRoot 'main.dart'
if (Test-Path $strayMain) {
  $strayText = Get-Content $strayMain -Raw
  $isWorkflowYaml = ($strayText -match '(?m)^name:\s*Build FreeF1 Cockpit \(Windows\)\s*$') -and ($strayText -match '(?m)^on:\s*$')
  if ($isWorkflowYaml) {
    Remove-Item $strayMain -Force
    Write-Host 'Removed stray root main.dart containing GitHub Actions YAML.'
  }
}

$appEntry = Join-Path $projectRoot 'lib\main.dart'
if (-not (Test-Path $appEntry)) {
  throw 'Missing lib/main.dart. Restore the Dart app entrypoint from the FreeF1 source ZIP.'
}
$entryText = Get-Content $appEntry -Raw
if ($entryText -notmatch '(?m)^void\s+main\s*\(') {
  throw 'lib/main.dart is not the FreeF1 Dart entrypoint. Put the workflow YAML in .github/workflows/build-windows.yml and restore lib/main.dart from the source ZIP.'
}

Write-Host 'Project layout is ready: lib/main.dart is Dart source and the workflow stays under .github/workflows/.'
