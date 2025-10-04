param(
  [string]$Idris2Cg = $env:IDRIS2_CG, # chez|racket|other
  [string]$Scheme   = $env:SCHEME,
  [ValidateSet('Debug','Release','RelWithDebInfo','MinSizeRel')]
  [string]$Config = 'Release'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSCommandPath
$bootstrapPrefix = Join-Path $repoRoot 'bootstrap-build'

if (-not $Idris2Cg) { $Idris2Cg = 'chez' }

Write-Host "bootstrapping in: $bootstrapPrefix"

# Setup environment similar to the .sh script
$env:LD_LIBRARY_PATH = if ($env:LD_LIBRARY_PATH) { "$bootstrapPrefix/lib;$env:LD_LIBRARY_PATH" } else { "$bootstrapPrefix/lib" }
$env:DYLD_LIBRARY_PATH = if ($env:DYLD_LIBRARY_PATH) { "$bootstrapPrefix/lib;$env:DYLD_LIBRARY_PATH" } else { "$bootstrapPrefix/lib" }
# IDRIS2_DATA will ultimately point to a versioned support dir under yprefix/idris2-<ver>/support
$versionedPrefix = Join-Path $bootstrapPrefix 'idris2-0.7.0'
$env:IDRIS2_DATA = if ($env:IDRIS2_DATA) { (Join-Path $versionedPrefix 'support') + ";" + $env:IDRIS2_DATA } else { (Join-Path $versionedPrefix 'support') }

# Optionally build support lib if not present
$supportSrc = Join-Path $repoRoot 'support/c'
$supportBld = Join-Path $supportSrc 'build'
if (-not (Test-Path (Join-Path $supportBld "$Config/libidris2_support.dll"))) {
  cmake -S "$supportSrc" -B "$supportBld" -DIDRIS2_VERSION="0.7.0" | Out-Null
  cmake --build "$supportBld" --config $Config | Out-Null
}

# Stage 2 flow: emulate Makefile goals using the bootstrap idris2
$env:IDRIS2_BOOT = Join-Path (Join-Path $repoRoot 'build/exec') 'idris2.ps1'

# Determine TTC version used by the bootstrap compiler so we can pre-create folders
$ttcVersion = 2023090800
$ttcSourceCandidates = @(
  (Join-Path $repoRoot 'build/exec/idris2_app/idris2-boot.rkt'),
  (Join-Path $repoRoot 'bootstrap-build/idris2_app/idris2-boot.rkt'),
  (Join-Path $repoRoot 'bootstrap/idris2_app/idris2.rkt')
)
foreach ($f in $ttcSourceCandidates) {
  if (Test-Path $f) {
    try {
      $txt = Get-Content -Raw $f
      if ($txt -match 'ttcVersion[^0-9]*([0-9]{6,})') { $ttcVersion = [int64]$matches[1]; break }
    } catch {}
  }
}

# Generate IdrisPaths with Windows-friendly yprefix
$pathsIdr = Join-Path $repoRoot 'src/IdrisPaths.idr'
$versionTag = ''
$major = 0; $minor = 7; $patch = 0
$yprefix = "$bootstrapPrefix"
@(
  "-- @generated",
  "module IdrisPaths",
  "export idrisVersion : ((Nat,Nat,Nat), String); idrisVersion = (($major,$minor,$patch), `"$versionTag`")",
  "export yprefix : String; yprefix=`"$yprefix`""
) | Set-Content -Encoding ASCII -Path $pathsIdr

# Build the Idris2 executable and libraries roughly like 'make all'
# 1) Ensure the app folder exists; prefer reusing DLL from bootstrap stage (now placed under bootstrap-build/idris2_app/lib)
$targetDir = Join-Path $repoRoot 'build/exec/idris2_app'
New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
$libDir = Join-Path $targetDir 'lib'
New-Item -ItemType Directory -Force -Path $libDir | Out-Null
# If a DLL already exists under bootstrap-build/idris2_app/lib, just ensure PATH picks it up.
$bootstrapDll = Join-Path $bootstrapPrefix 'idris2_app/lib/libidris2_support.dll'
if (Test-Path $bootstrapDll) {
  Write-Host '[bootstrap-stage2] Reusing bootstrap support DLL.'
  if (-not ($env:PATH -split ';' | Where-Object { $_ -eq (Split-Path -Parent $bootstrapDll) })) {
    $env:PATH = (Split-Path -Parent $bootstrapDll) + ';' + $env:PATH
  }
  # If a duplicate root-level DLL exists, remove it to avoid the runtime preferring the root path and to reduce race surface
  $rootDup = Join-Path $targetDir 'libidris2_support.dll'
  if (Test-Path $rootDup) {
    try {
      Remove-Item -Force $rootDup -ErrorAction Stop
      Write-Host '[bootstrap-stage2] Removed duplicate root-level support DLL.'
    } catch {
      Write-Warning "[bootstrap-stage2] Could not remove duplicate root DLL: $($_.Exception.Message)"
    }
  }
} else {
  # Fallback: locate a built DLL and copy only if we do not already have one in target lib
  $builtDll = Join-Path (Join-Path $repoRoot "build-cmake/support/c/$Config") 'libidris2_support.dll'
  if (-not (Test-Path $builtDll)) { $builtDll = Join-Path $supportBld "$Config/libidris2_support.dll" }
  if (Test-Path $builtDll) {
    $destDll = Join-Path $libDir 'libidris2_support.dll'
    if (-not (Test-Path $destDll)) {
      try { Copy-Item -Force $builtDll $libDir -ErrorAction Stop; Write-Host '[bootstrap-stage2] Copied support DLL to target lib.' } catch { Write-Warning "[bootstrap-stage2] Failed to copy support DLL: $($_.Exception.Message)" }
    } else {
      Write-Host '[bootstrap-stage2] Target support DLL already present; not copying.'
    }
  } else {
    Write-Warning '[bootstrap-stage2] No support DLL found to reuse or copy.'
  }
}

# Update the launcher to point to the final app dir instead of bootstrap-build
$launcher = Join-Path $repoRoot 'build/exec/idris2.ps1'
$appDir = $targetDir
$launcherContent = @"
`$ErrorActionPreference = 'Stop'
`$app = "$appDir"
`$bootstrapPrefix = "$bootstrapPrefix"
`$versionedPrefix = Join-Path `$bootstrapPrefix 'idris2-0.7.0'
`$env:PATH = "`$app/lib;`$app;`$env:PATH"
`$env:LD_LIBRARY_PATH = "`$app/lib;`$app;`$env:LD_LIBRARY_PATH"
`$env:DYLD_LIBRARY_PATH = "`$app/lib;`$app;`$env:DYLD_LIBRARY_PATH"
# Ensure runtime finds installed libs and support data by default
`$env:IDRIS2_PREFIX = `$bootstrapPrefix
`$env:IDRIS2_DATA = (Join-Path `$versionedPrefix 'support')
`$exe = Join-Path `$app 'idris2-boot.exe'
`$rkt = Join-Path `$app 'idris2-boot.rkt'
if (Test-Path `$exe) {
  Write-Host '[idris2.ps1 stage2] Using compiled idris2-boot.exe'
  & `$exe @args
} elseif (Test-Path `$rkt) {
  Write-Warning '[idris2.ps1 stage2] idris2-boot.exe missing, falling back to racket'
  racket `$rkt @args
} else {
  Write-Error 'Neither idris2-boot.exe nor idris2-boot.rkt found.'
}
"@
$launcherContent | Set-Content -Encoding ASCII -Path $launcher

