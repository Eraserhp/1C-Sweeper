<#
.SYNOPSIS
    Исправляет ошибки с массивами в EDT-модулях
.DESCRIPTION
    1. Заменяет $logFiles.Count на @($logFiles).Count в EdtService.ps1
    2. Заменяет ${1} на правильные имена переменных в Test-EdtService.ps1
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir

Write-Host "`n=== ИСПРАВЛЕНИЕ МАССИВОВ В EDT ===" -ForegroundColor Cyan

# Создаем backup
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backupDir = Join-Path $projectRoot "backups\fix_edt_arrays_$timestamp"
New-Item -Path $backupDir -ItemType Directory -Force | Out-Null

# Файлы для исправления
$filesToFix = @(
    @{
        Path = "src\services\EdtService.ps1"
        Fixes = @(
            @{ Old = 'Write-LogInfo "    ✓ Удалено логов плагинов: $($logFiles.Count)"'; New = 'Write-LogInfo "    ✓ Удалено логов плагинов: $(@($logFiles).Count)"' }
        )
    },
    @{
        Path = "tests\Test-EdtService.ps1"
        Fixes = @(
            @{ Old = 'if (@(${1}).Count -eq 2) {'; New = 'if (@($found).Count -eq 2) {' }
            @{ Old = 'if (@(${1}).Count -ge 1) {'; New = 'if (@($all).Count -ge 1) {' }
            @{ Old = 'if (@(${1}).Count -eq 0) {'; New = 'if (@($filtered).Count -eq 0) {' }
            @{ Old = 'if (@(${1}).Count -eq 1) {'; New = 'if (@($allWs).Count -eq 1) {' }
        )
    }
)

$totalFixed = 0

foreach ($fileInfo in $filesToFix) {
    $filePath = Join-Path $projectRoot $fileInfo.Path
    
    if (-not (Test-Path $filePath)) {
        Write-Host "⚠ Файл не найден: $($fileInfo.Path)" -ForegroundColor Yellow
        continue
    }
    
    Write-Host "`nОбработка: $($fileInfo.Path)" -ForegroundColor Cyan
    
    # Создаем backup
    $backupPath = Join-Path $backupDir (Split-Path -Leaf $filePath)
    Copy-Item -Path $filePath -Destination $backupPath -Force
    Write-Host "  Backup: $backupPath" -ForegroundColor Gray
    
    # Читаем файл
    $content = [System.IO.File]::ReadAllText($filePath, [System.Text.Encoding]::UTF8)
    $modified = $false
    $fixCount = 0
    
    # Применяем исправления
    foreach ($fix in $fileInfo.Fixes) {
        if ($content.Contains($fix.Old)) {
            $content = $content.Replace($fix.Old, $fix.New)
            $modified = $true
            $fixCount++
            Write-Host "  ✓ Исправлено: $($fix.Old)" -ForegroundColor Green
        }
    }
    
    if ($modified) {
        # Сохраняем с UTF-8 BOM
        $utf8WithBom = New-Object System.Text.UTF8Encoding($true)
        [System.IO.File]::WriteAllText($filePath, $content, $utf8WithBom)
        Write-Host "  ✓ Сохранено: $fixCount исправлений" -ForegroundColor Green
        $totalFixed += $fixCount
    } else {
        Write-Host "  ⊖ Изменений не требуется" -ForegroundColor Gray
    }
}

Write-Host "`n=== ИТОГО ===" -ForegroundColor Cyan
Write-Host "Всего исправлений: $totalFixed" -ForegroundColor Green
Write-Host "Backup: $backupDir" -ForegroundColor Gray
Write-Host "`nТеперь можно запустить: .\tests\Test-EdtService.ps1" -ForegroundColor Cyan