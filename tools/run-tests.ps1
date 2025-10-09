param(
  [ValidateSet('Debug','Release','RelWithDebInfo','MinSizeRel')]
  [string]$Config = 'Release',
  # -Only may be a single regex string or an array of shorthand tokens (e.g. @('001','002')).
  [Parameter(ValueFromPipeline=$false)]
  [Object]$Only,
  [string]$Except,
  [string]$Idris,
  [switch]$ListOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Normalise the user-supplied --only selector:
#  * If it's an array of tokens (e.g. numbers or partial names), expand them to full test path regex parts.
#  * If it's a single string, just clean path separators.
function Expand-OnlySelector([Object]$sel) {
  if (-not $sel) { return $null }
  if ($sel -is [System.Array]) {
    $tokens = @()
    foreach ($t in $sel) {
      if (-not $t) { continue }
      $tok = ($t.ToString().Trim())
      if (-not $tok) { continue }
      # Heuristic: if token is purely digits, match any test whose leaf directory ends with that number
      if ($tok -match '^\d+$') {
        # Build pattern like idris2/.*/basic0*<tok>$ OR allow anywhere: use trailing directory name match
        $tokens += "${tok}$"
      } else {
        # General substring fallback
        $tokens += [Regex]::Escape($tok)
      }
    }
    if ($tokens.Count -eq 0) { return $null }
    # Join tokens with '|' ensuring they don't accidentally introduce path backslashes
    return ($tokens -join '|')
  } else {
    return ($sel.ToString() -replace '\\','/').Trim()
  }
}

$Only = Expand-OnlySelector $Only
if ($Only) {
  Write-Host "[Tests] --only selector pattern: $Only"
}

# Always operate from repo root (parent of script's folder)
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

# Ensure Unix tools (sh, tr, etc.) are available via Git for Windows
function Initialize-UnixTools {
  if (Get-Command sh -ErrorAction SilentlyContinue) { return }
  $candidates = @()
  if ($env:ProgramFiles) {
    $candidates += @(
      (Join-Path $env:ProgramFiles 'Git\usr\bin'),
      (Join-Path $env:ProgramFiles 'Git\bin'),
      (Join-Path $env:ProgramFiles 'Git\mingw64\bin')
    )
  }
  if (${env:ProgramFiles(x86)}) {
    $candidates += @(
      (Join-Path ${env:ProgramFiles(x86)} 'Git\\usr\\bin'),
      (Join-Path ${env:ProgramFiles(x86)} 'Git\\bin')
    )
  }
  foreach ($dir in $candidates) {
    $sh = Join-Path $dir 'sh.exe'
    if (Test-Path $sh) {
      # Prepend so our process can find sh, tr, etc.
      $env:Path = "$dir;$env:Path"
      Write-Host "[Tests] Added Unix tools to PATH: $dir"
      return
    }
  }
  if (-not (Get-Command sh -ErrorAction SilentlyContinue)) {
    throw "Required Unix tools not found (sh). Please install Git for Windows and ensure its 'usr\\bin' is on PATH."
  }
}

Initialize-UnixTools

# Work around Racket test runner expecting a string path for IDRIS2_REPL_OUTPUT:
# If this variable leaks in from prior invocations (e.g. via --repl-output usage
# elsewhere) its raw pointer value can cause a contract violation when the
# Racket backend tries to open it as a file. Ensure it is unset.
Remove-Item Env:IDRIS2_REPL_OUTPUT -ErrorAction SilentlyContinue

Write-Host "[Tests] Building test binaries"

# Convert Windows path (e.g., D:\a\b) to POSIX (/d/a/b) for sh
function Convert-ToPosixPath([string]$p) {
  if (-not $p) { return $p }
  $pp = $p -replace '\\','/'
  if ($pp -match '^[A-Za-z]:') {
    $drive = $pp.Substring(0,1).ToLower()
    $pp = "/$drive/" + $pp.Substring(3)
  }
  return $pp
}

  # Minimal env for package resolution and support DLLs
  function Initialize-IdrisEnv {
    param([string]$Config)

    # Prefer bootstrap-build/idris2-*/ as package path
    $pkgRoot = $null
    $bb = Join-Path $repoRoot 'bootstrap-build'
    if (Test-Path $bb) {
      $cand = Get-ChildItem -LiteralPath $bb -Directory -Filter 'idris2-*' | Sort-Object Name -Descending | Select-Object -First 1
      if ($cand) { $pkgRoot = $cand.FullName }
    }
    # Always include repo libs so deps (prelude/base/contrib) can be built with current compiler
    $repoLibs = Join-Path $repoRoot 'libs'
    $pkgPaths = @()
  if ($repoLibs) { $pkgPaths += $repoLibs }
  if ($pkgRoot)  { $pkgPaths += $pkgRoot }
  if ($env:IDRIS2_PACKAGE_PATH) { $pkgPaths += $env:IDRIS2_PACKAGE_PATH }
  if ($pkgPaths.Count -gt 0) { $env:IDRIS2_PACKAGE_PATH = ($pkgPaths -join ';') }

    # Mirror testutils.sh hygiene env: install into tests/prefix/<NAME_VERSION>
    if ($pkgRoot) {
      $nameVersion = Split-Path -Leaf $pkgRoot
      if ($nameVersion) { $env:NAME_VERSION = $nameVersion }
      $testsPrefix = Join-Path $repoRoot 'tests/prefix'
      $oldPP = Join-Path $pkgRoot $nameVersion
      $newPP = Join-Path $testsPrefix $nameVersion
      # Ensure prefix directories exist
      New-Item -ItemType Directory -Force -Path (Join-Path $testsPrefix $nameVersion) | Out-Null
      # Where to install new stuff
      $env:IDRIS2_PREFIX = $testsPrefix
      # Where to look
      # IMPORTANT: include the repo 'libs' directory FIRST so freshly built packages
      # (notably the 'test' package containing updated Test.Golden) shadow any
      # previously installed copies under the bootstrap/prefix locations.
      if ($repoLibs) {
        $env:IDRIS2_PACKAGE_PATH = "$repoLibs;$newPP"
      } else {
        $env:IDRIS2_PACKAGE_PATH = "$newPP"
      }
      # If a final exe exists, deliberately drop the bootstrap-installed tree ($oldPP)
      $finalExe = Join-Path $repoRoot 'build/exec/idris2_app/idris2.exe'
      if (Test-Path $finalExe) {
        # Ensure no accidental reintroduction of $oldPP
        $env:IDRIS2_PACKAGE_PATH = ($env:IDRIS2_PACKAGE_PATH -split ';' | Where-Object { $_ -ne $oldPP }) -join ';'
      } else {
        # During early bootstrap fallback keep old path for compatibility
        $env:IDRIS2_PACKAGE_PATH = "$env:IDRIS2_PACKAGE_PATH;$oldPP"
      }
      Write-Host "[Tests] IDRIS2_PACKAGE_PATH=$($env:IDRIS2_PACKAGE_PATH)"
      # Support and libs
      if ($env:TEST_IDRIS2_LIBS) {
        $env:IDRIS2_LIBS = "$oldPP/lib;$newPP/lib;$env:TEST_IDRIS2_LIBS"
      } else {
        $env:IDRIS2_LIBS = "$oldPP/lib;$newPP/lib"
      }
      if ($env:TEST_IDRIS2_DATA) {
        $env:IDRIS2_DATA = "$oldPP/support;$newPP/support;$env:TEST_IDRIS2_DATA"
      } else {
        $env:IDRIS2_DATA = "$oldPP/support;$newPP/support"
      }
    }

    # Find libidris2_support.dll and put its directory on PATH and TEST_IDRIS2_LIBS
    $dllDir = $null
    $dllCandidates = @(
      (Join-Path $repoRoot "build-cmake/support/$Config"),
      (Join-Path $repoRoot "build-cmake/support/c/$Config"),
      (Join-Path $repoRoot "support/c/build/$Config")
    )
    foreach ($dir in $dllCandidates) {
      $dll = Join-Path $dir 'libidris2_support.dll'
      if (Test-Path $dll) { $dllDir = $dir; break }
    }
    if (-not $dllDir) {
      # Last resort: search shallowly under build-cmake
      $dll = Get-ChildItem -Path (Join-Path $repoRoot 'build-cmake') -Recurse -Filter 'libidris2_support.dll' -ErrorAction SilentlyContinue | Select-Object -First 1
      if ($dll) { $dllDir = $dll.DirectoryName }
    }
    if ($dllDir) {
      $env:Path = "$dllDir;$env:Path"
      $env:TEST_IDRIS2_LIBS = $dllDir
    }
  }

  Initialize-IdrisEnv -Config $Config

# Ensure the standard libraries are installed into the tests prefix when missing.
function Ensure-CoreLibsInstalled {
  param(
    [Parameter(Mandatory=$true)][string]$IdrisCmd,
    [Parameter(Mandatory=$true)][string]$Config
  )
  if (-not $env:NAME_VERSION) { return }
  $testsPrefix = Join-Path $repoRoot 'tests/prefix'
  $versionTag = ($env:NAME_VERSION -replace '^idris2-','')
  if (-not $versionTag) { return }
  $required = @('prelude','base','contrib','linear','network','test','papers')
  foreach ($lib in $required) {
    $targetDir = Join-Path (Join-Path $testsPrefix $env:NAME_VERSION) ("$lib-$versionTag")
    if (Test-Path $targetDir) { continue }
    # If already installed under bootstrap-build, mirror rather than reinstall to save time
    $bootstrapLibRoot = Join-Path (Join-Path $repoRoot 'bootstrap-build') $env:NAME_VERSION
    $bootstrapLibDir  = Join-Path $bootstrapLibRoot ("$lib-$versionTag")
    if (Test-Path $bootstrapLibDir) {
      try {
        Write-Host "[Tests] Mirroring existing bootstrap lib: $lib" -ForegroundColor DarkCyan
        New-Item -ItemType Directory -Force -Path (Split-Path $targetDir) | Out-Null
        Copy-Item -Recurse -Force $bootstrapLibDir $targetDir
        continue
      } catch {
        Write-Warning ("[Tests] Failed to mirror bootstrap lib {0}: {1}" -f $lib, $_.Exception.Message)
        # Fall through to attempt a fresh install
      }
    }
    $ipkg = Join-Path (Join-Path $repoRoot "libs/$lib") ("$lib.ipkg")
    if (-not (Test-Path $ipkg)) { Write-Warning "[Tests] Missing ipkg for $lib ($ipkg)"; continue }
    Write-Host "[Tests] Installing missing core lib: $lib" -ForegroundColor Cyan
    try {
      & $IdrisCmd --install $ipkg | Write-Host
    }
    catch {
      Write-Warning ("[Tests] Failed to install {0}: {1}" -f $lib, $_.Exception.Message)
    }
  }
}

# Clean per-test stale artifacts (output files, temporary .tmpout, previous build/exec inside test cases)
function Invoke-TestCleanup {
  param([string]$OnlyPattern)
  $testsDir = Join-Path $repoRoot 'tests'
  if (-not (Test-Path $testsDir)) { return }
  # Resolve the subset of test directories we'll touch
  $targets = @()
  if ($OnlyPattern) {
    $targets = Get-ChildItem -Path $testsDir -Recurse -Directory -ErrorAction SilentlyContinue | Where-Object { $_.FullName -replace '\\','/' -match [Regex]::Escape($OnlyPattern) }
  } else {
    $targets = Get-ChildItem -Path $testsDir -Recurse -Directory -ErrorAction SilentlyContinue | Where-Object { Test-Path (Join-Path $_.FullName 'expected') }
  }
  foreach ($dir in $targets) {
    Get-ChildItem -Path $dir.FullName -Filter 'output' -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    Get-ChildItem -Path $dir.FullName -Filter '.tmpout-*' -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
  }
}

Invoke-TestCleanup -OnlyPattern $Only

# If -ListOnly was requested, enumerate matching test directories and exit before building the runner.
if ($ListOnly) {
  $testsDir = Join-Path $repoRoot 'tests'
  if (-not (Test-Path $testsDir)) { Write-Warning '[Tests] No tests directory found.'; exit 0 }
  $allTestDirs = Get-ChildItem -Path $testsDir -Recurse -Directory -ErrorAction SilentlyContinue |
    Where-Object { (Test-Path (Join-Path $_.FullName 'expected')) -or (Test-Path (Join-Path $_.FullName 'expected_ro')) }
  $normalized = $allTestDirs | ForEach-Object { $_.FullName -replace '\\','/' }
  if ($Only) {
    $regex = [Regex]::new($Only)
    $normalized = $normalized | Where-Object { $regex.IsMatch($_) }
  }
  if ($Except) {
    $ex = ($Except -replace '\\','/').Trim()
    if ($ex) {
      $exRegex = [Regex]::new($ex)
      $normalized = $normalized | Where-Object { -not ($exRegex.IsMatch($_)) }
    }
  }
  $relative = $normalized | ForEach-Object {
    $rel = $_.Substring($testsDir.Length)
    while ($rel.StartsWith('/') -or $rel.StartsWith('\')) { $rel = $rel.Substring(1) }
    $rel
  }
  Write-Host "[Tests] Listing matched tests (count=$($relative.Count)):" -ForegroundColor Cyan
  $relative | Sort-Object | ForEach-Object { Write-Host "  $_" }
  exit 0
}

# Locate local Idris launchers
$idrisSh = Join-Path $repoRoot 'build/exec/idris2'      # POSIX sh script for tests
$idrisPs1 = Join-Path $repoRoot 'build/exec/idris2.ps1'  # PowerShell launcher
$idrisCmd = Join-Path $repoRoot 'build/exec/idris2.cmd'  # CMD shim (preferred for building)
if ($Idris) {
  # Explicit override provided; use for both building and running
  $idrisLauncher = $Idris
  $idrisBuilder  = $Idris
} else {
  $localPreferred = if (Test-Path $idrisSh) { $idrisSh } elseif (Test-Path $idrisPs1) { $idrisPs1 } else { $null }
  if (-not $localPreferred) {
    Write-Host "[Tests] Local launcher not found, attempting stage2 bootstrap..."
    $stage2 = Join-Path $repoRoot 'bootstrap-stage2.ps1'
    if (-not (Test-Path $stage2)) { throw "Missing $stage2" }
    pwsh -NoProfile -ExecutionPolicy Bypass -File $stage2 -Config $Config
  }
  if ((Test-Path $idrisSh) -and (Test-Path $idrisPs1)) {
    # Prefer native exe for sh-based tests to avoid wrapper path issues
    $idrisExe = Join-Path $repoRoot 'build/exec/idris2_app/idris2.exe'
    if (Test-Path $idrisExe) {
      $idrisLauncher = Convert-ToPosixPath (Resolve-Path -LiteralPath $idrisExe)
    } else {
      $idrisLauncher = Convert-ToPosixPath (Resolve-Path -LiteralPath $idrisSh)
    }
    if (Test-Path $idrisCmd) {
      $idrisBuilder = (Resolve-Path -LiteralPath $idrisCmd)
    } else {
      $idrisBuilder = (Resolve-Path -LiteralPath $idrisPs1)
    }
  } elseif (Test-Path $idrisPs1) {
    # Fallback: build via ps1 and also pass ps1 to runtests (may fail for sh tests)
    $idrisLauncher = (Resolve-Path -LiteralPath $idrisPs1)
    $idrisBuilder  = $idrisLauncher
  } elseif (Test-Path $idrisSh) {
    $idrisExe = Join-Path $repoRoot 'build/exec/idris2_app/idris2.exe'
    if (Test-Path $idrisExe) {
      $idrisLauncher = Convert-ToPosixPath (Resolve-Path -LiteralPath $idrisExe)
    } else {
      $idrisLauncher = Convert-ToPosixPath (Resolve-Path -LiteralPath $idrisSh)
    }
    # Prefer cmd shim for building from PowerShell when ps1 is absent
    if (Test-Path $idrisCmd) {
      $idrisBuilder = (Resolve-Path -LiteralPath $idrisCmd)
    } else {
      # As a last resort try invoking the sh script directly (may fail on some setups)
      $idrisBuilder = (Resolve-Path -LiteralPath $idrisSh)
    }
  } else {
    $cmd = (Get-Command idris2.ps1 -ErrorAction SilentlyContinue)
    if (-not $cmd) { $cmd = (Get-Command idris2 -ErrorAction SilentlyContinue) }
    if ($cmd) {
      $idrisLauncher = $cmd.Source
      $idrisBuilder = $idrisLauncher
      Write-Host "[Tests] Using installed Idris2 launcher: $idrisLauncher"
    } else {
      throw "Idris2 launcher not found. Run: cmake --build .\\build-cmake --config $Config -t bootstrap-racket"
    }
  }
}

# Build the tests runner (ipkg or Main.idr fallback)
$testsRoot = Join-Path $repoRoot 'tests'
$ipkgCandidates = @('tests.ipkg','runtests.ipkg')
$ipkgName = $ipkgCandidates | Where-Object { Test-Path (Join-Path $testsRoot $_) } | Select-Object -First 1

Push-Location $testsRoot
try {
  if ($ipkgName) {
    & $idrisBuilder --build $ipkgName
  } elseif (Test-Path 'Main.idr') {
    & $idrisBuilder 'Main.idr' -o runtests
  } else {
    throw "No tests ipkg or Main.idr found under .\tests"
  }
  # After building the runner ensure its dependencies (standard libs) are installed
  Ensure-CoreLibsInstalled -IdrisCmd $idrisBuilder -Config $Config
} finally {
  Pop-Location
}

# Find the produced runtests launcher across common Windows forms (under tests)
$runnerBase = Join-Path $testsRoot 'build\exec\runtests'
$candidateRunners = @(
  "$runnerBase.exe", "$runnerBase.cmd", "$runnerBase.bat",
  "$runnerBase.ps1", $runnerBase
)
$runtests = $candidateRunners | Where-Object { Test-Path $_ } | Select-Object -First 1

# Fallback to racket if we have a script app
if (-not $runtests) {
  $rkt = Join-Path $testsRoot 'build\exec\runtests_app\runtests.rkt'
  if (Test-Path $rkt) {
    $runtests = 'racket'
    $runnerArgs = @($rkt)
  } else {
    throw "Test runner not found: $runnerBase"
  }
}

# Build argument list
$threads = 1
$rtArgs = @('--interactive', '--timing', '--failure-file', 'failures', '--threads', $threads)
if ($Only)   { $rtArgs += @('--only',   $Only) }
if ($Except) { $rtArgs += @('--except', $Except) }

Write-Host "[Tests] Running tests..."
# Run from tests root so relative directories (e.g. ttimp) resolve
Push-Location $testsRoot
try {
  if ($runtests -ieq 'racket') {
    # Ensure idris launcher is the first argument to the racket app
    & $runtests @runnerArgs $idrisLauncher @rtArgs
  } else {
    & $runtests $idrisLauncher @rtArgs
  }
} finally {
  Pop-Location
}

if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
