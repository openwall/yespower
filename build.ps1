#requires -Version 5.1
<#
.SYNOPSIS
    Build yespower with the MSVC toolchain (port of the supplied GNU Makefile).

.DESCRIPTION
    Locates a Visual Studio / Build Tools installation with the C++ compiler
    using vswhere.exe, imports its x64 environment, and compiles the yespower
    "tests" and "benchmark" programs with cl.exe / link.exe.

    Targets (mirroring the Makefile):
        build.ps1                     # build tests.exe and benchmark.exe (optimized)
        build.ps1 -Target check       # build and run tests.exe, diff against TESTS-OK
        build.ps1 -Target benchmark   # build and run benchmark.exe
        build.ps1 -Target ref         # build using the reference implementation
        build.ps1 -Target check-ref
        build.ps1 -Target clean       # remove build artifacts

.NOTES
    Requires Visual Studio 2026 (Community is fine) with the
    "Desktop development with C++" workload installed. See the README section
    "How to test yespower for proper operation." for details.
#>
[CmdletBinding()]
param(
    [ValidateSet('all', 'tests', 'benchmark', 'check', 'ref', 'check-ref', 'clean')]
    [string]$Target = 'all'
)

$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot

# --- Toolchain detection via vswhere.exe ------------------------------------

function Find-VsWhere {
    $candidates = @(
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'),
        (Join-Path $env:ProgramFiles 'Microsoft Visual Studio\Installer\vswhere.exe')
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c)) { return $c }
    }
    $cmd = Get-Command vswhere.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    throw "vswhere.exe not found. Install Visual Studio 2026 (it ships vswhere)."
}

function Get-VcVarsPath {
    $vswhere = Find-VsWhere
    # Require the x64/x86 C++ compiler toolset.
    $installPath = & $vswhere -latest -products * `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -property installationPath
    if (-not $installPath) {
        throw "No Visual Studio installation with the C++ toolset was found. " +
              "Install the 'Desktop development with C++' workload."
    }
    $vcvars = Join-Path $installPath 'VC\Auxiliary\Build\vcvars64.bat'
    if (-not (Test-Path -LiteralPath $vcvars)) {
        throw "vcvars64.bat not found under '$installPath'."
    }
    return $vcvars
}

# Import the MSVC x64 environment (PATH, INCLUDE, LIB, ...) into this session.
function Import-VcEnvironment {
    $vcvars = Get-VcVarsPath
    Write-Host "Using MSVC environment: $vcvars"
    $marker = '___VCVARS_ENV___'
    # vcvars64.bat may emit benign stderr noise; don't let it abort the script.
    $lines = & cmd /c "`"$vcvars`" 2>nul && echo $marker && set"
    $seen = $false
    foreach ($line in $lines) {
        if (-not $seen) {
            if ($line.Trim() -eq $marker) { $seen = $true }
            continue
        }
        if ($line -match '^([^=]+)=(.*)$') {
            Set-Item -Path ("Env:" + $matches[1]) -Value $matches[2]
        }
    }
    if (-not $seen) { throw "Failed to import the MSVC environment." }
}

# --- Compiler / linker settings (port of Makefile CFLAGS/LDFLAGS) -----------

# /O2            -> -O2
# /D__SSE2__     -> enable the SSE2 intrinsic code path (MSVC x64 supports
#                   <emmintrin.h>; this path is free of GCC inline asm).
# /DUSE_OPENMP   -> intentionally NOT set: benchmark.c's OpenMP section relies
#                   on POSIX-only APIs and VLAs that MSVC cannot build.
$CFLAGS = @('/nologo', '/O2', '/MT', '/D__SSE2__', '/wd4146', '/wd4244')

$OBJS_COMMON = @('sha256.obj')
$OBJS_CORE_OPT = 'yespower-opt.obj'
$OBJS_CORE_REF = 'yespower-ref.obj'

