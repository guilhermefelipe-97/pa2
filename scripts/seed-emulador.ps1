# Popula `places` no emulador (rode com scripts/emuladores.ps1 já ativo).
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..\firebase')

if (-not (Test-Path 'node_modules')) { npm install }
$env:FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080'
$env:GCLOUD_PROJECT = 'demo-naarea'
npm run seed
