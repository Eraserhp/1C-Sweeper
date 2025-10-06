<#
.SYNOPSIS
    Тестирование параллельной обработки (Этап 6)
.DESCRIPTION
    Проверка работы ParallelProcessor
.NOTES
    Проект: 1C-Sweeper
    Этап: 6 - Параллелизация
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
. (Join-Path -Path $corePath -ChildPath "ParallelProcessor.ps1")

# Настройка кодировки и логирования
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# Инициализация логирования
$logPath = Join-Path -Path $env:TEMP -ChildPath "parallel-test-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
Initialize-Logging -LogFilePath $logPath -SilentMode $false

#region Тесты ParallelProcessor

function Test-ParallelProcessor {
    Write-Host "`n=== ТЕСТЫ ParallelProcessor.ps1 ===" -ForegroundColor Cyan
    
    $allPassed = $true
    
    # Тест 1: Последовательная обработка
    Write-Host "`nТест 1: Последовательная обработка" -ForegroundColor Yellow
    try {
        $items = @(1, 2, 3, 4, 5)
        
        $scriptBlock = {
            param($number)
            Start-Sleep -Milliseconds 100
            return @{
                Input = $number
                Output = $number * 2
                Success = $true
            }
        }
        
        $startTime = Get-Date
        $results = Start-SequentialProcessing -Items $items -ScriptBlock $scriptBlock -ItemName "число"
        $duration = ((Get-Date) - $startTime).TotalSeconds
        
        if (@($results).Count -eq 5) {
            Write-Host "  ✓ Обработано элементов: $(@($results).Count)" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Неверное количество: $(@($results).Count)" -ForegroundColor Red
            $allPassed = $false
        }
        
        # Проверяем результаты
        $allCorrect = $true
        foreach ($result in $results) {
            if ($result.Output -ne ($result.Input * 2)) {
                $allCorrect = $false
            }
        }
        
        if ($allCorrect) {
            Write-Host "  ✓ Все результаты корректны" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Некорректные результаты" -ForegroundColor Red
            $allPassed = $false
        }
        
        Write-Host "  ✓ Время выполнения: $([Math]::Round($duration, 2)) сек" -ForegroundColor Green
    }
    catch {
        Write-Host "  ✗ Ошибка: $($_.Exception.Message)" -ForegroundColor Red
        $allPassed = $false
    }
    
    # Тест 2: Параллельная обработка
    Write-Host "`nТест 2: Параллельная обработка" -ForegroundColor Yellow
    try {
        $items = @(1, 2, 3, 4, 5, 6, 7, 8)
        
        $scriptBlock = {
            param($number)
            Start-Sleep -Milliseconds 500
            return @{
                Input = $number
                Output = $number * 3
                Success = $true
            }
        }
        
        $startTime = Get-Date
        $results = Start-ParallelProcessing -Items $items -ScriptBlock $scriptBlock -MaxThreads 4 -ItemName "число"
        $duration = ((Get-Date) - $startTime).TotalSeconds
        
        if (@($results).Count -eq 8) {
            Write-Host "  ✓ Обработано элементов: $(@($results).Count)" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Неверное количество: $(@($results).Count)" -ForegroundColor Red
            $allPassed = $false
        }
        
        # Проверяем результаты
        $allCorrect = $true
        foreach ($result in $results) {
            if (-not $result.Success -or $result.Output -ne ($result.Input * 3)) {
                $allCorrect = $false
            }
        }
        
        if ($allCorrect) {
            Write-Host "  ✓ Все результаты корректны" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Некорректные результаты" -ForegroundColor Red
            $allPassed = $false
        }
        
        Write-Host "  ✓ Время выполнения: $([Math]::Round($duration, 2)) сек" -ForegroundColor Green
        
        # Параллельная обработка должна быть быстрее последовательной
        $expectedSequentialTime = 8 * 0.5  # 8 элементов по 500 мс
        if ($duration -lt $expectedSequentialTime) {
            Write-Host "  ✓ Параллелизм ускорил обработку (ожидалось ~$expectedSequentialTime сек)" -ForegroundColor Green
        } else {
            Write-Host "  ⊖ Параллелизм не дал ожидаемого ускорения" -ForegroundColor Gray
        }
    }
    catch {
        Write-Host "  ✗ Ошибка: $($_.Exception.Message)" -ForegroundColor Red
        $allPassed = $false
    }
    
    # Тест 3: Обработка ошибок в параллельных задачах
    Write-Host "`nТест 3: Обработка ошибок в параллельных задачах" -ForegroundColor Yellow
    try {
        $items = @(1, 2, 3, 4, 5)
        
        $scriptBlock = {
            param($number)
            if ($number -eq 3) {
                throw "Искусственная ошибка для числа 3"
            }
            return @{
                Input = $number
                Output = $number * 2
                Success = $true
            }
        }
        
        $results = Start-ParallelProcessing -Items $items -ScriptBlock $scriptBlock -MaxThreads 2 -ItemName "число"
        
        # Должны быть результаты для всех элементов
        if (@($results).Count -ge 4) {
            Write-Host "  ✓ Ошибка в одной задаче не прервала остальные" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Обработка прервалась: $(@($results).Count)" -ForegroundColor Red
            $allPassed = $false
        }
    }
    catch {
        Write-Host "  ✗ Ошибка: $($_.Exception.Message)" -ForegroundColor Red
        $allPassed = $false
    }
    
    # Тест 4: Определение оптимального количества потоков
    Write-Host "`nТест 4: Определение оптимального количества потоков" -ForegroundColor Yellow
    try {
        # Для 3 элементов
        $threads1 = Get-OptimalThreadCount -ItemCount 3
        if ($threads1 -le 3) {
            Write-Host "  ✓ Для 3 элементов: $threads1 потоков" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Неверное количество: $threads1" -ForegroundColor Red
            $allPassed = $false
        }
        
        # Для 100 элементов
        $threads2 = Get-OptimalThreadCount -ItemCount 100
        Write-Host "  ✓ Для 100 элементов: $threads2 потоков" -ForegroundColor Green
        
        # С явным указанием
        $threads3 = Get-OptimalThreadCount -ItemCount 100 -MaxThreads 4
        if ($threads3 -eq 4) {
            Write-Host "  ✓ С MaxThreads=4: $threads3 потоков" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Ожидалось 4, получено $threads3" -ForegroundColor Red
            $allPassed = $false
        }
    }
    catch {
        Write-Host "  ✗ Ошибка: $($_.Exception.Message)" -ForegroundColor Red
        $allPassed = $false
    }
    
    # Тест 5: Проверка целесообразности параллелизма
    Write-Host "`nТест 5: Проверка целесообразности параллелизма" -ForegroundColor Yellow
    try {
        $should1 = Test-ShouldUseParallel -ItemCount 1
        if (-not $should1) {
            Write-Host "  ✓ Для 1 элемента параллелизм нецелесообразен" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Ошибка: параллелизм рекомендован для 1 элемента" -ForegroundColor Red
            $allPassed = $false
        }
        
        $should5 = Test-ShouldUseParallel -ItemCount 5
        if ($should5) {
            Write-Host "  ✓ Для 5 элементов параллелизм целесообразен" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Ошибка: параллелизм не рекомендован для 5 элементов" -ForegroundColor Red
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

#region Тест производительности

function Test-Performance {
    Write-Host "`n=== ТЕСТ ПРОИЗВОДИТЕЛЬНОСТИ ===" -ForegroundColor Cyan
    
    $allPassed = $true
    
    Write-Host "`nСравнение последовательной и параллельной обработки" -ForegroundColor Yellow
    try {
        $itemCount = 10
        $items = 1..$itemCount
        
        # Имитация реальной нагрузки (например, Git-операции)
        $scriptBlock = {
            param($number)
            Start-Sleep -Milliseconds 300  # ~0.3 сек на элемент
            return @{
                Input = $number
                Output = $number * 2
                Success = $true
            }
        }
        
        Write-Host "`n  Тест 1: Последовательная обработка ($itemCount элементов)..." -ForegroundColor Gray
        $seqStart = Get-Date
        $seqResults = Start-SequentialProcessing -Items $items -ScriptBlock $scriptBlock -ItemName "тест"
        $seqDuration = ((Get-Date) - $seqStart).TotalSeconds
        
        Write-Host "  ✓ Последовательная: $([Math]::Round($seqDuration, 2)) сек" -ForegroundColor Green
        
        Write-Host "`n  Тест 2: Параллельная обработка ($itemCount элементов, 4 потока)..." -ForegroundColor Gray
        $parStart = Get-Date
        $parResults = Start-ParallelProcessing -Items $items -ScriptBlock $scriptBlock -MaxThreads 4 -ItemName "тест"
        $parDuration = ((Get-Date) - $parStart).TotalSeconds
        
        Write-Host "  ✓ Параллельная: $([Math]::Round($parDuration, 2)) сек" -ForegroundColor Green
        
        # Расчет ускорения
        $speedup = $seqDuration / $parDuration
        Write-Host "`n  РЕЗУЛЬТАТ:" -ForegroundColor Cyan
        Write-Host "  • Ускорение: $([Math]::Round($speedup, 2))x" -ForegroundColor $(if ($speedup -ge 2) { "Green" } else { "Yellow" })
        
        if ($speedup -ge 1.5) {
            Write-Host "  ✓ Параллелизм обеспечивает значительное ускорение" -ForegroundColor Green
        } elseif ($speedup -ge 1.1) {
            Write-Host "  ⊖ Параллелизм дает умеренное ускорение" -ForegroundColor Yellow
        } else {
            Write-Host "  ⊖ Параллелизм не дал ускорения" -ForegroundColor Gray
        }
        
        # Проверка корректности результатов
        if (@($seqResults).Count -eq $itemCount -and @($parResults).Count -eq $itemCount) {
            Write-Host "  ✓ Все элементы обработаны в обоих режимах" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Потеряны элементы: seq=$(@($seqResults).Count), par=$(@($parResults).Count)" -ForegroundColor Red
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
║              Этап 6: Параллелизация                       ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

$startTime = Get-Date

try {
    # Запуск тестов
    $parallelPassed = Test-ParallelProcessor
    $performancePassed = Test-Performance
    
    # Итоги
    Write-Host "`n`n " -NoNewline
    Write-Host ("+" + "=" * 60) -ForegroundColor Cyan
    Write-Host "  РЕЗУЛЬТАТЫ ТЕСТИРОВАНИЯ" -ForegroundColor Cyan
    Write-Host ("=" * 61) -ForegroundColor Cyan
    
    $results = @(
        @{ Name = "ParallelProcessor.ps1"; Passed = $parallelPassed },
        @{ Name = "Тест производительности"; Passed = $performancePassed }
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
        Write-Host "Этап 6 (Параллелизация) завершен." -ForegroundColor Green
        Write-Host "Можно переходить к Этапу 7 (Главный оркестратор).`n" -ForegroundColor Cyan
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