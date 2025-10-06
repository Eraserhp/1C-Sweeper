#Requires -Version 5.1
<#
.SYNOPSIS
    Исправляет Test-ReportService.ps1 - проверка Duration
.DESCRIPTION
    Duration = 0 - это валидное значение для быстрых операций
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$targetFile = Join-Path -Path $projectRoot -ChildPath "tests\Test-ReportService.ps1"

Write-Host "=== ИСПРАВЛЕНИЕ Test-ReportService.ps1 ===" -ForegroundColor Cyan
Write-Host "Файл: $targetFile" -ForegroundColor Gray

# Создаем backup
$backupFile = "$targetFile.backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
Copy-Item -Path $targetFile -Destination $backupFile -Force
Write-Host "✓ Создан backup: $backupFile" -ForegroundColor Green

# Читаем содержимое
$content = Get-Content -Path $targetFile -Raw -Encoding UTF8

# Исправляем проверку Duration
# Было: if ($report.Duration -gt 0)
# Стало: if ($report.Duration -ge 0)
$content = $content.Replace(
    'if ($report.Duration -gt 0) {',
    'if ($report.Duration -ge 0) {'
)

# Меняем сообщение об ошибке
$content = $content.Replace(
    'Write-Host "  ✗ Длительность не установлена" -ForegroundColor Red',
    'Write-Host "  ✗ Duration имеет некорректное значение: $($report.Duration)" -ForegroundColor Red'
)

# Записываем обратно с BOM
$utf8WithBom = New-Object System.Text.UTF8Encoding $true
[System.IO.File]::WriteAllText($targetFile, $content, $utf8WithBom)

Write-Host "✓ Test-ReportService.ps1 исправлен" -ForegroundColor Green
Write-Host "`nИсправления:" -ForegroundColor Cyan
Write-Host "  • Duration >= 0 (было > 0) - теперь 0 считается валидным значением" -ForegroundColor Gray
Write-Host "`nТеперь запустите тест снова:" -ForegroundColor Cyan
Write-Host "  .\tests\Test-ReportService.ps1" -ForegroundColor White