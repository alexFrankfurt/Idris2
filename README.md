# Idris 2

This fork contains only necessary changes to the Idris2 repo that make it build and install on Windows in a straightforward way, read part about [Windows below](#windows-cmake--powershell). Install [elab](https://github.com/alexFrankfurt/idris2-elab-util) and [pack](https://github.com/alexFrankfurt/idris2-pack?tab=readme-ov-file#reusing-an-existing-idris2-installation-on-windows) for package management.

[![Documentation Status](https://readthedocs.org/projects/idris2/badge/?version=latest)](https://idris2.readthedocs.io/en/latest/?badge=latest)
[![Build Status](https://github.com/idris-lang/Idris2/actions/workflows/ci-idris2-and-libs.yml/badge.svg?branch=main)](https://github.com/idris-lang/Idris2/actions/workflows/ci-idris2-and-libs.yml?query=branch%3Amain)

[Idris 2](https://idris-lang.org/) is a purely functional programming language
with first class types.

For installation instructions, see [INSTALL.md](INSTALL.md).

The [wiki](https://github.com/idris-lang/Idris2/wiki) lists a number of useful
resources, in particular

+ [What's changed since Idris 1](https://idris2.readthedocs.io/en/latest/updates/updates.html)
+ [Resources for learning Idris](https://github.com/idris-lang/Idris2/wiki/Resources),
  including [official talks](https://github.com/idris-lang/Idris2/wiki/Resources#official-talks)
  that showcase its capabilities
+ [Editor support](https://github.com/idris-lang/Idris2/wiki/Editor-Support)

## Installation and Packages

The most common way to install the latest version of Idris and its packages is through [`pack`][PACK] Idris' package manager. Working with the latest version of Idris is as easy as `pack switch latest`.
Follow instructions [on the `pack` repository][PACK] for how to install `pack`.

To use `pack` and idris, you will need an `.ipkg` file (Idris-package file) that describes your idris project.
You can generate one with `idris2 --init`. Once setup with an `.ipkg` file, `pack` gives you access to the [_pack collection_][PACK_COL] of packages, a set of compatible libraries in the ecosystem.
If your dependency is in the `depends` field of your `.ipkg` file, `pack` will automatically pull the dependency from you matching pack collection.
The wiki hosts a list of [curated packages by the community](https://github.com/idris-lang/Idris2/wiki/Third-party-Libraries).

Finally, `pack` also makes it easy to download, and keep updated version of, [idris2-lsp](https://github.com/idris-community/idris2-lsp), and other idris-related programs.

### Windows (CMake + PowerShell)

This guide describes a Windows-first workflow using Visual Studio, CMake, PowerShell, and Racket.

#### Prerequisites

- Visual Studio 2022 (Desktop development with C++)
- CMake (3.15+)
- PowerShell 7+ (pwsh)
- Racket (raco available in PATH)

Optional: Git for Windows

#### Configure, Bootstrap, Install

Run these commands in PowerShell (quote all -D args):

1) Configure (from the repository root)

```
cmake -S . -B build-cmake -D IDRIS2_VERSION=0.7.0
```

2) Bootstrap (stage1 + stage2)

```
cmake --build build-cmake --config Release --target stage2
```

3) Install to a prefix (example C:\\Idris2)

```
cmake --install build-cmake --config Release --prefix "C:\\Idris2"
```
#### Clean

```
Remove-Item -Recurse -Force .\build-cmake, .\build, .\bootstrap-build, .\support\c\build
```
#### Install Layout

- Binaries and runtime
  - `C:\\Idris2\\bin\\idris2.ps1` (PowerShell launcher)
  - `C:\\Idris2\\bin\\idris2.cmd` (cmd shim)
  - `C:\\Idris2\\bin\\idris2_app\\idris2-boot.exe`
  - `C:\\Idris2\\bin\\idris2_app\\libidris2_support.dll`
- Libraries (compiled TTC files)
  - `C:\\Idris2\\idris2-0.7.0\\prelude-0.7.0\\...`
  - `C:\\Idris2\\idris2-0.7.0\\base-0.7.0\\...`
  - `C:\\Idris2\\idris2-0.7.0\\linear-0.7.0\\...`
  - `C:\\Idris2\\idris2-0.7.0\\network-0.7.0\\...`
  - `C:\\Idris2\\idris2-0.7.0\\contrib-0.7.0\\...`
  - `C:\\Idris2\\idris2-0.7.0\\test-0.7.0\\...`
  - `C:\\Idris2\\idris2-0.7.0\\papers-0.7.0\\...`
- C support library and headers
  - `C:\\Idris2\\idris2-0.7.0\\lib\\libidris2_support.dll`
  - `C:\\Idris2\\idris2-0.7.0\\support\\c\\*.h`
- Racket backend support
  - `C:\\Idris2\\idris2-0.7.0\\support\\racket\\support.rkt`

#### How to run Idris2

- PowerShell (recommended):

```
& "C:\\Idris2\\bin\\idris2.ps1" --version
& "C:\\Idris2\\bin\\idris2.ps1" .\\Main.idr -o main
```

- cmd.exe:

```
C:\\Idris2\\bin\\idris2.cmd --version
C:\\Idris2\\bin\\idris2.cmd .\\Main.idr -o main
```

If you want, add `C:\\Idris2\\bin` to PATH.

#### Notes

- The launcher now relies on Idris' built-in mkdirAll to create build directories on demand; no pre-creation or DLL copying is performed by the launcher.
- To run the Idris 2 test suite on Windows via CMake, use the custom test target: build stage2 first, then `cmake --build . --config Release -t test` (from the build folder). You can filter tests by passing `-Only <pattern>` or `-Except <pattern>` via `tools/run-tests.ps1` directly.
- If you switch versions, re-run configure and install with the new `-D IDRIS2_VERSION=...`.

#### Test Suite

For detailed instructions on running individual or multiple tests, filtering with `-Only` / `-Except`, using array selectors, and listing tests without executing them, see [RUNNING_TESTS.md](RUNNING_TESTS.md).

#### Automated REPL Flags & Golden Test Changes (This Fork)

This Windows-focused fork introduces (or standardizes) several compiler flags and test harness behaviours to make the REPL and golden tests deterministic and CI‑friendly:

New / emphasized flags used by the test harness:

| Flag | Purpose |
|------|---------|
| `--repl-input <file>` | Feed a sequence of REPL commands from a file (non-interactive). |
| `--repl-output <file>` | Capture the REPL session transcript (exact user-visible lines) to a file. |
| `--width <n>` | Fix output wrapping width to ensure stable formatting in golden outputs. |
| `--no-color` | Disable ANSI color so golden files are not polluted with escape codes. |
| `--no-prelude` | (Existing flag) Sometimes used in very small baseline tests; documented here for completeness. |

Example (what the PowerShell test runner effectively does):

```
& ./build/exec/idris2.ps1 --repl-input test_repl_input.txt --repl-output transcript.txt --width 120 --no-color MyModule.idr
```

Golden test harness updates:

* Dual expected files: if an `expected_ro` file is present, it is preferred over `expected`. The `_ro` variant represents a REPL transcript (“read‑only” baseline) captured via `--repl-output`.
* CRLF / LF neutrality: all carriage returns (`\r`) are stripped before textual comparison so tests pass uniformly on Windows and POSIX.
* External cleanup: removal of stale per-test `output`/temporary files is handled in `tools/run-tests.ps1` instead of Idris code (simpler semantics & fewer races).
* Deterministic formatting: fixed `--width` plus `--no-color` ensures column alignment and prevents sporadic diffs due to terminal size or ANSI sequences.
* Library path isolation: once the final self‑hosted compiler is built, bootstrap library paths are dropped from `IDRIS2_PACKAGE_PATH` for cleaner, warning‑free tests.

Migration guidance for adding or updating a golden test in this fork:

1. Create (or update) your test directory under `tests/<suite>/<name>/` with source files.
2. Provide a REPL command script (e.g. `repl_input` or reuse the shared one) if interaction is required.
3. Run the test harness to generate a transcript (or run the `idris2` command with the flags above) and capture the stable output.
4. Save the canonical transcript as `expected_ro` (preferred). If you keep the older `expected` style, it will only be used when `expected_ro` is absent.
5. Avoid embedding color codes or depending on terminal width—those are now standardized.

Notes:

* These flags are primarily for automation; interactive users normally do not need them.
* Treat the interface as experimental (naming may change upstream); pin to this fork if you rely on them in scripts.
* If you see unexpected diffs on Windows, first check for stray `\r` characters or missing `--no-color` usage.

Environment variable reminder (test & install layout): make sure the launcher‑provided `IDRIS2_PREFIX` (pointing at the parent `lib` directory) and `IDRIS2_{PATH,PACKAGE_PATH}` are not overridden manually unless debugging path issues.


## Resources to Learn Idris 2

### Books
- [_Type-Driven Development with Idris_](https://www.manning.com/books/type-driven-development-with-idris), Edwin brady. This was written for Idris1. If you are using Idris2, you should make [these changes](https://idris2.readthedocs.io/en/latest/typedd/typedd.html)
### Tutorials
- [_Functional Programming in Idris 2_](https://github.com/idris-community/idris2-tutorial)
- [_A Tutorial on Elaborator Reflection in Idris 2_](https://github.com/stefan-hoeck/idris2-elab-util/blob/main/src/Doc/Index.md), accompanied by [library utilities](https://github.com/stefan-hoeck/idris2-elab-util)
- [_An attempt at explaining Decidable Equality_](https://teh6.eu/en/post/intro-to-decidable-equality/)
### Official talks
- [_What's New in Idris 2_](https://www.youtube.com/watch?v=nbClauMCeds), Edwin Brady, Berlin Functional Programming Group
- [Scheme Workshop Keynote](https://www.youtube.com/watch?v=h9YAOaBWuIk), Edwin Brady, ACM SIGPLAN
- [_Idris 2 - Type-driven Development of Idris_](https://www.youtube.com/watch?v=DRq2NgeFcO0), Edwin Brady, Curry On! 2019
- [_Idris 2: Type-driven development of Idris_](https://www.youtube.com/watch?v=mOtKD7ml0NU), Edwin Brady, Code Mesh LDN 18
- [_The implementation of Idris 2_](https://www.youtube.com/playlist?list=PLmYPUe8PWHKqBRJfwBr4qga7WIs7r60Ql), Edwin Brady, SPLV'20 and [accompanying code](https://github.com/edwinb/SPLV20)
### Community talks
- [_Domain Driven Design Made Dependently Typed_](https://www.youtube.com/watch?v=QBj-4K-l-sg), Andor Penzes, Aug '21
- [_Extending RefC - Making Idris 2 backends while avoiding most of the work_](https://www.youtube.com/watch?v=i-_U6US3bBk), Robert Wright, Sept '21
- [_Introduction to JVM backend for Idris 2_](https://www.youtube.com/watch?v=kSIUsBQS3EE), Marimuthu Madasamy, Oct '21
- [_Idris Data Science Infrastructure - Because sometimes we have to consider the real world_](https://www.youtube.com/watch?v=4jDlYJf9_34),  Robert Wright, Dec '21

## Documentation

- [Official documentation](https://idris2.readthedocs.io/en/latest/index.html)
- Standard library online API reference
  - [official, latest](https://idris-lang.github.io/Idris2/)
  - [community](https://idris2docs.sinyax.net/)
- [Community API reference for selected packages](https://idris2-quickdocs.surge.sh)

## Docker images

- Multi-arch, multi-distro Docker [images](https://github.com/joshuanianji/idris-2-docker) for Idris 2
- Official [images](https://github.com/stefan-hoeck/idris2-pack/pkgs/container/idris2-pack) for the Pack package manager
- [alexhumphreys/idris2-dockerfile](https://github.com/alexhumphreys/idris2-dockerfile)
- [mattpolzin/idris-docker](https://github.com/mattpolzin/idris-docker)
- [dgellow/idris-docker-image](https://github.com/dgellow/idris-docker-image)

## Things still missing

+ Cumulativity (currently `Type : Type`. Bear that in mind when you think
  you've proved something)
+ `rewrite` doesn't yet work on dependent types

## Contributions wanted

If you want to learn more about Idris, contributing to the compiler could be
one way to do so. The [contribution guidelines](CONTRIBUTING.md) outline
the process. Having read that, choose a [good first issue][1] or have a look at
the [contributions wanted][2] for something more involved. This [map][3] should
help you find your way around the source code. See [the wiki page][4]
for more details.

[1]: <https://github.com/idris-lang/Idris2/issues?q=is%3Aopen+is%3Aissue+label%3A%22good+first+issue%22>
[2]: <https://github.com/idris-lang/Idris2/wiki/What-Contributions-are-Needed>
[3]: <https://github.com/idris-lang/Idris2/wiki/Map-of-the-Source-Code>
[4]: <https://github.com/idris-lang/Idris2/wiki/Getting-Started-with-Compiler-Development>
[PACK]: https://github.com/stefan-hoeck/idris2-pack
[PACK_COL]: https://github.com/stefan-hoeck/idris2-pack-db
