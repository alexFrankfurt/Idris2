param(
  [Parameter(Mandatory=$true)][string]$Prefix,
  [Parameter(Mandatory=$true)][string]$Version
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Write-Host "[Idris2] Installing to prefix: $Prefix (version $Version)"

# Compute repository root (this script lives in tools/)
$repoRoot = Split-Path -Parent $PSScriptRoot

# Layout:
#  - $Prefix/bin/idris2.ps1 and idris2.cmd
#  - $Prefix/bin/idris2_app/*
#  - $Prefix/idris2-$Version/{lib,support/c} (support/c installed via CMake separately)
#  - $Prefix/idris2-$Version/<lib>-$Version (ttc files)

$binDir = Join-Path $Prefix 'bin'
$appDir = Join-Path $binDir 'idris2_app'
${libRoot} = Join-Path $Prefix ("idris2-" + $Version)
Write-Host "[Idris2] Ensuring directories: $binDir, $appDir"
New-Item -ItemType Directory -Force -Path $binDir | Out-Null
New-Item -ItemType Directory -Force -Path $appDir | Out-Null

############################################
# Create launcher (installed, self-contained)
############################################
$launcherPath = Join-Path $binDir 'idris2.ps1'
$launcherContent = @"
`$ErrorActionPreference = 'Stop'
`$app = Join-Path `$PSScriptRoot 'idris2_app'
# Rely on Idris to create build and ttc directories on demand
`$env:PATH = "`$app\lib;`$app;`$env:PATH"
`$env:LD_LIBRARY_PATH = "`$app\lib;`$app;`$env:LD_LIBRARY_PATH"
`$env:DYLD_LIBRARY_PATH = "`$app\lib;`$app;`$env:DYLD_LIBRARY_PATH"
`$env:IDRIS2_LIB_DIR = "${libRoot}"
`$env:IDRIS2_PREFIX = "${Prefix}"
`$env:IDRIS2_DATA = (Join-Path "${libRoot}" 'support')
`$env:RACKET = "racket"
`$env:RACKET_RACO = "raco"
& (Join-Path `$app 'idris2-boot.exe') @args
"@
Write-Host "[Idris2] Writing launcher to: $launcherPath"
$launcherContent | Out-File -FilePath $launcherPath -Encoding ASCII -Force

# Create idris2.cmd shim for convenience
$idrisCmd = @"
@echo off
setlocal
set SCRIPT_DIR=%~dp0
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%idris2.ps1" %*
"@
$idrisCmd | Out-File -FilePath (Join-Path $binDir 'idris2.cmd') -Encoding ASCII -Force

############################################
# Build an installed idris2-boot.exe targeting the install prefix
############################################
# Generate idris2-boot.rkt from template, replacing __PREFIX__ with install prefix
$template = Join-Path $repoRoot 'bootstrap/idris2_app/idris2.rkt'
if (-not (Test-Path $template)) { throw "Template not found: $template" }
$prefixForRacket = ($Prefix -replace '\\','/')
$outRkt  = Join-Path $appDir 'idris2-boot.rkt'
Write-Host "[Idris2] Generating Racket bootstrap with prefix: $prefixForRacket"
(Get-Content -Raw $template).Replace('__PREFIX__', $prefixForRacket) | Set-Content -Encoding ASCII -Path $outRkt

# Copy support DLL into installed app dir
$dllCandidates = @(
  (Join-Path $repoRoot 'build-cmake/support/c/Release/libidris2_support.dll'),
  (Join-Path $repoRoot 'support/c/build/Release/libidris2_support.dll')
)
$copied = $false
foreach ($dll in $dllCandidates) {
  if (Test-Path $dll) {
    Write-Host "[Idris2] Copying support DLL: $dll -> $appDir"
    Copy-Item -Force $dll $appDir
    $copied = $true
    break
  }
}
if (-not $copied) { Write-Warning '[Idris2] libidris2_support.dll not found in expected locations; idris may fail at runtime.' }

# Build the executable with raco into the installed app directory
Push-Location $appDir
try {
  Write-Host "[Idris2] Building idris2-boot.exe (raco exe)..."
  raco exe 'idris2-boot.rkt'
}
finally {
  Pop-Location
}

# Install Racket backend support files (required for Racket codegen at runtime)
$destRoot = $libRoot
$srcRktSupport = Join-Path $repoRoot 'support/racket'
if (Test-Path $srcRktSupport) {
  $destRktSupport = Join-Path $destRoot 'support/racket'
  Write-Host "[Idris2] Installing Racket support files -> $destRktSupport"
  New-Item -ItemType Directory -Force -Path $destRktSupport | Out-Null
  Copy-Item -Recurse -Force (Join-Path $srcRktSupport '*') $destRktSupport
} else {
  Write-Warning "[Idris2] Racket support files not found at $srcRktSupport"
}

# Install libraries (copy built TTCs)
$libs = @('prelude','base','linear','network','contrib','test','papers')
New-Item -ItemType Directory -Force -Path $destRoot | Out-Null
foreach ($lib in $libs) {
  $srcTtc = Join-Path $repoRoot ("libs/" + $lib + "/build/ttc")
  if (Test-Path $srcTtc) {
    $dest = Join-Path $destRoot ("$lib-" + $Version)
    Write-Host "[Idris2] Installing library TTCs: $lib -> $dest"
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    Copy-Item -Recurse -Force (Join-Path $srcTtc '*') $dest
  } else {
    Write-Host "[Idris2] Skipping library (not built): $lib"
  }
}

Write-Host "[Idris2] Installation complete at: $Prefix"
