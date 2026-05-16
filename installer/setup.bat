@echo off
echo ========================================
echo   ?? - AI????? ???? v1.0.0
echo ========================================
echo.
echo ????...
echo.

:: Check admin
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo ??????????????...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

:: Set directories
set "INSTALL_DIR=%ProgramFiles%\??"
set "START_MENU=%APPDATA%\Microsoft\Windows\Start Menu\Programs\??"
set "DESKTOP=%USERPROFILE%\Desktop\??.lnk"

:: Create directories
mkdir "%INSTALL_DIR%" 2>nul
mkdir "%START_MENU%" 2>nul

:: Copy files
echo ??????...
xcopy /E /Y "%~dp0*" "%INSTALL_DIR%\" 2>nul

:: Create shortcuts
powershell -Command "$ws = New-Object -ComObject WScript.Shell; $s = $ws.CreateShortcut('%START_MENU%\??.lnk'); $s.TargetPath = '%INSTALL_DIR%\ai_reader.exe'; $s.WorkingDirectory = '%INSTALL_DIR%'; $s.Description = 'AI?????'; $s.Save()"
powershell -Command "$ws = New-Object -ComObject WScript.Shell; $s = $ws.CreateShortcut('%DESKTOP%'); $s.TargetPath = '%INSTALL_DIR%\ai_reader.exe'; $s.WorkingDirectory = '%INSTALL_DIR%'; $s.Description = 'AI?????'; $s.Save()"

echo.
echo ????????????????????
echo.
pause
