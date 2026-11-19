# Тести ядра SvitloCore на Windows (Swift для Windows у D:\DevTools\Swift, Windows SDK і MSVC).
# Шлях проєкту має кирилицю, а інструменти Swift на Windows з нею не дружать, тож пакет копіюємо
# в теку з латиницею (як android/build.py) і збираємо там. Тека .build лишається між запусками.
# Запуск:  & "ios\tools\test-core.ps1"            усі тести
#          & "ios\tools\test-core.ps1" LogicTests  лише тести, у назві яких є «LogicTests»
param([string]$Filter = "", [switch]$BuildOnly)
$ErrorActionPreference = 'Stop'

$src = Resolve-Path (Join-Path $PSScriptRoot '..\SvitloCore')
$work = 'D:\DevTools\work\SvitloCore'
New-Item -ItemType Directory -Force $work | Out-Null
foreach ($part in 'Sources', 'Tests') {
    $target = Join-Path $work $part
    if (Test-Path $target) { Remove-Item -Recurse -Force $target }
    Copy-Item -Recurse (Join-Path $src $part) $target
}
Copy-Item -Force (Join-Path $src 'Package.swift') (Join-Path $work 'Package.swift')

# Заголовки C (Windows SDK, MSVC) Swift шукає за змінними середовища розробника: беремо їх із vcvars64.bat.
$vswhere = 'C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe'
$vs = & $vswhere -all -prerelease -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath | Select-Object -First 1
if (-not $vs) { throw "Не знайдено Visual Studio Build Tools з MSVC" }
$vcvars = Join-Path $vs 'VC\Auxiliary\Build\vcvars64.bat'
if (-not (Test-Path $vcvars)) { throw "Не знайдено vcvars64.bat (потрібні Build Tools з MSVC)" }
foreach ($line in (cmd /c "`"$vcvars`" >nul 2>&1 && set")) {
    $eq = $line.IndexOf('=')
    if ($eq -gt 0) { Set-Item -Path ("env:" + $line.Substring(0, $eq)) -Value $line.Substring($eq + 1) }
}

# Swift ставить шляхи в змінні користувача; у вже відкритій консолі їх ще немає.
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$swiftPaths = ($userPath -split ';') | Where-Object { $_ -like '*Swift*' }
$env:Path = (($swiftPaths -join ';') + ';' + $env:Path)
if (-not $env:SDKROOT) { $env:SDKROOT = [Environment]::GetEnvironmentVariable('SDKROOT', 'User') }

# Swift пише хід збирання в stderr; у Windows PowerShell 5.1 з 'Stop' це обриває скрипт.
$ErrorActionPreference = 'Continue'
Push-Location $work
try {
    # Нова система збирання SwiftPM (swiftbuild) на Windows не передає компілятору шляхи до заголовків C,
    # тож лишаємося на звичній (native).
    if ($BuildOnly) {
        swift build --build-tests --build-system native
    } elseif ($Filter) {
        swift test --build-system native --filter $Filter
    } else {
        swift test --build-system native
    }
    $code = $LASTEXITCODE
} finally {
    Pop-Location
}
exit $code
