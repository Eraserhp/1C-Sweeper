<#
.SYNOPSIS
    Запуск всех тестов 1C-Sweeper
.DESCRIPTION
    Последовательно запускает все тестовые сценарии проекта
    и выводит общую сводку результатов
.NOTES
    Проект: 1C-Sweeper
    Версия: 1.0
    Дата создания: 2025-10-06
#>

#Requires -Version 5.1

param(
    [Parameter(Mandatory = $false)]
    [string]$ProjectRoot = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'  # Продолжаем выполнение при ошибках

# Настройка кодировки
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# Определение корня проекта
if ([string]::IsNullOrEmpty($ProjectRoot)) {
    if (-not [string]::IsNullOrEmpty($PSScriptRoot)) {
        $ProjectRoot = Split-Path -Parent $PSScriptRoot
    } else {
        $ProjectRoot = $PWD.Path
    }
}

$testsPath = Join-Path -Path $ProjectRoot -ChildPath "tests"

# Список тестов
$tests = @(
    @{
        Name = "Этап 1: Базовая инфраструктура"
        Script = "Test-Infrastructure.ps1"
        Order = 1
    },
    @{
        Name = "Этап 2: Git-сервис"
        Script = "Test-GitService.ps1"
        Order = 2
    },
    @{
        Name = "Этап 3: EDT-сервис"
        Script = "Test-EdtService.ps1"
        Order = 3
    },
    @{
        Name = "Этап 4: Database-сервис"
        Script = "Test-DatabaseService.ps1"
        Order = 4
    },
    @{
        Name = "Этап 5: Отчетность"
        Script = "Test-ReportService.ps1"
        Order = 5
    },
    @{
        Name = "Этап 7: Главный оркестратор"
        Script = "Test-MaintenanceService.ps1"
        Order = 7
    }
)

Write-Host @"

╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║              1C-SWEEPER - ЗАПУСК ВСЕХ ТЕСТОВ              ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

Write-Host "Корень проекта: $ProjectRoot" -ForegroundColor Gray
Write-Host "Всего тестов: $($tests.Count)" -ForegroundColor White
Write-Host ""

$startTime = Get-Date
$results = @()

foreach ($test in $tests) {
    $testScript = Join-Path -Path $testsPath -ChildPath $test.Script
    
    if (-not (Test-Path $testScript)) {
        Write-Host "✗ Тест не найден: $($test.Script)" -ForegroundColor Red
        $results += @{
            Name = $test.Name
            Passed = $false
            Duration = 0
            ExitCode = -1
        }
        continue
    }
    
    Write-Host ("=" * 70) -ForegroundColor Cyan
    Write-Host "Запуск: $($test.Name)" -ForegroundColor Yellow
    Write-Host ("=" * 70) -ForegroundColor Cyan
    Write-Host ""
    
    $testStartTime = Get-Date
    
    # Запускаем тест
    try {
        & $testScript -ProjectRoot $ProjectRoot
        $exitCode = $LASTEXITCODE
    }
    catch {
        Write-Host "Ошибка выполнения теста: $($_.Exception.Message)" -ForegroundColor Red
        $exitCode = 1
    }
    
    $testDuration = ((Get-Date) - $testStartTime).TotalSeconds
    
    $results += @{
        Name = $test.Name
        Script = $test.Script
        Passed = ($exitCode -eq 0)
        Duration = [Math]::Round($testDuration, 2)
        ExitCode = $exitCode
    }
    
    Write-Host ""
}

# Итоговая сводка
$totalDuration = ((Get-Date) - $startTime).TotalSeconds
$totalPassed = @($results | Where-Object { $_.Passed }).Count
$totalFailed = @($results | Where-Object { -not $_.Passed }).Count

Write-Host ""
Write-Host ("=" * 70) -ForegroundColor Cyan
Write-Host "  ИТОГОВАЯ СВОДКА" -ForegroundColor Cyan
Write-Host ("=" * 70) -ForegroundColor Cyan
Write-Host ""

foreach ($result in $results) {
    $status = if ($result.Passed) { "✓ ПРОЙДЕНО" } else { "✗ НЕ ПРОЙДЕНО" }
    $color = if ($result.Passed) { "Green" } else { "Red" }
    
    Write-Host "  $($result.Name) " -NoNewline -ForegroundColor White
    Write-Host $status -ForegroundColor $color
    Write-Host "    Время: $($result.Duration) сек" -ForegroundColor Gray
    
    if (-not $result.Passed) {
        Write-Host "    Код выхода: $($result.ExitCode)" -ForegroundColor Red
    }
    
    Write-Host ""
}

Write-Host ("=" * 70) -ForegroundColor Cyan
Write-Host ""
Write-Host "  Всего тестов:    $($results.Count)" -ForegroundColor White
Write-Host "  Пройдено:        " -NoNewline -ForegroundColor White
Write-Host $totalPassed -ForegroundColor Green
Write-Host "  Не пройдено:     " -NoNewline -ForegroundColor White

if ($totalFailed -gt 0) {
    Write-Host $totalFailed -ForegroundColor Red
} else {
    Write-Host $totalFailed -ForegroundColor Green
}

Write-Host ""
Write-Host "  Общее время:     $([Math]::Round($totalDuration, 2)) сек" -ForegroundColor Gray
Write-Host ""
Write-Host ("=" * 70) -ForegroundColor Cyan
Write-Host ""

if ($totalFailed -eq 0) {
    Write-Host "🎉 ВСЕ ТЕСТЫ ПРОЙДЕНЫ УСПЕШНО!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Система 1C-Sweeper готова к использованию!" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Следующие шаги:" -ForegroundColor Yellow
    Write-Host "  1. Запустите установщик: .\install\Install.ps1" -ForegroundColor White
    Write-Host "  2. Следуйте инструкциям установки" -ForegroundColor White
    Write-Host "  3. Проверьте созданную конфигурацию" -ForegroundColor White
    Write-Host "  4. Система будет работать автоматически!" -ForegroundColor White
    Write-Host ""
    exit 0
} else {
    Write-Host "⚠ ОБНАРУЖЕНЫ ОШИБКИ В ТЕСТАХ" -ForegroundColor Red
    Write-Host ""
    Write-Host "Тесты с ошибками:" -ForegroundColor Yellow
    
    foreach ($failed in ($results | Where-Object { -not $_.Passed })) {
        Write-Host "  • $($failed.Name)" -ForegroundColor Red
        Write-Host "    Скрипт: $($failed.Script)" -ForegroundColor Gray
    }
    
    Write-Host ""
    Write-Host "Пожалуйста, исправьте ошибки перед использованием системы." -ForegroundColor Yellow
    Write-Host ""
    exit 1
}