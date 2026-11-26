<#
.SYNOPSIS
  Gera o APK de release assinado do EvoFit (Fase 6.3, ADR-067).
.DESCRIPTION
  O endereço da API entra no build (--dart-define=API_BASE_URL); o app não guarda nenhum segredo.
  Por padrão exige HTTPS. Para uma demonstração com a API num computador da rede local, use
  -AllowHttp: o APK sai com "-http" no nome e aceita HTTP sem TLS.
  Antes, rode uma vez .\scripts\make-keystore.ps1. O APK vai para dist/ com o SHA-256 ao lado.
.EXAMPLE
  .\scripts\build-apk.ps1 -ApiUrl https://api.exemplo.com.br
  .\scripts\build-apk.ps1 -ApiUrl http://192.168.0.10:8000 -AllowHttp
  .\scripts\build-apk.ps1 -ApiUrl http://10.0.2.2:8000 -AllowHttp   # emulador
#>
param(
    [Parameter(Mandatory = $true)][string]$ApiUrl,
    [switch]$AllowHttp
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Mobile = Join-Path $Root 'apps/mobile'

function Stop-Build([string]$Message) {
    Write-Host $Message -ForegroundColor Red
    exit 1
}

# 1. Endereço da API: absoluto, sem caminho (o app acrescenta /api/v1), HTTPS salvo -AllowHttp.
$ApiUrl = $ApiUrl.TrimEnd('/')
$uri = $null
if (-not [Uri]::TryCreate($ApiUrl, [UriKind]::Absolute, [ref]$uri) -or
    ($uri.Scheme -ne 'https' -and $uri.Scheme -ne 'http') -or -not $uri.Host) {
    Stop-Build "Endereço inválido: '$ApiUrl'. Use algo como https://api.exemplo.com.br"
}
if ($uri.AbsolutePath -ne '/' -or $uri.Query -or $uri.UserInfo) {
    Stop-Build "Informe só o endereço do servidor, sem caminho, consulta ou usuário (o app acrescenta /api/v1): '$ApiUrl'"
}
if ($uri.Scheme -eq 'http' -and -not $AllowHttp) {
    Stop-Build "O APK de release exige HTTPS. Para a API num computador da rede local, acrescente -AllowHttp."
}
if ($uri.Scheme -eq 'https' -and $AllowHttp) {
    Write-Host 'Aviso: -AllowHttp ignorado, o endereço já é HTTPS.' -ForegroundColor Yellow
    $AllowHttp = $false
}

# 2. Chave de assinatura (fora do repositório).
if (-not (Test-Path (Join-Path $Mobile 'android/key.properties'))) {
    Stop-Build 'Falta a chave de assinatura. Rode antes: .\scripts\make-keystore.ps1'
}

# 3. Versão do pubspec (version: 1.0.0+1).
$versionLine = Get-Content (Join-Path $Mobile 'pubspec.yaml') | Where-Object { $_ -match '^version:\s*' } | Select-Object -First 1
$version = (($versionLine -split ':', 2)[1].Trim() -split '\+')[0]

$flutterArgs = @('build', 'apk', '--release', "--dart-define=API_BASE_URL=$ApiUrl")
if ($AllowHttp) { $flutterArgs += @('-P', 'evofit.allowHttp=true') }

Push-Location $Mobile
try {
    & flutter @flutterArgs
    if ($LASTEXITCODE -ne 0) { Stop-Build 'O build do APK falhou (veja a saída acima).' }
} finally {
    Pop-Location
}

# 4. Cópia com nome claro e o SHA-256 ao lado.
$dist = Join-Path $Root 'dist'
New-Item -ItemType Directory -Force $dist | Out-Null
$suffix = if ($AllowHttp) { '-http' } else { '' }
$apk = Join-Path $dist "evofit-$version$suffix.apk"
Copy-Item (Join-Path $Mobile 'build/app/outputs/flutter-apk/app-release.apk') $apk -Force
$hash = (Get-FileHash $apk -Algorithm SHA256).Hash.ToLower()
"$hash  $(Split-Path -Leaf $apk)" | Set-Content -Path "$apk.sha256" -Encoding ascii

$sizeMb = [Math]::Round((Get-Item $apk).Length / 1MB, 1)
Write-Host "APK: $apk ($sizeMb MB)" -ForegroundColor Green
Write-Host "API: $ApiUrl" -ForegroundColor Green
Write-Host "SHA-256: $hash" -ForegroundColor Green
