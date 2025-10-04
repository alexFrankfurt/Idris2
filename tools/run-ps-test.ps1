Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Manual argument parsing to avoid param-block issues in some build shells
$TestDir = $null
$Idris2 = $null
for ($i = 0; $i -lt $args.Count; $i++) {
  switch -Regex ($args[$i]) {
    '^-TestDir$' { $i++; if ($i -ge $args.Count) { throw "-TestDir requires a value" } $TestDir = $args[$i]; continue }
    '^-Idris2$'  { $i++; if ($i -ge $args.Count) { throw "-Idris2 requires a value" }  $Idris2  = $args[$i]; continue }
    default { }
  }
}
if (-not $TestDir) { throw "Usage: run-ps-test.ps1 -TestDir <path> [-Idris2 <path>]" }

$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path $TestDir)) { throw "TestDir not found: $TestDir" }
Push-Location $TestDir
try {
  . (Join-Path $repoRoot 'tests/testutils.ps1') -Idris2 $Idris2

  function Get-RunScriptSpec {
    $res = @{ Args = @(); Input = $null }
    if (-not (Test-Path 'run')) { return $res }
    $lines = Get-Content -LiteralPath 'run' -Encoding UTF8
    foreach ($l in $lines) {
      $t = $l.Trim()
      if (-not $t) { continue }
      if ($t.StartsWith('. ')) { continue } # source testutils.sh
      if ($t -like 'idris2*') {
        # Simple tokenization adequate for common tests
        $tokens = [System.Text.RegularExpressions.Regex]::Split($t, '\s+')
        # Drop first token 'idris2'
        $tokens = $tokens | Select-Object -Skip 1
        $filtered = @()
        $i = 0
        while ($i -lt $tokens.Count) {
          $tok = $tokens[$i]
          if ($tok -eq '<') {
            $i++
            if ($i -lt $tokens.Count) { $res.Input = $tokens[$i] }
          } else {
            $filtered += $tok
          }
          $i++
        }
        $res.Args = $filtered
        break
      }
    }
    return $res
  }

  $runSpec = Get-RunScriptSpec
  $output = 'output'
  if ($runSpec.Args.Count -gt 0) {
    # Emulate `idris2 <args> < input` from sh script
    Invoke-Idris2 -IdArgs (@('--no-banner','--console-width','0','--no-color') + $runSpec.Args) -InputFile $runSpec.Input -OutputFile $output
  } else {
    # Fallback: run main if no run script present
    $idr = Get-ChildItem -LiteralPath . -Filter '*.idr' | Select-Object -First 1
    if (-not $idr) { throw "No .idr file found in $TestDir" }
    $stdinFile = if (Test-Path 'input') { 'input' } else { $null }
    Invoke-IdrisMain -File $idr.Name -InputFile $stdinFile -OutputFile $output
  }

  if (Test-Path 'expected') {
    if (-not (Compare-Expected -ExpectedFile 'expected' -OutputFile 'output')) {
      Write-Error "Test failed: $TestDir"
      exit 1
    }
  }
  Write-Host "PASS $TestDir"
} finally {
  Pop-Location
}
