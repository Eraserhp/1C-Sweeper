<#
.SYNOPSIS
    Тестирование системы отчетности (Этап 5)
.DESCRIPTION
    Проверка работы ReportService
.NOTES
    Проект: 1C-Sweeper
    Этап: 5 - Отчетность
    Дата создания: 2025-10-06
#>

#Requires -Version 5.1

param(
    [Parameter(Mandatory = $false)]
    [string]$ProjectRoot = ""
)

# Определение корня проекта
if ([string]::IsNullOrEmpty($ProjectRoot)) {
    if (-not [string]::IsNullOrEmpty($PSScriptRoot)) {
        $ProjectRoot = Split-Path -Parent $PSScriptRoot
    } else {
        $ProjectRoot = Split-Path -Parent $PWD.Path
    }
}

Write-Host "Корень проекта: $ProjectRoot" -ForegroundColor Gray

# Импорт модулей
$corePath = Join-Path -Path $ProjectRoot -ChildPath "src\core"

if (-not (Test-Path $corePath)) {
    Write-Host "ОШИБКА: Папка src\core не найдена" -ForegroundColor Red
    exit 1
}

. (Join-Path -Path $corePath -ChildPath "Common.ps1")
. (Join-Path -Path $corePath -ChildPath "LoggingService.ps1")
. (Join-Path -Path $corePath -ChildPath "ReportService.ps1")

# Настройка кодировки и логирования
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# Инициализация логирования
$logPath = Join-Path -Path $env:TEMP -ChildPath "report-test-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
Initialize-Logging -LogFilePath $logPath -SilentMode $false

#region Тесты ReportService

