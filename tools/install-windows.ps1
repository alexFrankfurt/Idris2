param(
  [Parameter(Mandatory=$true)][string]$Prefix,
  [Parameter(Mandatory=$true)][string]$Version
$launcherContent = @'
$ErrorActionPreference = "Stop"
$app = Join-Path $PSScriptRoot 'idris2_app'
# Rely on Idris to create build and ttc directories on demand
$env:PATH = "$app\lib;$app;$env:PATH"
$env:LD_LIBRARY_PATH = "$app\lib;$app;$env:LD_LIBRARY_PATH"
$env:DYLD_LIBRARY_PATH = "$app\lib;$app;$env:DYLD_LIBRARY_PATH"
$env:IDRIS2_LIB_DIR = "__LIB_ROOT__"
$env:IDRIS2_PREFIX = "__PREFIX__"
$env:IDRIS2_DATA = (Join-Path "__LIB_ROOT__" 'support')
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
`$replInput = $null
`$i = 0
`while (`$i -lt `$argList.Count) {
`  `$a = `$argList[`$i]
`  if (`$a -eq '--repl-input' -and (`$i + 1) -lt `$argList.Count) {
`    `$replInput = `$argList[`$i + 1]
`    `$argList.RemoveAt(`$i); `$argList.RemoveAt(`$i)
`    continue
`  }
`  if (`$a -like '--repl-input=*') {
`    `$replInput = `$a.Substring(`$a.IndexOf('=') + 1)
`    `$argList.RemoveAt(`$i)
`    continue
`  }
`  `$i++
`}
`# Prefer final self-hosted idris2.exe if present, else fall back to bootstrap
`$exe = Join-Path `$app 'idris2.exe'
`if (-not (Test-Path `$exe)) { `$exe = Join-Path `$app 'idris2-boot.exe' }
`if (`$replInput) {
`  Start-Process -FilePath `$exe -ArgumentList `$argList -NoNewWindow -Wait -RedirectStandardInput `$replInput | Out-Null
`}
`else {
`  & `$exe @argList
`}

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

  # Copy final stage idris2.exe / idris2.rkt from build tree if available
  $finalExeSrc = Join-Path $repoRoot 'build\exec\idris2_app\idris2.exe'
  if (Test-Path $finalExeSrc) {
    Write-Host "[Idris2] Installing final idris2.exe -> $appDir"
    Copy-Item -Force $finalExeSrc (Join-Path $appDir 'idris2.exe')
  }
  $finalRktSrc = Join-Path $repoRoot 'build\exec\idris2_app\idris2.rkt'
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
