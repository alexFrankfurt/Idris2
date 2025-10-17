param(
  [string]$Scheme = $env:SCHEME,
  [string]$Idris2Version = $env:IDRIS2_VERSION,
  [ValidateSet('Debug','Release','RelWithDebInfo','MinSizeRel')]
  [string]$Config = 'Release'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (-not $Scheme) {
  try {
    $Scheme = (Get-Command 'scheme' -ErrorAction Stop).Source
    Write-Verbose "Defaulting SCHEME to 'scheme' found on PATH."
  } catch {
    $Scheme = $null
  }
}

if (-not $Scheme -or -not $Idris2Version) {
  Write-Error "Required SCHEME or IDRIS2_VERSION is not set. Pass -Scheme and -Idris2Version or set environment variables."
}

try {
  $null = Get-Command $Scheme -ErrorAction Stop
} catch {
  throw "SCHEME executable '$Scheme' not found on PATH."
}

$repoRoot = Split-Path -Parent $PSCommandPath
Write-Host "Bootstrapping SCHEME=$Scheme IDRIS2_VERSION=$Idris2Version"

# 1) Prepare bootstrap-build/idris2_app with template and support DLL
$bootDir = Join-Path $repoRoot 'bootstrap-build'
New-Item -ItemType Directory -Force -Path $bootDir | Out-Null
$bootAppDir = Join-Path $bootDir 'idris2_app'
New-Item -ItemType Directory -Force -Path $bootAppDir | Out-Null

# Find and copy libidris2_support.dll next to the Chez sources
$dllCandidates = @(
  (Join-Path $repoRoot "build-cmake/support/c/$Config/libidris2_support.dll"),
  (Join-Path $repoRoot "support/c/build/$Config/libidris2_support.dll")
)
$foundDll = $null
foreach ($dll in $dllCandidates) {
  if (Test-Path $dll) { $foundDll = $dll; break }
}
if (-not $foundDll) {
  throw "libidris2_support.dll not found. Expected at:`n - $($dllCandidates -join "`n - ")`nBuild the C support library first (cmake --build build-cmake --config $Config)."
}
$supportName = Split-Path -Leaf $foundDll
Copy-Item -Force $foundDll $bootAppDir

# Generate idris2-boot.ss from template, replacing __PREFIX__ and support library name
$template = Join-Path $repoRoot 'bootstrap/idris2_app/idris2.ss'
$outSs   = Join-Path $bootAppDir 'idris2-boot.ss'
$prefixForChez = ($bootDir -replace '\\','/')
$templateContent = Get-Content -Raw $template
$generatedContent = $templateContent.Replace('__PREFIX__', $prefixForChez).Replace('libidris2_support.so', $supportName)
Set-Content -Encoding ASCII -Path $outSs -Value $generatedContent

# 2) Build bootstrap with Chez Scheme
Push-Location $bootDir
try {
  Write-Host 'Building idris2-boot from idris2-boot.ss'
  & $Scheme --script (Join-Path $repoRoot 'bootstrap/compile.ss')
}
finally {
  Pop-Location
}

# 3) Prepare output layout: build/exec and idris2_app
$execDir = Join-Path $repoRoot 'build/exec'
$appDir  = Join-Path $execDir 'idris2_app'
New-Item -ItemType Directory -Force -Path $execDir | Out-Null
New-Item -ItemType Directory -Force -Path $appDir | Out-Null

# 4) Copy bootstrap app payload
Copy-Item -Recurse -Force (Join-Path $bootDir 'idris2_app/*') $appDir

# 5) Create a PowerShell launcher instead of the POSIX shell script
$launcher = Join-Path $execDir 'idris2.ps1'
$launcherContent = @"
param([Parameter(ValueFromRemainingArguments=
$true)][string[]]`$Args)
`$ErrorActionPreference = 'Stop'
`$scriptDir = Split-Path -Parent `$PSCommandPath
`$app = Join-Path `$scriptDir 'idris2_app'
# Ensure DLLs and app are found
`$env:PATH = "`$app;`$env:PATH"
# Idris expects these sometimes; harmless on Windows
`$env:LD_LIBRARY_PATH = "`$app;`$env:LD_LIBRARY_PATH"
`$env:DYLD_LIBRARY_PATH = "`$app;`$env:DYLD_LIBRARY_PATH"
`$scheme = "$Scheme"
`$schemeResolved = (Get-Command `$scheme -ErrorAction SilentlyContinue).Path
if (-not `$schemeResolved) { `$schemeResolved = `$scheme }
`$schemeDir = Split-Path `$schemeResolved -Parent
`$schemeArch = Split-Path `$schemeDir -Leaf
`$schemeBin = Split-Path `$schemeDir -Parent
`$schemeRoot = Split-Path `$schemeBin -Parent
`$defaultBoot = Join-Path (Join-Path `$schemeRoot 'boot') `$schemeArch
if (-not `$env:CHEZSCHEMELIBDIRS -and (Test-Path `$defaultBoot)) {
  `$env:CHEZSCHEMELIBDIRS = `$defaultBoot
}
# Allow local bootstrap artefacts to take precedence if present
if (Test-Path (Join-Path `$app 'Program.boot')) {
  `$env:CHEZSCHEMELIBDIRS = "`$app;`$env:CHEZSCHEMELIBDIRS"
}
# Forward to Chez runtime boot image
& "$Scheme" --script (Join-Path `$app 'idris2-boot.so') @Args
"@
$launcherContent | Out-File -FilePath $launcher -Encoding ASCII -Force

Write-Host 'bootstrap stage 1 (chez) complete'