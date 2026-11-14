param()

$scriptDir = $PSScriptRoot
if (Test-Path (Join-Path $scriptDir "TestHarness.lua")) {
    $testsDir = $scriptDir
    $projectRoot = Split-Path $scriptDir -Parent
} elseif (Test-Path (Join-Path $scriptDir "Tests\TestHarness.lua")) {
    $projectRoot = $scriptDir
    $testsDir = Join-Path $scriptDir "Tests"
} else {
    $projectRoot = (Get-Location).Path
    $testsDir = Join-Path $projectRoot "Tests"
}

$testHarness = Join-Path $testsDir "TestHarness.lua"
if (-not (Test-Path $testHarness)) {
    Write-Error "[ERROR] TestHarness.lua not found at $testHarness"
    exit 1
}

$luaBin = $null
if ($env:LUA_EXE -and (Test-Path $env:LUA_EXE)) {
    $luaBin = $env:LUA_EXE
}

if (-not $luaBin) {
    foreach ($cmd in @("lua", "luajit")) {
        $found = Get-Command $cmd -ErrorAction SilentlyContinue
        if ($found) {
            $luaBin = $found.Source
            break
        }
    }
}

if (-not $luaBin) {
    $candidates = @(
        "C:\Dev Projects\Addon Studio\Extensions\Tools\Lua\lua.exe",
        "C:\Program Files\Lua\lua.exe",
        "C:\Program Files (x86)\Lua\lua.exe",
        "C:\Program Files (x86)\Lua\5.1\bin\lua.exe",
        "C:\ProgramData\chocolatey\bin\lua.exe",
        "$env:USERPROFILE\scoop\shims\lua.exe",
        "$env:LOCALAPPDATA\Programs\Lua\lua.exe",
        "C:\tools\lua\lua.exe"
    )
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path $candidate)) {
            $luaBin = $candidate
            break
        }
    }
}

if (-not $luaBin) {
    Write-Host "[ERROR] No Lua interpreter found on this system." -ForegroundColor Red
    Write-Host "Please set `$env:LUA_EXE or install Lua ('choco install lua' or 'winget install -e --id DEVCOM.Lua')." -ForegroundColor Yellow
    exit 1
}

Write-Host "[ULO Test Runner] Using Lua interpreter: $luaBin" -ForegroundColor Cyan
Write-Host "[ULO Test Runner] Project root: $projectRoot" -ForegroundColor Cyan
Write-Host "[ULO Test Runner] Executing test suite...`n" -ForegroundColor Cyan

$env:ULO_PROJECT_ROOT = $projectRoot
& $luaBin $testHarness @args
$exitCode = $LASTEXITCODE

Write-Host ""
if ($exitCode -eq 0) {
    Write-Host "[ULO Test Runner] Result: ALL TESTS PASSED (Exit Code: 0)" -ForegroundColor Green
} else {
    Write-Host "[ULO Test Runner] Result: TESTS FAILED (Exit Code: $exitCode)" -ForegroundColor Red
}

exit $exitCode