function Test-ReportService {
    Write-Host "`n=== ТЕСТЫ ReportService.ps1 ===" -ForegroundColor Cyan
    
    $allPassed = $true
    
    # Тест 1: Создание отчета
    Write-Host "`nТест 1: Создание нового отчета" -ForegroundColor Yellow
    try {
        $report = New-Report
        
        if ($null -ne $report) {
            Write-Host "  ✓ New-Report создал объект отчета" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Отчет не создан" -ForegroundColor Red
            $allPassed = $false
        }
        
        # Проверка структуры
        $requiredKeys = @('ReportVersion', 'Timestamp', 'Hostname', 'Summary', 'GitRepositories', 'EdtWorkspaces', 'Databases', 'Errors')
        $hasAllKeys = $true
        foreach ($key in $requiredKeys) {
            if (-not $report.ContainsKey($key)) {
                Write-Host "  ✗ Отсутствует ключ: $key" -ForegroundColor Red
                $hasAllKeys = $false
            }
        }
        
        if ($hasAllKeys) {
            Write-Host "  ✓ Структура отчета корректна" -ForegroundColor Green
        } else {
            $allPassed = $false
        }
        
        # Проверка сводки
        if ($report.Summary.TotalSpaceSaved -eq 0.0) {
            Write-Host "  ✓ Начальные значения сводки установлены правильно" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Неверные начальные значения" -ForegroundColor Red
            $allPassed = $false
        }
    }
    catch {
        Write-Host "  ✗ Ошибка: $($_.Exception.Message)" -ForegroundColor Red
        $allPassed = $false
    }
    
    # Тест 2: Добавление Git-результата
    Write-Host "`nТест 2: Добавление Git-результата" -ForegroundColor Yellow
    try {
        $report = New-Report
        
        $gitResult = @{
            Success = $true
            Skipped = $false
            Path = "C:\Test\Repo1"
            SizeBefore = 25.5
            SizeAfter = 12.3
            SpaceSaved = 13.2
            Duration = 456
            Actions = @("prune", "repack", "gc")
            Errors = @()
        }
        
        Add-GitResult -Report $report -Result $gitResult
        
        if (@($report.GitRepositories).Count -eq 1) {
            Write-Host "  ✓ Git-результат добавлен в отчет" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Результат не добавлен" -ForegroundColor Red
            $allPassed = $false
        }
        
        if ($report.Summary.GitReposProcessed -eq 1) {
            Write-Host "  ✓ Счетчик обработанных репозиториев обновлен" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Счетчик не обновлен" -ForegroundColor Red
            $allPassed = $false
        }
        
        if ($report.Summary.TotalSpaceSaved -eq 13.2) {
            Write-Host "  ✓ Освобожденное место учтено ($($report.Summary.TotalSpaceSaved) ГБ)" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Неверный расчет освобожденного места: $($report.Summary.TotalSpaceSaved)" -ForegroundColor Red
            $allPassed = $false
        }
    }
    catch {
        Write-Host "  ✗ Ошибка: $($_.Exception.Message)" -ForegroundColor Red
        $allPassed = $false
    }
    
    # Тест 3: Добавление EDT-результата
    Write-Host "`nТест 3: Добавление EDT-результата" -ForegroundColor Yellow
    try {
        $report = New-Report
        
        $edtResult = @{
            Success = $true
            Path = "C:\EDT\Workspace1"
            SizeBefore = 8589934592  # 8 ГБ в байтах
            SizeAfter = 2147483648   # 2 ГБ в байтах
            SpaceSaved = 6442450944  # 6 ГБ в байтах
            Duration = 45
            Actions = @("clear_logs", "clear_cache")
            Errors = @()
        }
        
        Add-EdtResult -Report $report -Result $edtResult
        
        if (@($report.EdtWorkspaces).Count -eq 1) {
            Write-Host "  ✓ EDT-результат добавлен в отчет" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Результат не добавлен" -ForegroundColor Red
            $allPassed = $false
        }
        
        if ($report.Summary.WorkspacesProcessed -eq 1) {
            Write-Host "  ✓ Счетчик обработанных workspace обновлен" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Счетчик не обновлен" -ForegroundColor Red
            $allPassed = $false
        }
        
        # Проверяем, что размеры конвертированы в ГБ
        $entry = $report.EdtWorkspaces[0]
        if ($entry.SizeBefore -eq 8.0) {
            Write-Host "  ✓ Размеры корректно конвертированы в ГБ" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Ошибка конвертации размеров: $($entry.SizeBefore)" -ForegroundColor Red
            $allPassed = $false
        }
    }
    catch {
        Write-Host "  ✗ Ошибка: $($_.Exception.Message)" -ForegroundColor Red
        $allPassed = $false
    }
    
    # Тест 4: Добавление Database-результата
    Write-Host "`nТест 4: Добавление Database-результата" -ForegroundColor Yellow
    try {
        $report = New-Report
        
        $dbResult = @{
            Success = $true
            Skipped = $false
            Path = "C:\Bases\Dev\1Cv8.1CD"
            SizeBefore = 5.2
            SizeAfter = 3.1
            SpaceSaved = 2.1
            Duration = 234
            Platform = "8.3.27.1719"
            Actions = @("test_and_repair")
            Errors = @()
        }
        
        Add-DatabaseResult -Report $report -Result $dbResult
        
        if (@($report.Databases).Count -eq 1) {
            Write-Host "  ✓ Database-результат добавлен в отчет" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Результат не добавлен" -ForegroundColor Red
            $allPassed = $false
        }
        
        if ($report.Summary.DatabasesProcessed -eq 1) {
            Write-Host "  ✓ Счетчик обработанных баз обновлен" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Счетчик не обновлен" -ForegroundColor Red
            $allPassed = $false
        }
        
        # Проверяем наличие версии платформы
        $entry = $report.Databases[0]
        if ($entry.Platform -eq "8.3.27.1719") {
            Write-Host "  ✓ Версия платформы сохранена" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Версия платформы не сохранена" -ForegroundColor Red
            $allPassed = $false
        }
    }
    catch {
        Write-Host "  ✗ Ошибка: $($_.Exception.Message)" -ForegroundColor Red
        $allPassed = $false
    }
    
    # Тест 5: Обработка ошибок
    Write-Host "`nТест 5: Обработка ошибок" -ForegroundColor Yellow
    try {
        $report = New-Report
        
        $failedResult = @{
            Success = $false
            Skipped = $false
            Path = "C:\Test\FailedRepo"
            SizeBefore = 20.0
            SizeAfter = 20.0
            SpaceSaved = 0.0
            Duration = 10
            Actions = @()
            Errors = @("Git command failed", "Repository is locked")
        }
        
        Add-GitResult -Report $report -Result $failedResult
        
        if ($report.Summary.GitReposFailed -eq 1) {
            Write-Host "  ✓ Счетчик ошибок обновлен" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Счетчик ошибок не обновлен" -ForegroundColor Red
            $allPassed = $false
        }
        
        if (@($report.Errors).Count -eq 2) {
            Write-Host "  ✓ Ошибки добавлены в общий список ($(@($report.Errors).Count))" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Ошибки не добавлены: $(@($report.Errors).Count)" -ForegroundColor Red
            $allPassed = $false
        }
        
        if (Test-ReportHasErrors -Report $report) {
            Write-Host "  ✓ Test-ReportHasErrors корректно определяет наличие ошибок" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Ошибка проверки наличия ошибок" -ForegroundColor Red
            $allPassed = $false
        }
    }
    catch {
        Write-Host "  ✗ Ошибка: $($_.Exception.Message)" -ForegroundColor Red
        $allPassed = $false
    }
    
    # Тест 6: Сохранение отчета
    Write-Host "`nТест 6: Сохранение отчета в JSON" -ForegroundColor Yellow
    try {
        $report = New-Report
        
        # Добавляем несколько результатов
        Add-GitResult -Report $report -Result @{
            Success = $true; Skipped = $false; Path = "C:\Test\Repo1"
            SizeBefore = 25.0; SizeAfter = 12.0; SpaceSaved = 13.0
            Duration = 300; Actions = @("gc"); Errors = @()
        }
        
        Add-EdtResult -Report $report -Result @{
            Success = $true; Path = "C:\EDT\WS1"
            SizeBefore = 5368709120; SizeAfter = 1073741824; SpaceSaved = 4294967296
            Duration = 30; Actions = @("clear_cache"); Errors = @()
        }
        
        $testReportsPath = Join-Path -Path $env:TEMP -ChildPath "1C-Sweeper-Reports-Test"
        $reportFile = Save-Report -Report $report -ReportsPath $testReportsPath
        
        if (Test-Path -Path $reportFile) {
            Write-Host "  ✓ Отчет сохранен: $reportFile" -ForegroundColor Green
            
            # Проверяем, что это валидный JSON
            try {
                $savedReport = Get-Content -Path $reportFile -Raw | ConvertFrom-Json
                Write-Host "  ✓ JSON валиден и может быть прочитан" -ForegroundColor Green
                
                # Проверяем наличие основных полей
                if ($savedReport.Summary.TotalSpaceSaved -gt 0) {
                    Write-Host "  ✓ Данные сохранены корректно" -ForegroundColor Green
                }
            }
            catch {
                Write-Host "  ✗ Ошибка чтения JSON: $($_.Exception.Message)" -ForegroundColor Red
                $allPassed = $false
            }
            
            # Очистка
            Remove-Item -Path $testReportsPath -Recurse -Force -ErrorAction SilentlyContinue
        } else {
            Write-Host "  ✗ Файл отчета не создан" -ForegroundColor Red
            $allPassed = $false
        }
    }
    catch {
        Write-Host "  ✗ Ошибка: $($_.Exception.Message)" -ForegroundColor Red
        $allPassed = $false
    }
    
    # Тест 7: Вспомогательные функции
    Write-Host "`nТест 7: Вспомогательные функции" -ForegroundColor Yellow
    try {
        $report = New-Report
        
        # Добавляем успешные результаты
        Add-GitResult -Report $report -Result @{
            Success = $true; Skipped = $false; Path = "C:\Test\Repo1"
            SizeBefore = 20.0; SizeAfter = 10.0; SpaceSaved = 10.0
            Duration = 100; Actions = @("gc"); Errors = @()
        }
        
        Add-GitResult -Report $report -Result @{
            Success = $true; Skipped = $false; Path = "C:\Test\Repo2"
            SizeBefore = 15.0; SizeAfter = 8.0; SpaceSaved = 7.0
            Duration = 80; Actions = @("gc"); Errors = @()
        }
        
        # Добавляем результат с ошибкой
        Add-GitResult -Report $report -Result @{
            Success = $false; Skipped = $false; Path = "C:\Test\Repo3"
            SizeBefore = 30.0; SizeAfter = 30.0; SpaceSaved = 0.0
            Duration = 5; Actions = @(); Errors = @("Failed")
        }
        
        $successCount = Get-ReportSuccessCount -Report $report
        if ($successCount -eq 2) {
            Write-Host "  ✓ Get-ReportSuccessCount: $successCount" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Неверное количество успешных: $successCount (ожидалось 2)" -ForegroundColor Red
            $allPassed = $false
        }
        
        $failedCount = Get-ReportFailedCount -Report $report
        if ($failedCount -eq 1) {
            Write-Host "  ✓ Get-ReportFailedCount: $failedCount" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Неверное количество ошибок: $failedCount (ожидалось 1)" -ForegroundColor Red
            $allPassed = $false
        }
        
        $summary = Get-ReportSummary -Report $report
        if ($summary.TotalSpaceSaved -eq 17.0) {
            Write-Host "  ✓ Get-ReportSummary: освобождено $($summary.TotalSpaceSaved) ГБ" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Неверный расчет: $($summary.TotalSpaceSaved) (ожидалось 17.0)" -ForegroundColor Red
            $allPassed = $false
        }
    }
    catch {
        Write-Host "  ✗ Ошибка: $($_.Exception.Message)" -ForegroundColor Red
        $allPassed = $false
    }
    
    # Тест 8: Вывод сводки
    Write-Host "`nТест 8: Вывод сводки отчета" -ForegroundColor Yellow
    try {
        $report = New-Report
        
        # Создаем комплексный отчет
        Add-GitResult -Report $report -Result @{
            Success = $true; Skipped = $false; Path = "C:\Test\Repo1"
            SizeBefore = 25.0; SizeAfter = 12.0; SpaceSaved = 13.0
            Duration = 300; Actions = @("gc"); Errors = @()
        }
        
        Add-EdtResult -Report $report -Result @{
            Success = $true; Path = "C:\EDT\WS1"
            SizeBefore = 5368709120; SizeAfter = 1073741824; SpaceSaved = 4294967296
            Duration = 30; Actions = @("clear_cache"); Errors = @()
        }
        
        Add-DatabaseResult -Report $report -Result @{
            Success = $true; Skipped = $false; Path = "C:\Bases\Dev\1Cv8.1CD"
            SizeBefore = 5.0; SizeAfter = 3.0; SpaceSaved = 2.0
            Duration = 120; Platform = "8.3.27.1719"; Actions = @("repair"); Errors = @()
        }
        
        # Финализируем отчет
        Complete-Report -Report $report
        
        Write-Host "  Вывод сводки:" -ForegroundColor Gray
        Write-Host ""
        Show-ReportSummary -Report $report
        Write-Host ""
        
        Write-Host "  ✓ Show-ReportSummary выполнена без ошибок" -ForegroundColor Green
        
        # Проверяем, что Duration установлен
        if ($report.Duration -ge 0) {
            Write-Host "  ✓ Complete-Report установил длительность: $($report.Duration) сек" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Длительность не установлена" -ForegroundColor Red
            $allPassed = $false
        }
    }
    catch {
        Write-Host "  ✗ Ошибка: $($_.Exception.Message)" -ForegroundColor Red
        $allPassed = $false
    }
    
    return $allPassed
}

