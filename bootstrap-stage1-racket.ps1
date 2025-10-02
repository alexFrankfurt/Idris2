param(
  [string]$Idris2Version = $env:IDRIS2_VERSION,
  [ValidateSet('Debug','Release','RelWithDebInfo','MinSizeRel')]
  [string]$Config = 'Release'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (-not $Idris2Version) {
  Write-Error "Required IDRIS2_VERSION is not set. Pass -Idris2Version or set environment variable."
}

$repoRoot = Split-Path -Parent $PSCommandPath
Write-Host "Bootstrapping IDRIS2_VERSION=$Idris2Version"

# 1) Prepare bootstrap-build/idris2_app with template and support DLL
$bootDir = Join-Path $repoRoot 'bootstrap-build'
New-Item -ItemType Directory -Force -Path (Join-Path $bootDir 'idris2_app') | Out-Null

# Generate idris2-boot.rkt from template, replacing __PREFIX__ with bootstrap-build path
$template = Join-Path $repoRoot 'bootstrap/idris2_app/idris2.rkt'
$outRkt  = Join-Path $bootDir 'idris2_app/idris2-boot.rkt'
# Use forward slashes to avoid Racket string escape issues
$prefixForRacket = ($bootDir -replace '\\','/')
(Get-Content -Raw $template).Replace('__PREFIX__', $prefixForRacket) | Set-Content -Encoding ASCII -Path $outRkt

# Find and copy libidris2_support.dll into bootstrap-build/idris2_app
$dllCandidates = @(
  (Join-Path $repoRoot "build-cmake/support/c/$Config/libidris2_support.dll"),
  (Join-Path $repoRoot "support/c/build/$Config/libidris2_support.dll")
)
$foundDll = $null
foreach ($dll in $dllCandidates) { if (Test-Path $dll) { $foundDll = $dll; break } }
if (-not $foundDll) {
  throw "libidris2_support.dll not found. Expected at: `n - $($dllCandidates -join "`n - ")`nBuild the C support library first (cmake --build build-cmake --config $Config)."
}
Copy-Item -Force $foundDll (Join-Path $bootDir 'idris2_app')

# Ensure the folder with the DLL is on PATH so Racket FFI can resolve it during raco exe
$dllDir = Split-Path -Parent $foundDll
$env:PATH = "$dllDir;$env:PATH"

# 2) Build bootstrap with Racket
Push-Location $bootDir
try {
  Write-Host 'Building idris2-boot from idris2-boot.rkt'
  raco exe idris2_app/idris2-boot.rkt
}
finally {
  Pop-Location
}

# 2) Prepare output layout
$execDir = Join-Path $repoRoot 'build/exec'
$appDir  = Join-Path $execDir 'idris2_app'
New-Item -ItemType Directory -Force -Path $execDir | Out-Null
New-Item -ItemType Directory -Force -Path $appDir | Out-Null

# 3) Copy payload
# Ensure no running process is locking the exe before copying
Get-Process idris2-boot -ErrorAction SilentlyContinue | Stop-Process -Force
if (Test-Path (Join-Path $appDir 'idris2-boot.exe')) { Remove-Item -Force (Join-Path $appDir 'idris2-boot.exe') }
Copy-Item -Recurse -Force (Join-Path $bootDir 'idris2_app/*') $appDir

# 4) Create a PowerShell launcher mirroring idris2-rktboot.sh
$launcher = Join-Path $execDir 'idris2.ps1'
# Use bootstrap-build/idris2_app for runtime DLLs to avoid locking target DLLs
$bootAppDir = Join-Path $bootDir 'idris2_app'
$launcherContent = @"
`$ErrorActionPreference = 'Stop'
`$app = "$bootAppDir"
`$env:PATH = "`$app;`$env:PATH"
`$env:LD_LIBRARY_PATH = "`$app;`$env:LD_LIBRARY_PATH"
`$env:DYLD_LIBRARY_PATH = "`$app;`$env:DYLD_LIBRARY_PATH"
& (Join-Path `$app 'idris2-boot.exe') @args
"@
$launcherContent | Out-File -FilePath $launcher -Encoding ASCII -Force

Write-Host 'bootstrap stage 1 (racket) complete'