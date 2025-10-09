# Running the Idris2 Test Suite (Windows-focused Fork)

This document summarizes all supported ways to run one, several, or all tests using the enhanced PowerShell harness (`tools/run-tests.ps1`). It also notes lower-level alternatives.

## Prerequisites

1. Configure & bootstrap:
   ```powershell
   cmake -S . -B build-cmake -D "IDRIS2_VERSION=0.7.0" -D "IDRIS2_CG=racket"
   cmake --build build-cmake --config Release -t bootstrap-racket
   ```
2. Ensure PowerShell 7+ (`pwsh`) and Git for Windows (for `sh`, `tr`, etc.) are available.

The script auto-installs any missing core libraries into a hygienic test prefix (`tests/prefix/<NAME_VERSION>`) on first run.

## Basic Invocation

Run the entire suite:
```powershell
pwsh -File .\tools\run-tests.ps1
```

Specify build config (defaults to Release):
```powershell
pwsh -File .\tools\run-tests.ps1 -Config Debug
```

## Selecting Tests

The `-Only` parameter accepts either:
- A single regex string (matched against normalised full test directory paths relative to `tests/`).
- An array of shorthand tokens (numbers or substrings) which are OR-joined into a single regex.

Examples:

Run all basic tests:
```powershell
pwsh -File .\tools\run-tests.ps1 -Only 'idris2/basic/'
```

Run exactly one test by full relative path:
```powershell
pwsh -File .\tools\run-tests.ps1 -Only 'idris2/basic/basic001'
```

Run two specific tests using array syntax:
```powershell
pwsh -File .\tools\run-tests.ps1 -Only @('idris2/basic/basic001','idris2/basic/basic004')
```

Run several by numeric suffix shorthand (pure digits treated as trailing directory match):
```powershell
pwsh -File .\tools\run-tests.ps1 -Only @('001','004')
```
Internally this builds a pattern similar to:
```
001$|004$
```

Regex example (range of basic tests 1–5 excluding 4):
```powershell
pwsh -File .\tools\run-tests.ps1 -Only 'idris2/basic/basic00[1-5]' -Except 'basic004'
```

Anchor to avoid accidental partial matches:
```powershell
pwsh -File .\tools\run-tests.ps1 -Only 'idris2/basic/basic001$'
```

## Listing Without Running

Use `-ListOnly` to show what would run (applies `-Only` / `-Except`) then exit:
```powershell
pwsh -File .\tools\run-tests.ps1 -Only @('001','004') -ListOnly
```
Output includes a count and the relative test directories.

## Excluding Tests

Use `-Except` with a regex to subtract matches after inclusion filtering:
```powershell
pwsh -File .\tools\run-tests.ps1 -Only 'idris2/basic/' -Except 'basic00(3|4)'
```

## Combining Array Tokens and Regex Anchors

Array tokens are escaped (except pure digits, which become simple trailing matches). If you need a token to carry regex meta characters, pass it as a single `-Only` string instead of part of the array.

## Dry-Run vs ListOnly

Currently only `-ListOnly` is implemented (no runner build). If you would like a true dry-run that *builds* the runner and enumerates what the test executable would run (useful if the runner itself filters), you can implement or request a `-DryRun` flag.

## Running Via CMake (All Tests)

If you prefer to use the CMake custom target (after stage2 build):
```powershell
cmake --build build-cmake --config Release -t test
```
(This invokes the test harness internally; for fine-grained selection prefer direct script usage.)

## Low-Level: Direct Runner Invocation

After the harness builds `tests/build/exec/runtests*` you can call it directly:
```powershell
# Example using the generated EXE and final idris2 executable
& .\tests\build\exec\runtests.exe .\build\exec\idris2_app\idris2.exe --only 'idris2/basic/basic001'
```
Flags available to the runner include (subject to upstream changes): `--only`, `--except`, `--threads`, `--failure-file`, `--interactive`, `--timing`.

## Golden Test Mechanics (Recap)

- Each test directory contains an `expected` (or preferred `expected_ro`) file.
- REPL transcript tests use the compiler with `--repl-input` & `--repl-output` to produce deterministic logs.
- `expected_ro` is chosen automatically over `expected` when present.
- Carriage returns are stripped before comparison for CRLF/LF neutrality.
- Per-test transient files (`output`, `.tmpout-*`) are cleaned before each run by the harness.

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|--------------|-----|
| Missing `contrib` / core lib | First run without libs installed | Harness should auto-install; rerun or inspect warnings |
| Test not selected | Regex mismatch / missing path anchor | Use `-ListOnly` to inspect pattern matches |
| Unexpected extra matches | Regex too broad | Anchor with `$` or refine pattern |
| Prelude not found | Misconfigured IDRIS2_PACKAGE_PATH / PREFIX | Re-run bootstrap or ensure harness environment precedence |
| Output diff with CR characters | Old expected file with CRLF vs normalized | Regenerate expected or rely on normalization |

## Environment Variables Set by Harness

- `IDRIS2_PACKAGE_PATH` – Ordered with repo `libs` first, then isolated test prefix.
- `IDRIS2_PREFIX` – Points to `tests/prefix` for isolated installs.
- `IDRIS2_DATA` – Combined support directories for current + test prefix.
- `NAME_VERSION` – Derived version tag (e.g. `idris2-0.7.0`).

Avoid overriding these manually during test runs unless debugging path resolution.

## Requesting Enhancements

Potential future flags:
- `-DryRun` (build runner, no execution)
- Glob token expansion (`basic00{1,3}`)
- Category grouping (if test metadata added)

Open an issue or ask directly if you need one of these.

---
_Last updated: generated by automation; adjust if upstream test runner semantics change._
