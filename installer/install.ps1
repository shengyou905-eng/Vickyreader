# 知读 - AI辅助阅读器 安装程序
# Run this script as Administrator to install

$ErrorActionPreference = "Stop"
$appName = "知读"
$appVersion = "1.0.0"
$installDir = "$env:ProgramFiles\$appName"
$sourceDir = "$PSScriptRoot"
$shortcutDir = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\$appName"
$desktopShortcut = "$env:USERPROFILE\Desktop\$appName.lnk"

Write-Host "========================================" -ForegroundColor Magenta
Write-Host "  知读 - AI辅助阅读器 安装程序 v$appVersion" -ForegroundColor Magenta
Write-Host "========================================" -ForegroundColor Magenta
Write-Host ""

# Check admin
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "[!] 需要管理员权限。正在请求提升..." -ForegroundColor Yellow
    Start-Process powershell -Verb RunAs -ArgumentList "-File `"$PSCommandPath`""
    exit
}

Write-Host "[*] 安装目录: $installDir" -ForegroundColor Cyan

# Create directories
New-Item -ItemType Directory -Force -Path $installDir | Out-Null
New-Item -ItemType Directory -Force -Path $shortcutDir | Out-Null

# Copy files
Write-Host "[*] 正在复制文件..." -ForegroundColor Cyan
Copy-Item -Path "$sourceDir\*" -Destination $installDir -Recurse -Force

# Create Start Menu shortcut
Write-Host "[*] 创建开始菜单快捷方式..." -ForegroundColor Cyan
$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut("$shortcutDir\$appName.lnk")
$Shortcut.TargetPath = "$installDir\ai_reader.exe"
$Shortcut.WorkingDirectory = $installDir
$Shortcut.Description = "AI辅助阅读器 - 支持EPUB阅读、AI解释、笔记标注"
$Shortcut.IconLocation = "$installDir\data\flutter_assets\assets\icon.png"
$Shortcut.Save()

# Create Desktop shortcut
Write-Host "[*] 创建桌面快捷方式..." -ForegroundColor Cyan
$DesktopShortcut = $WshShell.CreateShortcut($desktopShortcut)
$DesktopShortcut.TargetPath = "$installDir\ai_reader.exe"
$DesktopShortcut.WorkingDirectory = $installDir
$DesktopShortcut.Description = "AI辅助阅读器 - 支持EPUB阅读、AI解释、笔记标注"
$DesktopShortcut.Save()

# Create uninstaller
Write-Host "[*] 创建卸载程序..." -ForegroundColor Cyan
$uninstaller = @"
@echo off
echo 正在卸载 知读...
taskkill /f /im ai_reader.exe 2>nul
rmdir /s /q "$installDir"
rmdir /s /q "$shortcutDir"
del /f "$desktopShortcut" 2>nul
reg delete "HKCU\Software\知读" /f 2>nul
echo 卸载完成！
pause
"@
$uninstaller | Out-File -FilePath "$installDir\uninstall.bat" -Encoding Default
$UnShortcut = $WshShell.CreateShortcut("$shortcutDir\卸载知读.lnk")
$UnShortcut.TargetPath = "$installDir\uninstall.bat"
$UnShortcut.WorkingDirectory = $installDir
$UnShortcut.Save()

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  安装完成！" -ForegroundColor Green
Write-Host "  桌面和开始菜单已创建快捷方式。" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Read-Host "按 Enter 退出"
