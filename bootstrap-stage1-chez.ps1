param(
  [string]$Scheme = $env:SCHEME,
  [string]$Idris2Version = $env:IDRIS2_VERSION
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (-not $Scheme -or -not $Idris2Version) {
  Write-Error "Required SCHEME or IDRIS2_VERSION is not set. Pass -Scheme and -Idris2Version or set environment variables."
}

$repoRoot = Split-Path -Parent $PSCommandPath
Write-Host "Bootstrapping SCHEME=$Scheme IDRIS2_VERSION=$Idris2Version"

# 1) Build bootstrap with Chez Scheme
$bootDir = Join-Path $repoRoot 'bootstrap-build'
Push-Location $bootDir
try {
  Write-Host 'Building idris2-boot from idris2-boot.ss'
  & $Scheme --script (Join-Path $repoRoot 'bootstrap/compile.ss')
}
finally {
  Pop-Location
}

# 2) Prepare output layout: build/exec and idris2_app
$execDir = Join-Path $repoRoot 'build/exec'
$appDir  = Join-Path $execDir 'idris2_app'
New-Item -ItemType Directory -Force -Path $execDir | Out-Null
New-Item -ItemType Directory -Force -Path $appDir | Out-Null

# 3) Copy bootstrap app payload
Copy-Item -Recurse -Force (Join-Path $bootDir 'idris2_app/*') $appDir

# 4) Create a PowerShell launcher instead of the POSIX shell script
$launcher = Join-Path $execDir 'idris2.ps1'
$launcherContent = @"
param([Parameter(ValueFromRemainingArguments=
$true)][string[]]`$Args)
`$ErrorActionPreference = 'Stop'
`$scriptDir = Split-Path -Parent `$PSCommandPath
`$app = Join-Path `$scriptDir 'idris2_app'
# Ensure DLLs and app are found
`$env:PATH = "$($app);$env:PATH"
# Idris expects these sometimes; harmless on Windows
`$env:LD_LIBRARY_PATH = "$($app);$env:LD_LIBRARY_PATH"
`$env:DYLD_LIBRARY_PATH = "$($app);$env:DYLD_LIBRARY_PATH"
# Forward to Chez runtime boot image
& "$Scheme" --script (Join-Path `$app 'idris2-boot.so') @Args
"@
$launcherContent | Out-File -FilePath $launcher -Encoding ASCII -Force

Write-Host 'bootstrap stage 1 (chez) complete'