function Invoke-Tool {
    param([string]$Exe, [string[]]$Arguments)
    Write-Host ">> $Exe $($Arguments -join ' ')"
    # Send tool output to the host so it doesn't pollute function return values.
    & $Exe @Arguments | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "$Exe failed with exit code $LASTEXITCODE"
    }
}

function Compile-One {
    param([string]$Source, [string[]]$ExtraFlags = @())
    $obj = [System.IO.Path]::GetFileNameWithoutExtension($Source) + '.obj'
    Invoke-Tool 'cl' (@('/c') + $CFLAGS + $ExtraFlags + @("/Fo$obj", $Source))
    return $obj
}

function Link-Exe {
    param([string]$Out, [string[]]$Objs)
    Invoke-Tool 'link' (@('/nologo', "/OUT:$Out") + $Objs)
}

function Build-Tests {
    param([string]$Core = $OBJS_CORE_OPT)
    $coreSrc = if ($Core -eq $OBJS_CORE_REF) { 'yespower-ref.c' } else { 'yespower-opt.c' }
    $objs = @()
    $objs += Compile-One $coreSrc
    $objs += Compile-One 'sha256.c'
    $objs += Compile-One 'tests.c'
    Link-Exe 'tests.exe' $objs
    Write-Host "Built tests.exe"
}

function Build-Benchmark {
    param([string]$Core = $OBJS_CORE_OPT)
    $coreSrc = if ($Core -eq $OBJS_CORE_REF) { 'yespower-ref.c' } else { 'yespower-opt.c' }
    $objs = @()
    $objs += Compile-One $coreSrc
    $objs += Compile-One 'sha256.c'
    $objs += Compile-One 'benchmark.c'
    Link-Exe 'benchmark.exe' $objs
    Write-Host "Built benchmark.exe"
}

function Invoke-Benchmark {
    param([string]$Core = $OBJS_CORE_OPT)
    Build-Benchmark -Core $Core
    Write-Host 'Running benchmark'
    & .\benchmark.exe | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "benchmark.exe failed with exit code $LASTEXITCODE" }
}

function Invoke-Check {
    param([string]$Core = $OBJS_CORE_OPT)
    Build-Tests -Core $Core
    Write-Host 'Running tests'
    & .\tests.exe | Out-File -Encoding ascii -FilePath 'TESTS-OUT'
    if ($LASTEXITCODE -ne 0) { throw "tests.exe failed with exit code $LASTEXITCODE" }
    # Compare against the reference output, ignoring CRLF/LF differences.
    $expected = (Get-Content -Raw 'TESTS-OK')  -replace "`r`n", "`n"
    $actual   = (Get-Content -Raw 'TESTS-OUT') -replace "`r`n", "`n"
    if ($expected.TrimEnd("`n") -eq $actual.TrimEnd("`n")) {
        Write-Host 'PASSED' -ForegroundColor Green
    } else {
        Write-Host 'FAILED' -ForegroundColor Red
        Compare-Object ($expected -split "`n") ($actual -split "`n") |
            Format-Table -AutoSize | Out-String | Write-Host
        exit 1
    }
}

function Invoke-Clean {
    $patterns = @('*.obj', 'tests.exe', 'benchmark.exe', 'TESTS-OUT',
                  '*.ilk', '*.pdb', '_probe*', '_run.ps1', '_vcout.txt')
    foreach ($p in $patterns) {
        Get-ChildItem -LiteralPath $PSScriptRoot -Filter $p -ErrorAction SilentlyContinue |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }
    Write-Host 'Cleaned build artifacts.'
}

# --- Dispatch ---------------------------------------------------------------

switch ($Target) {
    'clean' { Invoke-Clean; break }
    default {
        Import-VcEnvironment
        switch ($Target) {
            'all'       { Build-Tests; Build-Benchmark }
            'tests'     { Build-Tests }
            'benchmark' { Invoke-Benchmark }
            'check'     { Invoke-Check }
            'ref'       { Build-Tests -Core $OBJS_CORE_REF; Build-Benchmark -Core $OBJS_CORE_REF }
            'check-ref' { Invoke-Check -Core $OBJS_CORE_REF }
        }
    }
}
