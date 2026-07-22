$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = (Resolve-Path '.').Path
$logPath = Join-Path $root 'rmd-v060-build-diagnostics.log'

function Join-Base64Parts {
    param(
        [Parameter(Mandatory = $true)][string]$Pattern,
        [Parameter(Mandatory = $true)][int]$ExpectedCount,
        [Parameter(Mandatory = $true)][string]$OutputPath,
        [Parameter(Mandatory = $true)][string]$ExpectedSha256,
        [string]$ExcludedName = ''
    )

    $parts = @(Get-ChildItem $Pattern | Where-Object { -not $ExcludedName -or $_.Name -ne $ExcludedName } | Sort-Object Name)
    if ($parts.Count -ne $ExpectedCount) {
        throw "Expected $ExpectedCount chunks for $Pattern, found $($parts.Count)."
    }

    $stream = [System.IO.File]::Create($OutputPath)
    try {
        foreach ($part in $parts) {
            $text = [System.IO.File]::ReadAllText($part.FullName).Trim()
            $bytes = [Convert]::FromBase64String($text)
            $stream.Write($bytes, 0, $bytes.Length)
            Write-Host "Decoded $($part.Name): $($bytes.Length) bytes"
        }
    } finally {
        $stream.Dispose()
    }

    $actual = (Get-FileHash $OutputPath -Algorithm SHA256).Hash.ToLowerInvariant()
    Write-Host "SHA-256 $OutputPath = $actual"
    if ($actual -ne $ExpectedSha256) {
        throw "Source hash mismatch for $OutputPath: $actual"
    }
}

function Apply-Overlay {
    param(
        [Parameter(Mandatory = $true)][string]$Archive,
        [switch]$HasDeletePaths,
        [string]$SpecialServerMain = ''
    )

    $extractDir = "$Archive.extract"
    New-Item -ItemType Directory -Force -Path $extractDir | Out-Null
    tar -xJf $Archive -C $extractDir
    if ($LASTEXITCODE -ne 0) { throw "Could not extract $Archive." }

    if ($HasDeletePaths) {
        $deleteFile = Join-Path $extractDir 'DELETE_PATHS.txt'
        if (Test-Path $deleteFile) {
            Get-Content $deleteFile | ForEach-Object {
                $relative = $_.Trim()
                if ($relative) {
                    Remove-Item -LiteralPath (Join-Path 'rmd-security' $relative) -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }

    tar -xJf $Archive -C rmd-security
    if ($LASTEXITCODE -ne 0) { throw "Could not apply $Archive." }
    Remove-Item 'rmd-security/DELETE_PATHS.txt' -Force -ErrorAction SilentlyContinue

    if ($SpecialServerMain) {
        Copy-Item $SpecialServerMain 'rmd-security/server/main.py' -Force
    }
}

Start-Transcript -Path $logPath -Force
try {
    Write-Host '=== Reconstruct source ==='
    Join-Base64Parts -Pattern 'rmd-build/chunks/part-*.b64' -ExpectedCount 13 -OutputPath 'RMD-0.4.0-reconstructed.tar.gz' -ExpectedSha256 '3a33b50b8bc46a0a49ad912531ff03b00d666a12e3d0d80d1099b8a0b2a6f2f3' -ExcludedName 'part-010.b64'
    New-Item -ItemType Directory -Force -Path rmd-security | Out-Null
    tar -xzf 'RMD-0.4.0-reconstructed.tar.gz' -C rmd-security
    if ($LASTEXITCODE -ne 0) { throw 'Could not extract RMD 0.4 base.' }

    Join-Base64Parts -Pattern 'rmd-build/overlay050/part-*.b64' -ExpectedCount 7 -OutputPath 'RMD-0.5.0-overlay.tar.xz' -ExpectedSha256 '1267dd1d9223c3da6d046722e4f7de11f5a3a9934d04d002039048409b2807fb'
    Apply-Overlay -Archive 'RMD-0.5.0-overlay.tar.xz' -HasDeletePaths -SpecialServerMain 'rmd-build/overlay050/server-main.py'

    Join-Base64Parts -Pattern 'rmd-build/overlay051/part-*.b64' -ExpectedCount 9 -OutputPath 'RMD-0.5.1-overlay.tar.xz' -ExpectedSha256 '7aed816e806e7ac8cf8aaf61d56ce2f194b377b11937e8e20b0fe2c78b73045d'
    Apply-Overlay -Archive 'RMD-0.5.1-overlay.tar.xz'

    Join-Base64Parts -Pattern 'rmd-build/overlay060/part-*.b64' -ExpectedCount 8 -OutputPath 'RMD-0.6.0-overlay.tar.xz' -ExpectedSha256 '87e8a1b0f4f7ac525a5bb664f918d766182234ef5a7ebc040b1309e5406f6c05'
    Apply-Overlay -Archive 'RMD-0.6.0-overlay.tar.xz' -HasDeletePaths

    Write-Host '=== Source identity ==='
    Get-Content 'rmd-security/pyproject.toml' | Select-String 'version ='

    Write-Host '=== Windows environment ==='
    python --version
    $python = (Get-Command python.exe).Source
    $inno = @(
        'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
        'C:\Program Files\Inno Setup 6\ISCC.exe'
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $inno) { throw 'Inno Setup compiler was not found.' }
    Write-Host "Python: $python"
    Write-Host "Inno: $inno"

    Set-Location 'rmd-security'
    python -m venv .windows-build-venv
    .\.windows-build-venv\Scripts\python.exe -m pip install --upgrade pip
    .\.windows-build-venv\Scripts\python.exe -m pip install 'pillow>=10,<13'

    Write-Host '=== Begin RMD build script ==='
    .\scripts\build_windows_installer.ps1 -PythonPath $python -InnoSetupPath $inno
    if ($LASTEXITCODE -ne 0) { throw "Build script exited with code $LASTEXITCODE." }
    Write-Host '=== RMD build script completed ==='
} catch {
    Write-Host '=== FAILURE ===' -ForegroundColor Red
    Write-Host $_.Exception.ToString() -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    throw
} finally {
    Set-Location $root
    Stop-Transcript
}
