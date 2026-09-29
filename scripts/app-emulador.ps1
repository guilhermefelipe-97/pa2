# Roda o app no Chrome apontando para os emuladores locais.
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..\app')
flutter run -d chrome --dart-define=USE_EMULATOR=true
