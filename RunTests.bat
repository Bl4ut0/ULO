@echo off
setlocal EnableDelayedExpansion

:: Resolve directory paths safely without trailing backslash
for %%F in ("%~dp0.") do set "SCRIPT_DIR=%%~fF"

if exist "%SCRIPT_DIR%\TestHarness.lua" (
    set "TESTS_DIR=%SCRIPT_DIR%"
    for %%P in ("%SCRIPT_DIR%\..") do set "PROJECT_ROOT=%%~fP"
) else if exist "%SCRIPT_DIR%\Tests\TestHarness.lua" (
    set "PROJECT_ROOT=%SCRIPT_DIR%"
    set "TESTS_DIR=%SCRIPT_DIR%\Tests"
) else (
    set "PROJECT_ROOT=%CD%"
    set "TESTS_DIR=%CD%\Tests"
)

set "TEST_HARNESS=%TESTS_DIR%\TestHarness.lua"
set "ULO_PROJECT_ROOT=%PROJECT_ROOT%"

:: Discover Lua Interpreter
set "LUA_BIN="

if defined LUA_EXE (
    if exist "%LUA_EXE%" set "LUA_BIN=%LUA_EXE%"
)

if not defined LUA_BIN (
    for %%C in (lua.exe luajit.exe) do (
        if not defined LUA_BIN (
            for /f "tokens=*" %%I in ('where %%C 2^>nul') do (
                if not defined LUA_BIN set "LUA_BIN=%%I"
            )
        )
    )
)

if not defined LUA_BIN (
    for %%P in (
        "C:\Dev Projects\Addon Studio\Extensions\Tools\Lua\lua.exe"
        "C:\Program Files\Lua\lua.exe"
        "C:\Program Files (x86)\Lua\lua.exe"
        "C:\Program Files (x86)\Lua\5.1\bin\lua.exe"
        "C:\ProgramData\chocolatey\bin\lua.exe"
        "%USERPROFILE%\scoop\shims\lua.exe"
        "%LOCALAPPDATA%\Programs\Lua\lua.exe"
        "C:\tools\lua\lua.exe"
    ) do (
        if not defined LUA_BIN (
            if exist "%%~P" set "LUA_BIN=%%~P"
        )
    )
)

if not defined LUA_BIN (
    echo [ERROR] No Lua interpreter found on this system.
    echo Please set LUA_EXE environment variable to your lua.exe path.
    exit /b 1
)

echo [ULO Test Runner] Using Lua interpreter: %LUA_BIN%
echo [ULO Test Runner] Project root: %PROJECT_ROOT%
echo.

"%LUA_BIN%" "%TEST_HARNESS%" %*
set "TEST_EXIT_CODE=%ERRORLEVEL%"

echo.
if %TEST_EXIT_CODE% equ 0 (
    echo [ULO Test Runner] Result: ALL TESTS PASSED - Exit code 0
) else (
    echo [ULO Test Runner] Result: TESTS FAILED - Exit code %TEST_EXIT_CODE%
)

exit /b %TEST_EXIT_CODE%
