# Gera um APK debug que conversa com os emuladores rodando neste PC.
# O celular precisa estar na mesma rede Wi-Fi. Uso: .\scripts\apk-emulador.ps1 [-Ip 192.168.0.10]
param([string]$Ip)
$ErrorActionPreference = 'Stop'
if (-not $Ip) {
    $Ip = (Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object { $_.PrefixOrigin -in 'Dhcp', 'Manual' -and $_.IPAddress -notlike '169.*' } |
        Select-Object -First 1).IPAddress
}
if (-not $Ip) { throw 'Nao achei o IP da rede local; passe -Ip.' }
Set-Location (Join-Path $PSScriptRoot '..\app')
flutter build apk --debug --dart-define=USE_EMULATOR=true --dart-define=EMULATOR_HOST=$Ip
Write-Host "APK: app\build\app\outputs\flutter-apk\app-debug.apk (emuladores em $Ip)"
