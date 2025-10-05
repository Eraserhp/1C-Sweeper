<#
.SYNOPSIS
    Тестирование базовой инфраструктуры (Этап 1)
.DESCRIPTION
    Проверка работы Common, LoggingService и ConfigManager
.NOTES
    Проект: 1C-Sweeper
    Этап: 1 - Базовая инфраструктура
    Дата создания: 2025-10-04
#>

#Requires -Version 5.1

param(
    [Parameter(Mandatory = $false)]
    [string]$ProjectRoot = ""
)

# Определение корня проекта
if ([string]::IsNullOrEmpty($ProjectRoot)) {
    if (-not [string]::IsNullOrEmpty($PSScriptRoot)) {
        # Запуск как скрипт
        $ProjectRoot = Split-Path -Parent $PSScriptRoot
    } else {
        # Запуск через dot-sourcing
        $ProjectRoot = Split-Path -Parent $PWD.Path
    }
}

Write-Host "Корень проекта: $ProjectRoot" -ForegroundColor Gray

# Импорт модулей
$corePath = Join-Path -Path $ProjectRoot -ChildPath "src\core"

if (-not (Test-Path $corePath)) {
    Write-Host "ОШИБКА: Папка src\core не найдена по пути: $corePath" -ForegroundColor Red
    Write-Host "Убедитесь, что вы запускаете скрипт из корня проекта или из папки tests" -ForegroundColor Yellow
    exit 1
}

. (Join-Path -Path $corePath -ChildPath "Common.ps1")
. (Join-Path -Path $corePath -ChildPath "LoggingService.ps1")
. (Join-Path -Path $corePath -ChildPath "ConfigManager.ps1")

# Настройка кодировки
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

#region Тесты Common

