<#
.SYNOPSIS
  Roda todas as verificações do monorepo: tokens, API, app Flutter e site.
.EXAMPLE
  .\scripts\test-all.ps1
  .\scripts\test-all.ps1 -Only api,web
#>
param(
    [ValidateSet('tokens', 'api', 'mobile', 'web')]
    [string[]]$Only = @('tokens', 'api', 'mobile', 'web')
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Failures = New-Object System.Collections.Generic.List[string]

function Invoke-Step([string]$Name, [string]$Dir, [scriptblock]$Commands) {
    Write-Host "`n=== $Name ===" -ForegroundColor Cyan
    Push-Location $Dir
    try {
        & $Commands
        if ($LASTEXITCODE -ne 0) { throw "código de saída $LASTEXITCODE" }
        Write-Host "OK: $Name" -ForegroundColor Green
    } catch {
        Write-Host "FALHOU: $Name ($_)" -ForegroundColor Red
        $Failures.Add($Name)
    } finally {
        Pop-Location
    }
}

# Para no primeiro comando que falhar dentro de um passo.
function Exec([scriptblock]$Command) {
    & $Command
    if ($LASTEXITCODE -ne 0) { throw "falhou: $Command" }
}

# DB_MODE do ambiente ou do .env: "docker" (padrão) sobe o db-test; "local" usa o PostgreSQL da máquina.
function Get-DbMode {
    if ($env:DB_MODE) { return $env:DB_MODE }
    $envFile = Join-Path $Root '.env'
    if (Test-Path $envFile) {
        $line = Get-Content $envFile | Where-Object { $_ -match '^\s*DB_MODE\s*=' } | Select-Object -Last 1
        if ($line) { return ($line -split '=', 2)[1].Trim() }
    }
    return 'docker'
}

if ($Only -contains 'tokens') {
    Invoke-Step 'Tokens de design atualizados' $Root { Exec { python scripts/generate_tokens.py --check } }
}

if ($Only -contains 'api') {
    Invoke-Step 'API (ruff + pytest)' (Join-Path $Root 'services/api') {
        if ((Get-DbMode) -eq 'docker') {
            Exec { docker compose -f ../../docker-compose.yml up -d --wait db-test }
        }
        Exec { .\.venv\Scripts\ruff.exe check . }
        Exec { .\.venv\Scripts\ruff.exe format --check . }
        Exec { .\.venv\Scripts\python.exe -m pytest }
    }
}

if ($Only -contains 'mobile') {
    Invoke-Step 'App (analyze + test)' (Join-Path $Root 'apps/mobile') {
        Exec { dart format --output=none --set-exit-if-changed lib test }
        Exec { flutter analyze }
        Exec { flutter test }
    }
}

if ($Only -contains 'web') {
    Invoke-Step 'Site (typecheck + lint + test)' (Join-Path $Root 'apps/web') {
        Exec { npm run typecheck }
        Exec { npm run lint }
        Exec { npm test }
    }
}

if ($Failures.Count -gt 0) {
    Write-Host "`nFalhas: $($Failures -join ', ')" -ForegroundColor Red
    exit 1
}
Write-Host "`nTodas as verificações passaram." -ForegroundColor Green