# 2) Build and install libs needed for idris2
$env:IDRIS2_PREFIX = $bootstrapPrefix
$env:IDRIS2_PATH = ""

# Ensure support data is available under the versioned yprefix for runtime lookup
$supportDataRoot = Join-Path $repoRoot 'support'
$destSupport = Join-Path $versionedPrefix 'support'
[System.IO.Directory]::CreateDirectory($destSupport) | Out-Null
if (Test-Path $supportDataRoot) {
  foreach ($dir in @('racket','chez','gambit','js','refc')) {
    $src = Join-Path $supportDataRoot $dir
    if (Test-Path $src) {
      $dst = Join-Path $destSupport $dir
      [System.IO.Directory]::CreateDirectory($dst) | Out-Null
      Copy-Item -Recurse -Force "$src/*" $dst -ErrorAction SilentlyContinue
    }
  }
}

# helper function to call make-equivalent in subdir
function Build-Lib($lib, $exe) {
  Push-Location (Join-Path $repoRoot "libs/$lib")
  try {
    $ipkg = Get-ChildItem -Filter '*.ipkg' | Select-Object -First 1
    if (-not $ipkg) { throw "No .ipkg found in libs/$lib" }
    Write-Host "Building $lib with $exe"
    & $exe --build $ipkg.FullName 2>&1 | Out-Host
  }
  finally { Pop-Location }
}