#endregion

#region Основной код

Write-Host @"

╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║              1C-SWEEPER - ТЕСТИРОВАНИЕ                    ║
║              Этап 5: Отчетность                           ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

$startTime = Get-Date

try {
    # Запуск тестов
    $reportServicePassed = Test-ReportService
    
    # Итоги
    Write-Host "`n`n " -NoNewline
    Write-Host ("+" + "=" * 60) -ForegroundColor Cyan
    Write-Host "  РЕЗУЛЬТАТЫ ТЕСТИРОВАНИЯ" -ForegroundColor Cyan
    Write-Host ("=" * 61) -ForegroundColor Cyan
    
    $results = @(
        @{ Name = "ReportService.ps1"; Passed = $reportServicePassed }
    )
    
    $totalPassed = 0
    $totalTests = $results.Count
    
    foreach ($result in $results) {
        $status = if ($result.Passed) { "✓ ПРОЙДЕНО"; $totalPassed++ } else { "✗ НЕ ПРОЙДЕНО" }
        $color = if ($result.Passed) { "Green" } else { "Red" }
        
        Write-Host "  $($result.Name): " -NoNewline
        Write-Host $status -ForegroundColor $color
    }
    
    Write-Host "`n  Итого: $totalPassed из $totalTests тестов пройдено" -ForegroundColor $(if ($totalPassed -eq $totalTests) { "Green" } else { "Yellow" })
    
    $duration = (Get-Date) - $startTime
    Write-Host "  Время выполнения: $([Math]::Round($duration.TotalSeconds, 2)) сек" -ForegroundColor Gray
    
    Write-Host ("=" * 61) -ForegroundColor Cyan
    
    if ($totalPassed -eq $totalTests) {
        Write-Host "`n✓ ВСЕ ТЕСТЫ ПРОЙДЕНЫ УСПЕШНО!" -ForegroundColor Green
        Write-Host "Этап 5 (Отчетность) завершен." -ForegroundColor Green
        Write-Host "Можно переходить к Этапу 6 (Параллелизация).`n" -ForegroundColor Cyan
        exit 0
    } else {
        Write-Host "`n✗ НЕКОТОРЫЕ ТЕСТЫ НЕ ПРОЙДЕНЫ" -ForegroundColor Red
        Write-Host "Необходимо исправить ошибки перед продолжением.`n" -ForegroundColor Yellow
        exit 1
    }
}
catch {
    Write-Host "`n✗ КРИТИЧЕСКАЯ ОШИБКА:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Gray
    exit 1
}

#endregion