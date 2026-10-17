@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

set "OUT_DIR=dist"
if not exist "%OUT_DIR%" mkdir "%OUT_DIR%"

set "BASE_BIN="
for %%B in (
    "%LOCALAPPDATA%\Programs\AutoHotkey\v2\AutoHotkey64.exe"
    "%ProgramFiles%\AutoHotkey\v2\AutoHotkey64.exe"
    "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
    "Compiler\AutoHotkey64.exe"
) do (
    if not defined BASE_BIN if exist %%B set "BASE_BIN=%%~B"
)

set "AHK2EXE="
for %%P in (
    "Compiler\Ahk2Exe.exe"
    "%LOCALAPPDATA%\Programs\AutoHotkey\Compiler\Ahk2Exe.exe"
    "%ProgramFiles%\AutoHotkey\Compiler\Ahk2Exe.exe"
    "C:\Program Files\AutoHotkey\Compiler\Ahk2Exe.exe"
) do (
    if not defined AHK2EXE if exist %%P set "AHK2EXE=%%~P"
)

if not defined AHK2EXE where Ahk2Exe.exe >nul 2>&1 && set "AHK2EXE=Ahk2Exe.exe"

if not defined AHK2EXE (
    echo [INFO] Ahk2Exe not found. Downloading compiler...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $u='https://github.com/AutoHotkey/Ahk2Exe/releases/download/Ahk2Exe1.1.37.02a2/Ahk2Exe1.1.37.02a2.zip'; try { $r=Invoke-RestMethod 'https://api.github.com/repos/AutoHotkey/Ahk2Exe/releases' -Headers @{'User-Agent'='PS'}; if ($r[0].assets[0].browser_download_url) { $u=$r[0].assets[0].browser_download_url } } catch {}; Invoke-WebRequest -Uri $u -OutFile 'Ahk2Exe.zip'; Expand-Archive -Path 'Ahk2Exe.zip' -DestinationPath 'Compiler' -Force; Remove-Item 'Ahk2Exe.zip' -Force"
    if exist "Compiler\Ahk2Exe.exe" set "AHK2EXE=%CD%\Compiler\Ahk2Exe.exe"
)

if not defined BASE_BIN (
    echo [INFO] AutoHotkey64.exe not found. Downloading AHK v2 runtime...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri 'https://www.autohotkey.com/download/ahk-v2.zip' -OutFile 'ahk-v2.zip'; Expand-Archive -Path 'ahk-v2.zip' -DestinationPath 'Compiler' -Force; Remove-Item 'ahk-v2.zip' -Force"
    if exist "Compiler\AutoHotkey64.exe" set "BASE_BIN=%CD%\Compiler\AutoHotkey64.exe"
)

if not exist "%AHK2EXE%" (
    echo [ERROR] Failed to obtain Ahk2Exe.exe compiler.
    pause
    exit /b 1
)

echo [INFO] Compiling WindowAssist.exe...
"%AHK2EXE%" /in "WindowAssist.ahk" /out "%OUT_DIR%\WindowAssist.exe" /icon "assets\app.ico" /base "%BASE_BIN%"

if %errorlevel% neq 0 (
    echo [ERROR] Compilation failed.
    pause
    exit /b %errorlevel%
)

xcopy /E /I /Y "assets" "%OUT_DIR%\assets" >nul
xcopy /E /I /Y "web" "%OUT_DIR%\web" >nul
copy /Y "config.json" "%OUT_DIR%\config.json" >nul
copy /Y "Lib\WebView2\64bit\WebView2Loader.dll" "%OUT_DIR%\WebView2Loader.dll" >nul
xcopy /E /I /Y "Lib\WebView2\64bit" "%OUT_DIR%\Lib\WebView2\64bit" >nul

echo [SUCCESS] Build complete: %OUT_DIR%\WindowAssist.exe
pause