<#
.SYNOPSIS
  Compila l'app in versione di produzione e la pubblica su Cloudflare Pages.

.DESCRIPTION
  1. controlla la configurazione di produzione (config/dart_defines.production.json);
  2. esegue i test dell'Organizzatore e dell'impaginazione (saltabili con -SkipTests);
  3. compila in build/web-production, senza toccare build/web usata dal sito locale;
  4. pubblica la cartella sul tuo progetto Cloudflare Pages (-ProjectName).

  Prima della prima pubblicazione eseguire in Supabase (SQL Editor) il file
  supabase/migrations/20261112_organizer.sql.

.EXAMPLE
  .\tool\deploy-cloudflare.ps1 -ProjectName mio-progetto
.EXAMPLE
  .\tool\deploy-cloudflare.ps1 -ProjectName mio-progetto -SkipTests
.EXAMPLE
  .\tool\deploy-cloudflare.ps1 -ProjectName mio-progetto -Preview      # pubblica su un indirizzo di prova, non su quello stabile
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProjectName,
    [switch]$Preview,
    [switch]$SkipTests,
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$defines = 'config/dart_defines.production.json'
$output = 'build/web-production'
$wrangler = Join-Path $project 'backend/personal_agent/node_modules/.bin/wrangler.cmd'
$localNode = Join-Path $project '.tools/node-v24.19.0-win-x64'

function Invoke-Step([string]$Title, [scriptblock]$Action) {
    Write-Host "`n== $Title" -ForegroundColor Cyan
    & $Action
    if ($LASTEXITCODE -ne 0) { throw "$Title non riuscito (codice $LASTEXITCODE)." }
}

Push-Location $project
try {
    if (-not (Test-Path -LiteralPath $defines)) {
        throw "Manca $defines. Copiare config/dart_defines.production.example.json e compilarlo."
    }
    if (-not (Test-Path -LiteralPath $wrangler)) {
        throw 'Wrangler non installato: eseguire "npm ci" in backend/personal_agent.'
    }
    # Wrangler ha bisogno di Node: se non è nel PATH si usa quello del progetto.
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
        if (-not (Test-Path -LiteralPath (Join-Path $localNode 'node.exe'))) { throw 'Node.js non trovato.' }
        $env:PATH = "$localNode;$env:PATH"
    }
    # Node si fida anche dei certificati installati in Windows.
    if (-not $env:NODE_USE_SYSTEM_CA) { $env:NODE_USE_SYSTEM_CA = '1' }

    if (-not $SkipTests) {
        Invoke-Step 'Test' {
            flutter test --no-pub test/features/organizer test/features/mobile_layout_test.dart
        }
    }
    if (-not $SkipBuild) {
        Invoke-Step 'Compilazione di produzione' {
            flutter build web --release --no-pub "--dart-define-from-file=$defines" -o $output
        }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $output 'index.html'))) {
        throw "Cartella $output assente: rieseguire senza -SkipBuild."
    }
    if (-not (Test-Path -LiteralPath (Join-Path $output 'organizzatore/index.html'))) {
        throw "L'Organizzatore non è nella compilazione ($output/organizzatore/index.html)."
    }

    Invoke-Step 'Accesso a Cloudflare' { & $wrangler whoami }

    $branch = if ($Preview) { 'anteprima' } else { 'main' }
    Invoke-Step "Pubblicazione su Cloudflare Pages ($branch)" {
        & $wrangler pages deploy $output --project-name $ProjectName --branch $branch --commit-dirty=true
    }

    if ($Preview) {
        Write-Host "`nPubblicata in anteprima: usare l'indirizzo mostrato qui sopra." -ForegroundColor Green
    } else {
        Write-Host "`nPubblicata: https://$ProjectName.pages.dev/" -ForegroundColor Green
    }
} finally {
    Pop-Location
}
