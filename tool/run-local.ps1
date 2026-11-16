$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path -Parent $PSScriptRoot
Push-Location $projectDirectory
try {
  if (-not (Test-Path -LiteralPath 'config/dart_defines.local.json')) { throw 'Configurazione locale mancante: config/dart_defines.local.json' }
  & flutter build web --no-pub --dart-define-from-file=config/dart_defines.local.json
  if ($LASTEXITCODE -ne 0) { throw 'Compilazione Flutter non riuscita.' }
  & node tool/serve-local.mjs build/web 7358
} finally { Pop-Location }
