<#
.SYNOPSIS
  Sobe o PostgreSQL de desenvolvimento, aplica as migrações e inicia a API com reload.
  Na primeira execução cria o ambiente virtual e instala as dependências.
#>
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Api = Join-Path $Root 'services/api'

if (-not (Test-Path (Join-Path $Root '.env'))) {
    Copy-Item (Join-Path $Root '.env.example') (Join-Path $Root '.env')
    Write-Host 'Criado .env a partir de .env.example' -ForegroundColor Yellow
}

# DB_MODE=local (no .env ou no ambiente) usa o PostgreSQL instalado na máquina, sem Docker.
$dbMode = $env:DB_MODE
if (-not $dbMode) {
    $line = Get-Content (Join-Path $Root '.env') | Where-Object { $_ -match '^\s*DB_MODE\s*=' } | Select-Object -Last 1
    $dbMode = if ($line) { ($line -split '=', 2)[1].Trim() } else { 'docker' }
}
if ($dbMode -eq 'docker') {
    docker compose -f (Join-Path $Root 'docker-compose.yml') up -d --wait db
    if ($LASTEXITCODE -ne 0) { throw 'Não foi possível subir o banco. O Docker Desktop está aberto?' }
} else {
    Write-Host "DB_MODE=${dbMode}: usando o PostgreSQL de DATABASE_URL (sem Docker)." -ForegroundColor Yellow
}

Push-Location $Api
try {
    if (-not (Test-Path '.venv')) {
        py -3.14 -m venv .venv
        .\.venv\Scripts\python.exe -m pip install -e '.[dev]'
        if ($LASTEXITCODE -ne 0) { throw 'Falha ao instalar dependências.' }
    }
    .\.venv\Scripts\alembic.exe upgrade head
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao aplicar migrações.' }
    .\.venv\Scripts\uvicorn.exe app.main:app --reload --host 0.0.0.0 --port 8000
} finally {
    Pop-Location
}
