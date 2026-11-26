<#
.SYNOPSIS
  Testes de integração (Fase 6.2): o app no emulador falando com a API real.
.DESCRIPTION
  Antes: a API rodando (scripts/dev-api.ps1) com AI_PROVIDER=demo no .env e um emulador
  Android ligado. Cada execução cria uma conta e2e.*@evofit.local e a exclui no fim.
  A API aceita 5 cadastros por hora por IP: depois disso, reinicie a API.
.EXAMPLE
  .\scripts\test-e2e.ps1
  .\scripts\test-e2e.ps1 -DemoPassword "quatro palavras da demo"
#>
param(
    [string]$Device = 'emulator-5554',
    # Senha da conta de demonstração (6.1); sem ela, o teste da demo é pulado.
    [string]$DemoPassword = ''
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot

try {
    $health = Invoke-RestMethod -Uri 'http://localhost:8000/api/v1/health' -TimeoutSec 5
} catch {
    Write-Host 'A API não respondeu em http://localhost:8000. Rode .\scripts\dev-api.ps1 antes.' -ForegroundColor Red
    exit 1
}
if ($health.database -ne 'ok') {
    Write-Host "A API respondeu, mas o banco não: $($health.database)" -ForegroundColor Red
    exit 1
}

$flutterArgs = @('test', 'integration_test', '-d', $Device)
if ($DemoPassword) { $flutterArgs += "--dart-define=DEMO_PASSWORD=$DemoPassword" }

Push-Location (Join-Path $Root 'apps/mobile')
try {
    & flutter @flutterArgs
    exit $LASTEXITCODE
} finally {
    Pop-Location
}