# Rely on Idris installer to create install directories via its runtime
function Ensure-InstallDirs {
  param([string]$lib)
  # Ensure the install root and TTC-versioned directory exist, so copies won't fail
  $installRoot = Join-Path $versionedPrefix ("$lib-0.7.0")
  [void][System.IO.Directory]::CreateDirectory($installRoot)
  if ($ttcVersion) {
    $ttcDir = Join-Path $installRoot ("$ttcVersion")
    [void][System.IO.Directory]::CreateDirectory($ttcDir)
    # Also mirror subdirectories from the source TTC tree so nested copies succeed
    $srcTtcRoot = Join-Path (Join-Path $repoRoot "libs/$lib/build/ttc") ("$ttcVersion")
    if (Test-Path $srcTtcRoot) {
      Get-ChildItem -Path $srcTtcRoot -Recurse -Directory | ForEach-Object {
        $rel = ($_.FullName.Substring($srcTtcRoot.Length)) -replace '^[\\/]+',''
        $dst = if ([string]::IsNullOrEmpty($rel)) { $ttcDir } else { Join-Path $ttcDir $rel }
        [void][System.IO.Directory]::CreateDirectory($dst)
      }
      # Copy entire TTC tree (files and folders)
      Copy-Item -Path (Join-Path $srcTtcRoot '*') -Destination $ttcDir -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
}

# No TTC pre-creation for the app; rely on Idris to create build/ttc on demand
function Ensure-AppTTCDirs {
  # Pre-create the TTC build tree for compiler sources to avoid mkdir issues on Windows
  $ttcBuildRoot = Join-Path (Join-Path $repoRoot 'build/ttc') ("$ttcVersion")
  [void][System.IO.Directory]::CreateDirectory($ttcBuildRoot)
  $srcRoot = Join-Path $repoRoot 'src'
  if (Test-Path $srcRoot) {
    # Mirror only directories, preserving relative structure under build/ttc/<ver>
    Get-ChildItem -Path $srcRoot -Recurse -Directory | ForEach-Object {
      $rel = ($_.FullName.Substring($srcRoot.Length)) -replace '^[\\/]+',''
      if (-not [string]::IsNullOrWhiteSpace($rel)) {
        $dst = Join-Path $ttcBuildRoot $rel
        [void][System.IO.Directory]::CreateDirectory($dst)
      }
    }
  }
}

# Pre-create TTC build directories for a given library
function Ensure-LibTTCDirs {
  param([string]$lib)
  $libRoot = Join-Path $repoRoot "libs/$lib"
  $ttcBuildVer = Join-Path $libRoot ("build/ttc/$ttcVersion")
  [void][System.IO.Directory]::CreateDirectory($ttcBuildVer)
  if (Test-Path $libRoot) {
    # Mirror directory structure to avoid nested mkdir issues during TTC writes
    Get-ChildItem -Path $libRoot -Recurse -Directory -ErrorAction SilentlyContinue |
      Where-Object { $_.FullName -notmatch "\\build(\\|$)" } | ForEach-Object {
        $rel = ($_.FullName.Substring($libRoot.Length)) -replace '^[\\/]+',''
        if (-not [string]::IsNullOrWhiteSpace($rel)) {
          $dst = Join-Path $ttcBuildVer $rel
          [void][System.IO.Directory]::CreateDirectory($dst)
        }
      }
  }
}

$libsForIdris2 = @('prelude', 'base', 'linear', 'network', 'contrib')

foreach ($lib in $libsForIdris2) {
  # Always build before install to ensure TTCs exist
  Ensure-LibTTCDirs $lib
  Build-Lib $lib $env:IDRIS2_BOOT
  # Ensure install destination exists (Idris may not create it on Windows)
  Ensure-InstallDirs $lib
  Write-Host "Installing $lib"
  $ipkgPath = (Join-Path $repoRoot "libs/$lib/$lib.ipkg")
  & $env:IDRIS2_BOOT --install $ipkgPath 2>&1 | Out-Host
  # Add library root (not versioned folder) to IDRIS2_PATH
  $installRoot = "$bootstrapPrefix/idris2-0.7.0/$lib-0.7.0"
  $env:IDRIS2_PATH = ($env:IDRIS2_PATH + ";$installRoot").Trim(';')
}

# 3) Build Idris2 app
Write-Host "Building idris2"
Write-Host '[bootstrap-stage2][diag] DLL state before app build:'
Get-Item -ErrorAction SilentlyContinue `
  (Join-Path $targetDir 'libidris2_support.dll'), `
  (Join-Path $libDir 'libidris2_support.dll'), `
  $bootstrapDll | ForEach-Object {
    if ($_){
      Write-Host ("[bootstrap-stage2][diag] {0} {1} bytes {2}" -f $_.FullName,$_.Length,$_.LastWriteTime)
    }
  }
Ensure-AppTTCDirs
& $env:IDRIS2_BOOT --build (Join-Path $repoRoot 'idris2.ipkg') 2>&1 | Out-Host

$targetExe = Join-Path $repoRoot 'build/exec/idris2.ps1'

# Build and install the rest of the libs
$restLibs = @('test', 'papers')

foreach ($lib in $restLibs) {
  Ensure-LibTTCDirs $lib
  Build-Lib $lib $targetExe
  $ipkgPath = (Join-Path $repoRoot "libs/$lib/$lib.ipkg")
  Ensure-InstallDirs $lib
  & $targetExe --install $ipkgPath
}

Write-Host 'bootstrap stage 2 complete'