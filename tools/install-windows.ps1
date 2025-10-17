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

# Ensure Chez runtime can locate boot libraries if backend outputs are present
$schemeCandidate = if ($env:SCHEME) { $env:SCHEME } else { 'scheme' }
$schemeInfo = $null
try { $schemeInfo = Get-Command $schemeCandidate -ErrorAction Stop } catch {}
$schemeCommand = if ($schemeInfo) {
  if ($schemeInfo.Source) { $schemeInfo.Source } else { $schemeInfo.Path }
} else {
  $schemeCandidate
}
if ($schemeInfo) {
  $schemeDir = Split-Path $schemeCommand -Parent
  $schemeArch = Split-Path $schemeDir -Leaf
  $schemeBin = Split-Path $schemeDir -Parent
  $schemeRoot = Split-Path $schemeBin -Parent
  $defaultBoot = Join-Path (Join-Path $schemeRoot 'boot') $schemeArch
  if ((-not $env:CHEZSCHEMELIBDIRS) -and (Test-Path $defaultBoot)) {
    $env:CHEZSCHEMELIBDIRS = $defaultBoot
  }
  elseif ($env:CHEZSCHEMELIBDIRS -and (Test-Path $defaultBoot)) {
    $paths = $env:CHEZSCHEMELIBDIRS -split ';'
    if (-not ($paths | Where-Object { $_ -eq $defaultBoot })) {
      $env:CHEZSCHEMELIBDIRS = "$defaultBoot;$env:CHEZSCHEMELIBDIRS"
    }
  }
} else {
  $schemeDir = $null
  $schemeArch = $null
}
if (Test-Path (Join-Path $app 'Program.boot')) {
  if ($env:CHEZSCHEMELIBDIRS) {
    $paths = $env:CHEZSCHEMELIBDIRS -split ';'
    if (-not ($paths | Where-Object { $_ -eq $app })) {
      $env:CHEZSCHEMELIBDIRS = "$app;$env:CHEZSCHEMELIBDIRS"
    }
  } else {
    $env:CHEZSCHEMELIBDIRS = $app
  }
}

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

# Decide launch target based on available artefacts
$argArray = [string[]]$argList.ToArray()
$cmdPath = $null
$cmdArgs = @()

$exe       = Join-Path $app 'idris2.exe'
$bootExe   = Join-Path $app 'idris2-boot.exe'
$chezSo    = Join-Path $app 'idris2.so'
$chezSs    = Join-Path $app 'idris2.ss'
$bootSo    = Join-Path $app 'idris2-boot.so'
$bootSs    = Join-Path $app 'idris2-boot.ss'
$finalRkt  = Join-Path $app 'idris2.rkt'
$bootRkt   = Join-Path $app 'idris2-boot.rkt'

if (Test-Path $exe) {
  $cmdPath = $exe
  $cmdArgs = $argArray
} elseif (Test-Path $chezSo) {
  if (-not $schemeInfo) { throw 'Chez backend artefacts present but no scheme executable was found. Set SCHEME or ensure scheme.exe is on PATH.' }
  $cmdPath = $schemeCommand
  $cmdArgs = @('--script', $chezSo) + $argArray
} elseif (Test-Path $chezSs) {
  if (-not $schemeInfo) { throw 'Chez backend artefacts present but no scheme executable was found. Set SCHEME or ensure scheme.exe is on PATH.' }
  $cmdPath = $schemeCommand
  $cmdArgs = @('--script', $chezSs) + $argArray
} elseif (Test-Path $bootSo) {
  if (-not $schemeInfo) { throw 'Chez bootstrap artefacts present but no scheme executable was found. Set SCHEME or ensure scheme.exe is on PATH.' }
  $cmdPath = $schemeCommand
  $cmdArgs = @('--script', $bootSo) + $argArray
} elseif (Test-Path $bootSs) {
  if (-not $schemeInfo) { throw 'Chez bootstrap artefacts present but no scheme executable was found. Set SCHEME or ensure scheme.exe is on PATH.' }
  $cmdPath = $schemeCommand
  $cmdArgs = @('--script', $bootSs) + $argArray
} elseif (Test-Path $bootExe) {
  $cmdPath = $bootExe
  $cmdArgs = $argArray
} elseif (Test-Path $finalRkt) {
  $racketCmd = if ($env:RACKET) { $env:RACKET } else { 'racket' }
  $cmdPath = $racketCmd
  $cmdArgs = @($finalRkt) + $argArray
} elseif (Test-Path $bootRkt) {
  $racketCmd = if ($env:RACKET) { $env:RACKET } else { 'racket' }
  $cmdPath = $racketCmd
  $cmdArgs = @($bootRkt) + $argArray
}

if (-not $cmdPath) {
  throw 'No Idris2 runtime found (expected idris2.exe, idris2.so/.ss, idris2-boot.*, or idris2.rkt).'
}

if ($replInput) {
  Start-Process -FilePath $cmdPath -ArgumentList $cmdArgs -NoNewWindow -Wait -RedirectStandardInput $replInput | Out-Null
} else {
  & $cmdPath @cmdArgs
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
  $emitCandidates = @(
    @{ src = 'build-cmake\exec\idris2_app\idris2.exe'; dest = 'idris2.exe'; kind = 'final idris2.exe' },
    @{ src = 'build\exec\idris2_app\idris2.exe'; dest = 'idris2.exe'; kind = 'final idris2.exe' },
    @{ src = 'build-cmake\exec\idris2_app\idris2.rkt'; dest = 'idris2.rkt'; kind = 'final idris2.rkt' },
    @{ src = 'build\exec\idris2_app\idris2.rkt'; dest = 'idris2.rkt'; kind = 'final idris2.rkt' },
    @{ src = 'build-cmake\exec\idris2_app\idris2.so'; dest = 'idris2.so'; kind = 'final idris2.so' },
    @{ src = 'build\exec\idris2_app\idris2.so'; dest = 'idris2.so'; kind = 'final idris2.so' },
    @{ src = 'build-cmake\exec\idris2_app\idris2.ss'; dest = 'idris2.ss'; kind = 'final idris2.ss' },
    @{ src = 'build\exec\idris2_app\idris2.ss'; dest = 'idris2.ss'; kind = 'final idris2.ss' },
    @{ src = 'build-cmake\exec\idris2_app\idris2-boot.so'; dest = 'idris2-boot.so'; kind = 'bootstrap idris2-boot.so' },
    @{ src = 'build\exec\idris2_app\idris2-boot.so'; dest = 'idris2-boot.so'; kind = 'bootstrap idris2-boot.so' },
    @{ src = 'build-cmake\exec\idris2_app\idris2-boot.ss'; dest = 'idris2-boot.ss'; kind = 'bootstrap idris2-boot.ss' },
    @{ src = 'build\exec\idris2_app\idris2-boot.ss'; dest = 'idris2-boot.ss'; kind = 'bootstrap idris2-boot.ss' }
  )
  $seenDest = @{}
  foreach ($entry in $emitCandidates) {
    $src = Join-Path $repoRoot $entry.src
    $destPath = Join-Path $appDir $entry.dest
  if ((Test-Path $src) -and -not $seenDest.ContainsKey($entry.dest)) {
      Write-Host "[Idris2] Installing $($entry.kind) -> $destPath"
      Copy-Item -Force $src $destPath
      $seenDest[$entry.dest] = $true
    }
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
