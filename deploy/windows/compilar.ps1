$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = (Resolve-Path "$PSScriptRoot/../..").Path
Push-Location "$root/app"
try {
    # Un SDK recién clonado imprime el bootstrap antes del JSON de --machine.
    flutter --version
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo preparar Flutter' }
    $sdk = flutter --version --machine | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or $sdk.frameworkVersion -ne '3.47.4') {
        throw 'Se necesita Flutter 3.47.4'
    }
    $lines = @(Get-Content pubspec.yaml | Where-Object { $_ -match '^version:\s+' })
    if ($lines.Count -ne 1 -or $lines[0] -notmatch '^version:\s+(\d+\.\d+\.\d+)\+(\d+)\s*$') {
        throw 'Versión de pubspec inválida'
    }
    $version = $Matches[1]
    $compilation = [int]$Matches[2]
    flutter pub get --enforce-lockfile
    if ($LASTEXITCODE -ne 0) { throw 'Dependencias distintas o no disponibles' }
    flutter analyze
    if ($LASTEXITCODE -ne 0) { throw 'Analyze falló' }
    flutter test test/pantallas/ayuda --concurrency=3
    if ($LASTEXITCODE -ne 0) { throw 'Las pruebas del tutorial fallaron en Windows' }
    flutter test test/pantallas/tablero --concurrency=3
    if ($LASTEXITCODE -ne 0) { throw 'Las pruebas del tablero con ratón fallaron en Windows' }
    flutter test test/nucleo/base test/nucleo/cola test/pantallas/sincronizacion --concurrency=3
    if ($LASTEXITCODE -ne 0) { throw 'Las pruebas del trabajo sin conexión fallaron en Windows' }
    flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw 'Compilación Windows falló' }
    $bundle = (Resolve-Path 'build/windows/x64/runner/Release').Path
    foreach ($required in @('reparto.exe', 'flutter_windows.dll', 'data/app.so', 'data/icudtl.dat', 'data/flutter_assets/assets/manual/manual.txt')) {
        if (-not (Test-Path "$bundle/$required" -PathType Leaf)) { throw "Falta $required" }
    }
    $manual = (Get-FileHash assets/manual/manual.txt -Algorithm SHA256).Hash.ToLowerInvariant()
    if ((Get-FileHash "$bundle/data/flutter_assets/assets/manual/manual.txt" -Algorithm SHA256).Hash.ToLowerInvariant() -ne $manual) {
        throw 'Manual compilado distinto'
    }
    # La aplicación se entrega con sus DLL de runtime; el exe suelto no arranca.
    $vswhere = "${env:ProgramFiles(x86)}/Microsoft Visual Studio/Installer/vswhere.exe"
    $vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if ($LASTEXITCODE -ne 0 -or -not $vs) { throw 'No hay compilador C++ de Visual Studio' }
    $crt = Get-ChildItem "$vs/VC/Redist/MSVC" -Directory | Sort-Object Name -Descending |
        ForEach-Object { Join-Path $_.FullName 'x64/Microsoft.VC143.CRT' } |
        Where-Object { Test-Path $_ -PathType Container } | Select-Object -First 1
    if (-not $crt) { throw 'No hay redistribuible C++' }
    Copy-Item "$crt/*.dll" $bundle
    foreach ($dll in @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
        if (-not (Test-Path "$bundle/$dll" -PathType Leaf)) { throw "Falta runtime $dll" }
    }
    $out = "$root/app/build/windows-distribucion"
    if (Test-Path $out) { throw 'La distribución ya existe: no sobrescribir' }
    New-Item $out -ItemType Directory | Out-Null
    Compress-Archive -Path "$bundle/*" -DestinationPath "$out/reparto-$version-windows.zip"
    $iscc = "${env:ProgramFiles(x86)}/Inno Setup 6/ISCC.exe"
    if (-not (Test-Path $iscc)) { throw 'No está instalado Inno Setup 6' }
    & $iscc "/DVersion=$version" "/DBundleDir=$bundle" "/DOutputDir=$out" "$root/deploy/windows/reparto.iss"
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo crear el instalador' }
    $setup = "$out/reparto-$version-windows-setup.exe"
    if (-not (Test-Path $setup -PathType Leaf)) { throw 'No se generó el instalador' }
    # Instalar en una carpeta de prueba sin abrir ni conectar la aplicación.
    $testInstall = Join-Path ([IO.Path]::GetTempPath()) ("reparto-instalar-" + [guid]::NewGuid().ToString('N'))
    $process = Start-Process -FilePath $setup -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-', "/DIR=`"$testInstall`"") -PassThru
    if (-not $process.WaitForExit(60000)) { $process.Kill(); throw 'Instalador no terminó' }
    if ($process.ExitCode -ne 0) { throw 'Falló la instalación de prueba' }
    foreach ($file in Get-ChildItem $bundle -File -Recurse) {
        $relative = [IO.Path]::GetRelativePath($bundle, $file.FullName)
        $installed = Join-Path $testInstall $relative
        if (-not (Test-Path $installed -PathType Leaf) -or (Get-FileHash $installed -Algorithm SHA256).Hash -ne (Get-FileHash $file.FullName -Algorithm SHA256).Hash) {
            throw "Instalación incompleta o distinta: $relative"
        }
    }
    $commit = (git rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo identificar la fuente' }
    $files = @(Get-ChildItem $out -File | ForEach-Object {
        [ordered]@{file=$_.Name; bytes=$_.Length; sha256=(Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
    })
    [ordered]@{
        version=$version; compilation=$compilation; source_commit=$commit; flutter_version=$sdk.frameworkVersion
        manual_sha256=$manual; installer_files_verified=$true; application_launch_verified=$false
        physical_installation_verified=$false; files=$files
    } | ConvertTo-Json -Depth 5 | Set-Content "$out/windows-verification.json" -Encoding utf8
    Write-Host "Instalador y paquete completos: $out"
} finally {
    Pop-Location
}
