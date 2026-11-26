<#
.SYNOPSIS
  Cria a chave de assinatura do APK de release (Fase 6.3, ADR-067). Roda uma vez por máquina.
.DESCRIPTION
  Gera uma keystore PKCS12 com senha aleatória em $HOME\.evofit\evofit-release.jks (fora do
  repositório) e escreve apps/mobile/android/key.properties (ignorado pelo git) apontando para ela.
  Nunca sobrescreve uma chave existente: um APK assinado com outra chave não instala por cima do
  anterior. Guarde uma cópia da pasta .evofit em lugar seguro.
.EXAMPLE
  .\scripts\make-keystore.ps1
#>
param(
    [string]$KeystoreDir = (Join-Path $HOME '.evofit')
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$KeyProperties = Join-Path $Root 'apps/mobile/android/key.properties'
$Keystore = Join-Path $KeystoreDir 'evofit-release.jks'
$Alias = 'evofit'

if (Test-Path $KeyProperties) {
    Write-Host "Já existe $KeyProperties; nada foi alterado." -ForegroundColor Yellow
    exit 0
}
if (Test-Path $Keystore) {
    Write-Host "Já existe $Keystore, mas falta key.properties. Recrie o key.properties com as senhas dessa chave; ela não foi sobrescrita." -ForegroundColor Red
    exit 1
}

# keytool vem com o JDK (JAVA_HOME) ou com o Android Studio (jbr).
$candidates = @()
if ($env:JAVA_HOME) { $candidates += Join-Path $env:JAVA_HOME 'bin/keytool.exe' }
$candidates += 'C:/Program Files/Android/Android Studio/jbr/bin/keytool.exe'
$cmd = Get-Command keytool -ErrorAction SilentlyContinue
if ($cmd) { $candidates += $cmd.Source }
$keytool = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $keytool) { throw 'keytool não encontrado: instale um JDK 17 ou defina JAVA_HOME.' }

# Senha aleatória de 32 caracteres (PKCS12 usa a mesma para a keystore e a chave).
$bytes = New-Object byte[] 24
[System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
$password = [Convert]::ToBase64String($bytes).Replace('+', 'A').Replace('/', 'B')

New-Item -ItemType Directory -Force $KeystoreDir | Out-Null
# A senha vai por variável de ambiente, não pela linha de comando (não aparece na lista de processos).
$env:EVOFIT_KS_PASS = $password
try {
    & $keytool -genkeypair -v -storetype PKCS12 -keystore $Keystore -alias $Alias `
        -keyalg RSA -keysize 2048 -validity 10000 `
        -dname 'CN=EvoFit, OU=TCC, O=EvoFit, C=BR' `
        -storepass:env EVOFIT_KS_PASS -keypass:env EVOFIT_KS_PASS | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'keytool falhou ao criar a chave.' }
} finally {
    Remove-Item Env:EVOFIT_KS_PASS -ErrorAction SilentlyContinue
}

$storeFile = $Keystore.Replace('\', '/')
@(
    '# Assinatura do release (scripts/make-keystore.ps1). Arquivo local: nao versionar (fica no .gitignore).',
    "storeFile=$storeFile",
    "storePassword=$password",
    "keyAlias=$Alias",
    "keyPassword=$password"
) | Set-Content -Path $KeyProperties -Encoding ascii

Write-Host "Chave criada em $Keystore" -ForegroundColor Green
Write-Host "Senhas gravadas em $KeyProperties (fora do git)." -ForegroundColor Green
Write-Host 'Faça uma cópia de segurança da pasta .evofit e do key.properties: sem eles, novas versões não instalam por cima.' -ForegroundColor Yellow
