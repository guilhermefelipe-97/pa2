# Sobe os emuladores de Auth e Firestore usando o firebase.json da raiz
# (o app/firebase.json gerado pelo flutterfire não tem config de emuladores).
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location $root

$jdk = if ($env:NAAREA_JDK) { $env:NAAREA_JDK } else { 'C:\Program Files\Java\jdk-24' }
if (-not (Test-Path (Join-Path $jdk 'bin\java.exe'))) {
    throw "JDK nao encontrado em '$jdk'. Instale um JDK 21+ ou defina `$env:NAAREA_JDK."
}
$env:JAVA_HOME = $jdk
$env:PATH = "$jdk\bin;$env:PATH"

# Aspas obrigatórias: sem elas o PowerShell transforma auth,firestore em array.
firebase emulators:start --only "auth,firestore" --project demo-naarea