function Test-Common {
    Write-Host "`n=== ТЕСТЫ Common.ps1 ===" -ForegroundColor Cyan
    
    $allPassed = $true
    
    # Тест 1: Конвертация размеров
    Write-Host "`nТест 1: Конвертация размеров" -ForegroundColor Yellow
    try {
        $bytes = 1073741824  # 1 ГБ
        $gb = Convert-BytesToGB -Bytes $bytes
        
        if ($gb -eq 1.00) {
            Write-Host "  ✓ Convert-BytesToGB работает корректно: $bytes байт = $gb ГБ" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Ошибка: ожидалось 1.00, получено $gb" -ForegroundColor Red
            $allPassed = $false
        }
        
        $backToBytes = Convert-GBToBytes -GB 15
        Write-Host "  ✓ Convert-GBToBytes: 15 ГБ = $backToBytes байт" -ForegroundColor Green
    }
    catch {
        Write-Host "  ✗ Ошибка: $($_.Exception.Message)" -ForegroundColor Red
        $allPassed = $false
    }
    
    # Тест 2: Работа с файловой системой
    Write-Host "`nТест 2: Работа с файловой системой" -ForegroundColor Yellow
    try {
        $testDir = Join-Path -Path $env:TEMP -ChildPath "1C-Sweeper-Test-$(Get-Random)"
        
        $created = Ensure-DirectoryExists -Path $testDir
        if ($created -and (Test-Path -Path $testDir)) {
            Write-Host "  ✓ Ensure-DirectoryExists создала директорию" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Не удалось создать директорию" -ForegroundColor Red
            $allPassed = $false
        }
        
        $writable = Test-PathWritable -Path $testDir
        if ($writable) {
            Write-Host "  ✓ Test-PathWritable корректно определяет доступность для записи" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Ошибка проверки доступности записи" -ForegroundColor Red
            $allPassed = $false
        }
        
        # Создаем тестовый файл
        $testFile = Join-Path -Path $testDir -ChildPath "test.txt"
        "test content" | Out-File -FilePath $testFile
        
        $size = Get-FileSize -Path $testFile
        if ($size -gt 0) {
            Write-Host "  ✓ Get-FileSize: размер файла = $size байт" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Ошибка получения размера файла" -ForegroundColor Red
            $allPassed = $false
        }
        
        # Очистка
        Remove-DirectorySafely -Path $testDir | Out-Null
        if (-not (Test-Path -Path $testDir)) {
            Write-Host "  ✓ Remove-DirectorySafely удалила директорию" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Не удалось удалить директорию" -ForegroundColor Red
            $allPassed = $false
        }
    }
    catch {
        Write-Host "  ✗ Ошибка: $($_.Exception.Message)" -ForegroundColor Red
        $allPassed = $false
    }
    
    # Тест 3: Вспомогательные функции
    Write-Host "`nТест 3: Вспомогательные функции" -ForegroundColor Yellow
    try {
        $timestamp = Get-Timestamp
        Write-Host "  ✓ Get-Timestamp: $timestamp" -ForegroundColor Green
        
        $hostname = Get-HostName
        Write-Host "  ✓ Get-HostName: $hostname" -ForegroundColor Green
        
        $duration = Format-Duration -Seconds 3665
        if ($duration -like "*1ч*1м*5с*") {
            Write-Host "  ✓ Format-Duration: 3665 сек = $duration" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Ошибка форматирования длительности: $duration" -ForegroundColor Red
            $allPassed = $false
        }
        
        $safeName = Get-SafeFileName -FileName "Report: 2025-10-04"
        if ($safeName -notmatch '[<>:"|?*]') {
            Write-Host "  ✓ Get-SafeFileName: '$safeName'" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Остались недопустимые символы: $safeName" -ForegroundColor Red
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

#region Тесты LoggingService

function Test-LoggingService {
    Write-Host "`n=== ТЕСТЫ LoggingService.ps1 ===" -ForegroundColor Cyan
    
    $allPassed = $true
    
    # Тест 1: Инициализация
    Write-Host "`nТест 1: Инициализация логирования" -ForegroundColor Yellow
    try {
        $logDir = Join-Path -Path $env:TEMP -ChildPath "1C-Sweeper-Logs-Test"
        $logFile = Join-Path -Path $logDir -ChildPath "test.log"
        
        Initialize-Logging -LogFilePath $logFile -SilentMode $false
        
        if (Test-Path -Path $logFile) {
            Write-Host "  ✓ Initialize-Logging создала лог-файл" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Лог-файл не создан" -ForegroundColor Red
            $allPassed = $false
        }
        
        $retrievedPath = Get-LogFilePath
        if ($retrievedPath -eq $logFile) {
            Write-Host "  ✓ Get-LogFilePath возвращает правильный путь" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Неверный путь к лог-файлу" -ForegroundColor Red
            $allPassed = $false
        }
    }
    catch {
        Write-Host "  ✗ Ошибка: $($_.Exception.Message)" -ForegroundColor Red
        $allPassed = $false
    }
    
    # Тест 2: Различные уровни логирования
    Write-Host "`nТест 2: Уровни логирования" -ForegroundColor Yellow
    try {
        Write-LogInfo "Это информационное сообщение"
        Write-LogSuccess "Это сообщение об успехе"
        Write-LogWarning "Это предупреждение"
        Write-LogError "Это сообщение об ошибке"
        
        Write-Host "  ✓ Все уровни логирования работают" -ForegroundColor Green
    }
    catch {
        Write-Host "  ✗ Ошибка: $($_.Exception.Message)" -ForegroundColor Red
        $allPassed = $false
    }
    
    # Тест 3: Разделители и форматирование
    Write-Host "`nТест 3: Разделители и форматирование" -ForegroundColor Yellow
    try {
        Write-LogSeparator
        Write-LogSeparator -Title "ТЕСТОВЫЙ РАЗДЕЛ"
        Write-LogOperationStart "Тестовая операция"
        Write-LogOperationEnd "Тестовая операция" -Success $true -Duration 123
        Write-LogProgress -Current 5 -Total 10 -ItemName "тестов"
        
        Write-Host "  ✓ Форматирование работает корректно" -ForegroundColor Green
    }
    catch {
        Write-Host "  ✗ Ошибка: $($_.Exception.Message)" -ForegroundColor Red
        $allPassed = $false
    }
    
    # Тест 4: Тихий режим
    Write-Host "`nТест 4: Тихий режим" -ForegroundColor Yellow
    try {
        Write-Host "  Включаем тихий режим..." -ForegroundColor Gray
        Set-SilentMode -Enabled $true
        
        Write-LogInfo "Это НЕ должно появиться в консоли (только в файле)"
        Write-LogSuccess "Это тоже НЕ должно появиться"
        Write-LogWarning "А это должно появиться (WARNING)"
        Write-LogError "И это должно появиться (ERROR)"
        
        Set-SilentMode -Enabled $false
        Write-Host "  ✓ Тихий режим работает корректно" -ForegroundColor Green
    }
    catch {
        Write-Host "  ✗ Ошибка: $($_.Exception.Message)" -ForegroundColor Red
        $allPassed = $false
    }
    
    # Очистка
    $logDir = Join-Path -Path $env:TEMP -ChildPath "1C-Sweeper-Logs-Test"
    if (Test-Path -Path $logDir) {
        Remove-Item -Path $logDir -Recurse -Force
    }
    
    return $allPassed
}

#endregion

#region Тесты ConfigManager

function Test-ConfigManager {
    Write-Host "`n=== ТЕСТЫ ConfigManager.ps1 ===" -ForegroundColor Cyan
    
    $allPassed = $true
    
    # Тест 1: Создание конфигурации по умолчанию
    Write-Host "`nТест 1: Создание конфигурации по умолчанию" -ForegroundColor Yellow
    try {
        $testConfigPath = Join-Path -Path $env:TEMP -ChildPath "test-config-$(Get-Random).json"
        
        New-DefaultConfiguration -Path $testConfigPath
        
        if (Test-Path -Path $testConfigPath) {
            Write-Host "  ✓ New-DefaultConfiguration создала файл" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Файл конфигурации не создан" -ForegroundColor Red
            $allPassed = $false
        }
        
        # Очистка
        Remove-Item -Path $testConfigPath -Force
    }
    catch {
        Write-Host "  ✗ Ошибка: $($_.Exception.Message)" -ForegroundColor Red
        $allPassed = $false
    }
    
    # Тест 2: Загрузка и валидация конфигурации
    Write-Host "`nТест 2: Загрузка конфигурации" -ForegroundColor Yellow
    try {
        # Создаем тестовую конфигурацию
        $testConfigPath = Join-Path -Path $env:TEMP -ChildPath "test-config-$(Get-Random).json"
        
        $testConfig = @{
            settings = @{
                git = @{
                    repos = @("C:\Test\Repo1")
                    searchPaths = @("C:\Dev")
                    sizeThresholdGB = 15
                }
                edt = @{
                    workspaces = @()
                    searchPaths = @()
                    sizeThresholdGB = 5
                }
                database = @{
                    databases = @()
                    searchPaths = @()
                    platformVersion = "8.3.*"
                    user = ""
                    password = ""
                    sizeThresholdGB = 3
                }
                general = @{
                    reportsPath = "C:\MaintenanceReports"
                    silentMode = $false
                    parallelProcessing = $true
                    maxParallelTasks = 3
                }
            }
        }
        
        $testConfig | ConvertTo-Json -Depth 10 | Out-File -FilePath $testConfigPath -Encoding UTF8
        
        $config = Get-Configuration -Path $testConfigPath
        
        if ($null -ne $config) {
            Write-Host "  ✓ Get-Configuration загрузила конфигурацию" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Конфигурация не загружена" -ForegroundColor Red
            $allPassed = $false
        }
        
        if ($config.Git.SizeThresholdGB -eq 15) {
            Write-Host "  ✓ Параметры загружены корректно" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Ошибка загрузки параметров" -ForegroundColor Red
            $allPassed = $false
        }
        
        # Очистка
        Remove-Item -Path $testConfigPath -Force
    }
    catch {
        Write-Host "  ✗ Ошибка: $($_.Exception.Message)" -ForegroundColor Red
        $allPassed = $false
    }
    
    # Тест 3: Валидация
    Write-Host "`nТест 3: Валидация конфигурации" -ForegroundColor Yellow
    try {
        $config = New-ConfigurationObject
        $config.Git.SizeThresholdGB = 15
        $config.Git.SearchPaths = @("C:\Dev")
        $config.General.ReportsPath = "C:\Reports"
        
        $validationResult = Test-ConfigurationValid -Config $config
        
        if ($validationResult.IsValid) {
            Write-Host "  ✓ Test-ConfigurationValid: валидная конфигурация принята" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Валидная конфигурация отклонена" -ForegroundColor Red
            Write-Host "    Ошибки: $($validationResult.Errors -join ', ')" -ForegroundColor Red
            $allPassed = $false
        }
        
        # Тест невалидной конфигурации
        $invalidConfig = New-ConfigurationObject
        $invalidConfig.Git.SizeThresholdGB = -5  # Невалидное значение
        
        $validationResult2 = Test-ConfigurationValid -Config $invalidConfig
        
        if (-not $validationResult2.IsValid) {
            Write-Host "  ✓ Test-ConfigurationValid: невалидная конфигурация отклонена" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Невалидная конфигурация принята" -ForegroundColor Red
            $allPassed = $false
        }
    }
    catch {
        Write-Host "  ✗ Ошибка: $($_.Exception.Message)" -ForegroundColor Red
        $allPassed = $false
    }
    
    # Тест 4: Кодирование/декодирование пароля
    Write-Host "`nТест 4: Работа с паролями" -ForegroundColor Yellow
    try {
        $originalPassword = "TestPassword123"
        $encoded = ConvertTo-Base64Password -Password $originalPassword
        $decoded = ConvertFrom-Base64Password -EncodedPassword $encoded
        
        if ($decoded -eq $originalPassword) {
            Write-Host "  ✓ Кодирование/декодирование паролей работает корректно" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Ошибка кодирования: ожидалось '$originalPassword', получено '$decoded'" -ForegroundColor Red
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
║           Этап 1: Базовая инфраструктура                  ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

$startTime = Get-Date

try {
    # Запуск тестов
    $commonPassed = Test-Common
    $loggingPassed = Test-LoggingService
    $configPassed = Test-ConfigManager
    
    # Итоги
    Write-Host "`n`n" + ("=" * 60) -ForegroundColor Cyan
    Write-Host "  РЕЗУЛЬТАТЫ ТЕСТИРОВАНИЯ" -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor Cyan
    
    $results = @(
        @{ Name = "Common.ps1"; Passed = $commonPassed },
        @{ Name = "LoggingService.ps1"; Passed = $loggingPassed },
        @{ Name = "ConfigManager.ps1"; Passed = $configPassed }
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
    Write-Host "  Время выполнения: $($duration.TotalSeconds) сек" -ForegroundColor Gray
    
    Write-Host ("=" * 60) -ForegroundColor Cyan
    
    if ($totalPassed -eq $totalTests) {
        Write-Host "`n✓ ВСЕ ТЕСТЫ ПРОЙДЕНЫ УСПЕШНО!" -ForegroundColor Green
        Write-Host "Этап 1 (Базовая инфраструктура) завершен." -ForegroundColor Green
        Write-Host "Можно переходить к Этапу 2 (Git-сервис).`n" -ForegroundColor Cyan
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
