param(
  [Parameter(Mandatory=$true)][string]$Prefix,
  [Parameter(Mandatory=$true)][string]$Version
)

$ErrorActionPreference = 'Stop'

# Resolve repository root (script lives in tools/)
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

# Layout paths
$binDir  = Join-Path $Prefix 'bin'
$appDir  = Join-Path $binDir 'idris2_app'
$libDir  = Join-Path $Prefix 'lib'
$libRoot = Join-Path $libDir ("idris2-" + $Version)

# Ensure destination directories exist
New-Item -ItemType Directory -Force -Path $Prefix  | Out-Null
New-Item -ItemType Directory -Force -Path $binDir  | Out-Null
New-Item -ItemType Directory -Force -Path $appDir  | Out-Null
New-Item -ItemType Directory -Force -Path $libDir  | Out-Null

# Generate launcher content (filled with placeholders for later substitution)
${launcherContent} = @'
$ErrorActionPreference = "Stop"
$app = Join-Path $PSScriptRoot 'idris2_app'
# Ensure runtime can locate support DLL and executables
$env:PATH = "$app\lib;$app;$env:PATH"
$env:LD_LIBRARY_PATH = "$app\lib;$app;$env:LD_LIBRARY_PATH"
$env:DYLD_LIBRARY_PATH = "$app\lib;$app;$env:DYLD_LIBRARY_PATH"

# Derive paths
$versionedLibRoot = "__LIB_ROOT__"            # e.g. C:\Idris2\lib\idris2-0.7.0
$prefixLib = Split-Path $versionedLibRoot -Parent # e.g. C:\Idris2\lib

# Normalize to forward slashes which Idris path logic handles uniformly
function Normalize([string]$p){ return ($p -replace '\\','/') }
$normVersioned = Normalize $versionedLibRoot
$normPrefixLib = Normalize $prefixLib

# Set Idris environment variables:
# IDRIS2_PREFIX should point at directory whose children include idris2-<ver>
$env:IDRIS2_PREFIX = $normPrefixLib
$env:IDRIS2_DATA   = (Join-Path $versionedLibRoot 'support')

# Establish search paths for packages/imports (versioned directory)
$env:IDRIS2_PATH = $normVersioned
$env:IDRIS2_PACKAGE_PATH = $normVersioned

$env:RACKET = "racket"
$env:RACKET_RACO = "raco"

# Parse only --repl-input (REPL output redirection handled internally)
$argList = New-Object System.Collections.Generic.List[string]
$argList.AddRange([string[]]$args)
$replInput = $null
$i = 0
while ($i -lt $argList.Count) {
  $a = $argList[$i]
  if ($a -eq '--repl-input' -and ($i + 1) -lt $argList.Count) {
    $replInput = $argList[$i + 1]
    $argList.RemoveAt($i); $argList.RemoveAt($i)
    continue
  }
  if ($a -like '--repl-input=*') {
    $replInput = $a.Substring($a.IndexOf('=') + 1)
    $argList.RemoveAt($i)
    continue
  }
  $i++
}

# Prefer final self-hosted idris2.exe if present, else fall back to bootstrap
$exe = Join-Path $app 'idris2.exe'
if (-not (Test-Path $exe)) { $exe = Join-Path $app 'idris2-boot.exe' }
if ($replInput) {
  Start-Process -FilePath $exe -ArgumentList $argList -NoNewWindow -Wait -RedirectStandardInput $replInput | Out-Null
} else {
  & $exe @argList
}
'@

# Substitute prefix placeholders (avoid escaping storm inside here-string)
$launcherContent = $launcherContent.Replace('__LIB_ROOT__', $libRoot).Replace('__PREFIX__', $Prefix)

# Write launcher script
$launcherPath = Join-Path $binDir 'idris2.ps1'
Set-Content -Encoding UTF8 -Force -Path $launcherPath -Value $launcherContent
Write-Host "[Idris2] Launcher written: $launcherPath"

