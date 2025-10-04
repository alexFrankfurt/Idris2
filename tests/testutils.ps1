param(
  [string]$Idris2
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-Idris2Path {
  param([string]$Override)
  if ($Override) { return $Override }
  $repoRoot = Split-Path -Parent $PSScriptRoot
  $ps1 = Join-Path $repoRoot 'build/exec/idris2.ps1'
  $cmd = Join-Path $repoRoot 'build/exec/idris2.cmd'
  if (Test-Path $ps1) { return (Resolve-Path -LiteralPath $ps1).Path }
  if (Test-Path $cmd) { return (Resolve-Path -LiteralPath $cmd).Path }
  $found = (Get-Command idris2.ps1 -ErrorAction SilentlyContinue)
  if (-not $found) { $found = (Get-Command idris2 -ErrorAction SilentlyContinue) }
  if ($found) { return $found.Source }
  throw "Idris2 launcher not found. Build stage2 or pass -Idris2 explicitly."
}

$script:IDRIS2 = Get-Idris2Path -Override $Idris2

function Invoke-Idris2 {
  param(
    [Parameter(Mandatory)] [string[]]$IdArgs,
    [string]$InputFile,
    [string]$OutputFile
  )
  if ($InputFile) {
    $content = Get-Content -Raw -Encoding UTF8 -LiteralPath $InputFile
    $out = $content | & $script:IDRIS2 @IdArgs 2>&1
  } else {
    $out = & $script:IDRIS2 @IdArgs 2>&1
  }
  if ($OutputFile) {
    # Normalize CRLF to LF for stability
    $text = ($out | Out-String).Replace("`r`n","`n")
    Set-Content -LiteralPath $OutputFile -Value $text -NoNewline -Encoding UTF8
  } else {
    $out
  }
}

function Check {
  param([Parameter(Mandatory)] [string[]]$Files)
  Invoke-Idris2 -IdArgs (@('--no-banner','--console-width','0','--no-color','--check') + $Files) | Out-Null
}

function Invoke-IdrisMain {
  param(
    [Parameter(Mandatory)] [string]$File,
    [string]$InputFile,
    [string]$OutputFile
  )
  Invoke-Idris2 -IdArgs @('--no-banner','--console-width','0','--no-color','--exec','main', $File) -InputFile $InputFile -OutputFile $OutputFile
}

function NormalizeText {
  param([string]$Text)
  if ($null -eq $Text) { return '' }
  return $Text.Replace("`r`n","`n")
}

function Compare-Expected {
  param(
    [Parameter(Mandatory)] [string]$ExpectedFile,
    [Parameter(Mandatory)] [string]$OutputFile
  )
  $exp = NormalizeText (Get-Content -Raw -Encoding UTF8 -LiteralPath $ExpectedFile)
  $out = NormalizeText (Get-Content -Raw -Encoding UTF8 -LiteralPath $OutputFile)
  if ($exp -ne $out) {
    Write-Host "Expected and output differ:" -ForegroundColor Yellow
    Write-Host "--- expected" -ForegroundColor DarkGray
    Write-Host "$exp"
    Write-Host "--- output" -ForegroundColor DarkGray
    Write-Host "$out"
    return $false
  }
  return $true
}