# Copy support DLL into installed app dir
# On Windows the DLL may already be loaded/locked if an earlier build invoked idris2-boot
# so we try a safe copy strategy: if direct overwrite fails, copy to a temp name and schedule rename.
$dllCandidates = @(
  (Join-Path $repoRoot 'build-cmake/support/c/Release/libidris2_support.dll'),
  (Join-Path $repoRoot 'support/c/build/Release/libidris2_support.dll')
)
$copied = $false
foreach ($dll in $dllCandidates) {
  if (Test-Path $dll) {
    $target = Join-Path $appDir 'libidris2_support.dll'
    try {
      Write-Host "[Idris2] Copying support DLL: $dll -> $target"
      Copy-Item -Force $dll $target -ErrorAction Stop
      $copied = $true
      break
    }
    catch {
      Write-Warning "[Idris2] Direct copy failed (likely locked): $($_.Exception.Message)"
      $tempTarget = Join-Path $appDir ('libidris2_support.new.' + [guid]::NewGuid().ToString() + '.dll')
      try {
        Copy-Item $dll $tempTarget -ErrorAction Stop
        Write-Host "[Idris2] Copied support DLL to temp file: $tempTarget"
        # Attempt an in-place rename swap if original not writable
        try {
          if (Test-Path $target) { Rename-Item -Path $target -NewName ('libidris2_support.old.' + [guid]::NewGuid().ToString() + '.dll') -ErrorAction SilentlyContinue }
          Rename-Item -Path $tempTarget -NewName 'libidris2_support.dll' -ErrorAction SilentlyContinue
          if (Test-Path $target) {
            Write-Host '[Idris2] Support DLL updated via rename swap.'
            $copied = $true
            break
          } else {
            Write-Warning '[Idris2] Could not replace in-use support DLL; leaving temp copy.'
            $copied = $true
            break
          }
        }
        catch {
          Write-Warning "[Idris2] Rename swap failed: $($_.Exception.Message)"
        }
      }
      catch {
        Write-Warning "[Idris2] Failed to copy support DLL even to temp name: $($_.Exception.Message)"
      }
    }
  }
}
if (-not $copied) { Write-Warning '[Idris2] libidris2_support.dll not found in expected locations; idris may fail at runtime.' }

<#
 Build the bootstrap executable with Racket if the source exists.
 We expect idris2-boot.rkt to have been produced by the build in one of the
 candidate build trees. Copy it first, then run raco which will emit idris2-boot.exe.
#>

$bootRktCandidates = @(
  (Join-Path $repoRoot 'build-cmake\exec\idris2_app\idris2-boot.rkt'),
  (Join-Path $repoRoot 'build\exec\idris2_app\idris2-boot.rkt')
)
foreach ($c in $bootRktCandidates) {
  if (Test-Path $c) {
    Copy-Item -Force $c (Join-Path $appDir 'idris2-boot.rkt')
    break
  }
}
if (Test-Path (Join-Path $appDir 'idris2-boot.rkt')) {
  Push-Location $appDir
  try {
    Write-Host "[Idris2] Building idris2-boot.exe (raco exe)..."
    raco exe 'idris2-boot.rkt'
  }
  finally {
    Pop-Location
  }
} else {
  Write-Warning '[Idris2] idris2-boot.rkt not found; skipping raco exe build.'
}

  # Copy final stage idris2.exe / idris2.rkt from build tree if available
  $finalExeSrc = Join-Path $repoRoot 'build-cmake\exec\idris2_app\idris2.exe'
  if (-not (Test-Path $finalExeSrc)) {
    $finalExeSrc = Join-Path $repoRoot 'build\exec\idris2_app\idris2.exe'
  }
  if (Test-Path $finalExeSrc) {
    Write-Host "[Idris2] Installing final idris2.exe -> $appDir"
    Copy-Item -Force $finalExeSrc (Join-Path $appDir 'idris2.exe')
  }
  $finalRktSrc = Join-Path $repoRoot 'build-cmake\exec\idris2_app\idris2.rkt'
  if (-not (Test-Path $finalRktSrc)) {
    $finalRktSrc = Join-Path $repoRoot 'build\exec\idris2_app\idris2.rkt'
  }
  if (Test-Path $finalRktSrc) {
    Write-Host "[Idris2] Installing final idris2.rkt -> $appDir"
    Copy-Item -Force $finalRktSrc (Join-Path $appDir 'idris2.rkt')
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
