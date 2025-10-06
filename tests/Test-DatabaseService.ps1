<#
.SYNOPSIS
    Тестирование Database-сервиса (Этап 4)
.DESCRIPTION
    Проверка работы DatabaseService, DatabaseDiscovery и PlatformDiscovery
.NOTES
    Проект: 1C-Sweeper
    Этап: 4 - Database-сервис
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
$servicesPath = Join-Path -Path $ProjectRoot -ChildPath "src\services"
$discoveryPath = Join-Path -Path $ProjectRoot -ChildPath "src\discovery"

if (-not (Test-Path $corePath)) {
    Write-Host "ОШИБКА: Папка src\core не найдена" -ForegroundColor Red
    exit 1
}

. (Join-Path -Path $corePath -ChildPath "Common.ps1")
. (Join-Path -Path $corePath -ChildPath "LoggingService.ps1")
. (Join-Path -Path $corePath -ChildPath "ConfigManager.ps1")
. (Join-Path -Path $discoveryPath -ChildPath "PlatformDiscovery.ps1")
. (Join-Path -Path $servicesPath -ChildPath "DatabaseService.ps1")
. (Join-Path -Path $discoveryPath -ChildPath "DatabaseDiscovery.ps1")

# Настройка кодировки и логирования
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# Инициализация логирования
$logPath = Join-Path -Path $env:TEMP -ChildPath "database-test-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
Initialize-Logging -LogFilePath $logPath -SilentMode $false

#region Тесты PlatformDiscovery

function Test-PlatformDiscovery {
    Write-Host "`n=== ТЕСТЫ PlatformDiscovery.ps1 ===" -ForegroundColor Cyan
    
    $allPassed = $true
    
    # Тест 1: Парсинг версий
    Write-Host "`nТест 1: Парсинг версий" -ForegroundColor Yellow
    try {
        $version1 = ConvertTo-VersionObject -VersionString "8.3.27.1486"
        
        if ($version1.Major -eq 8 -and $version1.Minor -eq 3 -and $version1.Patch -eq 27 -and $version1.Build -eq 1486) {
            Write-Host "  ✓ Парсинг версии работает корректно" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Ошибка парсинга версии" -ForegroundColor Red
            $allPassed = $false
        }
        
        # Сравнение версий
        $version2 = ConvertTo-VersionObject -VersionString "8.3.28.1000"
        $compareResult = Compare-Versions -Version1 $version1 -Version2 $version2
        
        if ($compareResult -lt 0) {
            Write-Host "  ✓ Сравнение версий работает корректно (8.3.27 < 8.3.28)" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Ошибка сравнения версий" -ForegroundColor Red
            $allPassed = $false
        }
    }
    catch {
        Write-Host "  ✗ Ошибка: $($_.Exception.Message)" -ForegroundColor Red
        $allPassed = $false
    }
    
    # Тест 2: Проверка масок
    Write-Host "`nТест 2: Проверка масок версий" -ForegroundColor Yellow
    try {
        $version = ConvertTo-VersionObject -VersionString "8.3.27.1486"
        
        # Точное совпадение
        $match1 = Test-VersionMatchesMask -Version $version -Mask "8.3.27"
        if ($match1) {
            Write-Host "  ✓ Маска '8.3.27' соответствует версии 8.3.27.1486" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Ошибка: должна соответствовать" -ForegroundColor Red
            $allPassed = $false
        }
        
        # Wildcard
        $match2 = Test-VersionMatchesMask -Version $version -Mask "8.3.*"
        if ($match2) {
            Write-Host "  ✓ Маска '8.3.*' соответствует версии 8.3.27.1486" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Ошибка: должна соответствовать" -ForegroundColor Red
            $allPassed = $false
        }
        
        # Не соответствует
        $match3 = Test-VersionMatchesMask -Version $version -Mask "8.4.*"
        if (-not $match3) {
            Write-Host "  ✓ Маска '8.4.*' не соответствует версии 8.3.27.1486 (правильно)" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Ошибка: не должна соответствовать" -ForegroundColor Red
            $allPassed = $false
        }
        
        # Пустая маска
        $match4 = Test-VersionMatchesMask -Version $version -Mask ""
        if ($match4) {
            Write-Host "  ✓ Пустая маска соответствует любой версии" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "  ✗ Ошибка: $($_.Exception.Message)" -ForegroundColor Red
        $allPassed = $false
    }
    
    # Тест 3: Поиск установленных платформ
    Write-Host "`nТест 3: Поиск установленных платформ" -ForegroundColor Yellow
    try {
        Write-Host "  Запуск поиска платформ..." -ForegroundColor Gray
        
        $platforms = Get-InstalledPlatforms
        
        if (@($platforms).Count -gt 0) {
            Write-Host "  ✓ Найдено платформ: $(@($platforms).Count)" -ForegroundColor Green
            
            foreach ($platform in $platforms) {
                Write-Host "    • $($platform.Version.Original) - $($platform.Path)" -ForegroundColor Gray
            }
        } else {
            Write-Host "  ⊖ Платформы 1С не установлены (это нормально для тестовой среды)" -ForegroundColor Gray
        }
    }
    catch {
        Write-Host "  ✗ Ошибка: $($_.Exception.Message)" -ForegroundColor Red
        $allPassed = $false
    }
    
    # Тест 4: Find-Platform1C
    Write-Host "`nТест 4: Find-Platform1C" -ForegroundColor Yellow
    try {
        Write-Host "  Поиск платформы без маски..." -ForegroundColor Gray
        
        $result = Find-Platform1C -VersionMask ""
        
        if ($result.Success) {
            Write-Host "  ✓ Платформа найдена: $($result.Platform.Version.Original)" -ForegroundColor Green
        } else {
            Write-Host "  ⊖ Платформа не найдена: $($result.Error)" -ForegroundColor Gray
            Write-Host "  (Это нормально, если 1С не установлена)" -ForegroundColor Gray
        }
    }
    catch {
        Write-Host "  ✗ Ошибка: $($_.Exception.Message)" -ForegroundColor Red
        $allPassed = $false
    }
    
    return $allPassed
}

#endregion

#region Тесты DatabaseService

function Test-DatabaseService {
    Write-Host "`n=== ТЕСТЫ DatabaseService.ps1 ===" -ForegroundColor Cyan
    
    $allPassed = $true
    
    # Тест 1: Распознавание базы
    Write-Host "`nТест 1: Распознавание базы 1С" -ForegroundColor Yellow
    try {
        # Создаем фейковый файл .1CD
        $testDbPath = Join-Path -Path $env:TEMP -ChildPath "TestDB-$(Get-Random).1CD"
        "test content" | Out-File -FilePath $testDbPath
        
        $isDb = Test-Is1CDatabase -Path $testDbPath
        if ($isDb) {
            Write-Host "  ✓ Файл .1CD распознан как база" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Не удалось распознать базу" -ForegroundColor Red
            $allPassed = $false
        }
        
        # Проверка НЕ-базы
        $normalFile = Join-Path -Path $env:TEMP -ChildPath "NotDB-$(Get-Random).txt"
        "test" | Out-File -FilePath $normalFile
        
        $isNotDb = -not (Test-Is1CDatabase -Path $normalFile)
        if ($isNotDb) {
            Write-Host "  ✓ Правильно определен обычный файл (не база)" -ForegroundColor Green
        }
        
        # Очистка
        Remove-Item -Path $testDbPath -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $normalFile -Force -ErrorAction SilentlyContinue
    }
    catch {
        Write-Host "  ✗ Ошибка: $($_.Exception.Message)" -ForegroundColor Red
        $allPassed = $false
    }
    
    # Тест 2: Получение размера базы
    Write-Host "`nТест 2: Получение размера базы" -ForegroundColor Yellow
    try {
        # Создаем тестовую базу с контентом
        $testDbPath = Join-Path -Path $env:TEMP -ChildPath "TestDB-$(Get-Random).1CD"
        1..100 | ForEach-Object { "Test data line $_" } | Out-File -FilePath $testDbPath
        
        $size = Get-DatabaseSize -DbPath $testDbPath
        $sizeGB = Convert-BytesToGB -Bytes $size
        
        if ($size -gt 0) {
            Write-Host "  ✓ Размер базы: $sizeGB ГБ ($size байт)" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Не удалось получить размер" -ForegroundColor Red
            $allPassed = $false
        }
        
        # Очистка
        Remove-Item -Path $testDbPath -Force -ErrorAction SilentlyContinue
    }
    catch {
        Write-Host "  ✗ Ошибка: $($_.Exception.Message)" -ForegroundColor Red
        $allPassed = $false
    }
    
    # Тест 3: Проверка доступности
    Write-Host "`nТест 3: Проверка доступности базы" -ForegroundColor Yellow
    try {
        $testDbPath = Join-Path -Path $env:TEMP -ChildPath "TestDB-$(Get-Random).1CD"
        "test" | Out-File -FilePath $testDbPath
        
        $available = Test-DatabaseAvailable -DbPath $testDbPath
        if ($available) {
            Write-Host "  ✓ База доступна для обслуживания" -ForegroundColor Green
        } else {
            Write-Host "  ⊖ База недоступна (может быть заблокирована)" -ForegroundColor Gray
        }
        
        # Очистка
        Remove-Item -Path $testDbPath -Force -ErrorAction SilentlyContinue
    }
    catch {
        Write-Host "  ✗ Ошибка: $($_.Exception.Message)" -ForegroundColor Red
        $allPassed = $false
    }
    
    return $allPassed
}

#endregion

#region Тесты DatabaseDiscovery

function Test-DatabaseDiscovery {
    Write-Host "`n=== ТЕСТЫ DatabaseDiscovery.ps1 ===" -ForegroundColor Cyan
    
    $allPassed = $true
    
    # Тест 1: Поиск баз в папке
    Write-Host "`nТест 1: Поиск баз в папке" -ForegroundColor Yellow
    try {
        # Создаем структуру для теста
        $testDir = Join-Path -Path $env:TEMP -ChildPath "DbDiscoveryTest-$(Get-Random)"
        $db1Path = Join-Path -Path $testDir -ChildPath "Database1\1Cv8.1CD"
        $db2Path = Join-Path -Path $testDir -ChildPath "Database2\1Cv8.1CD"
        $normalFile = Join-Path -Path $testDir -ChildPath "NotDB.txt"
        
        # Создаем файлы
        New-Item -Path (Split-Path $db1Path) -ItemType Directory -Force | Out-Null
        New-Item -Path (Split-Path $db2Path) -ItemType Directory -Force | Out-Null
        
        "test" | Out-File -FilePath $db1Path
        "test" | Out-File -FilePath $db2Path
        "test" | Out-File -FilePath $normalFile
        
        # Поиск
        $found = @(Find-Databases -SearchPath $testDir -MaxDepth 2)
        
        if (@($found).Count -eq 2) {
            Write-Host "  ✓ Найдено баз: $(@($found).Count)" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Ожидалось 2, найдено: $(@($found).Count)" -ForegroundColor Red
            $allPassed = $false
        }
        
        # Очистка
        Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    catch {
        Write-Host "  ✗ Ошибка: $($_.Exception.Message)" -ForegroundColor Red
        $allPassed = $false
    }
    
    # Тест 2: Объединение явных путей и автопоиска
    Write-Host "`nТест 2: Объединение явных путей и автопоиска" -ForegroundColor Yellow
    try {
        # Создаем тестовую базу
        $explicitDb = Join-Path -Path $env:TEMP -ChildPath "ExplicitDB-$(Get-Random).1CD"
        "test" | Out-File -FilePath $explicitDb
        
        # Получаем все базы
        $all = @(Get-AllDatabases -ExplicitDatabases @($explicitDb) -SearchPaths @() -SizeThresholdGB 0)
        
        if (@($all).Count -ge 1) {
            Write-Host "  ✓ Явная база обработана корректно" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Явная база не найдена" -ForegroundColor Red
            $allPassed = $false
        }
        
        # Очистка
        Remove-Item -Path $explicitDb -Force -ErrorAction SilentlyContinue
    }
    catch {
        Write-Host "  ✗ Ошибка: $($_.Exception.Message)" -ForegroundColor Red
        $allPassed = $false
    }
    
    # Тест 3: Фильтрация по размеру
    Write-Host "`nТест 3: Фильтрация по размеру" -ForegroundColor Yellow
    try {
        # Создаем маленькую базу
        $smallDb = Join-Path -Path $env:TEMP -ChildPath "SmallDB-$(Get-Random).1CD"
        "test" | Out-File -FilePath $smallDb
        
        # Фильтрация с большим порогом
        $filtered = @(Get-FilteredDatabases -Databases @($smallDb) -SizeThresholdGB 999)
        
        if (@($filtered).Count -eq 0) {
            Write-Host "  ✓ Фильтрация по размеру работает" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Ошибка фильтрации" -ForegroundColor Red
            $allPassed = $false
        }
        
        # Фильтрация с нулевым порогом
        $allDbs = @(Get-FilteredDatabases -Databases @($smallDb) -SizeThresholdGB 0)
        
        if (@($allDbs).Count -eq 1) {
            Write-Host "  ✓ При нулевом пороге все базы включены" -ForegroundColor Green
        }
        
        # Очистка
        Remove-Item -Path $smallDb -Force -ErrorAction SilentlyContinue
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
║              Этап 4: Database-сервис                      ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

$startTime = Get-Date

try {
    # Запуск тестов
    $platformPassed = Test-PlatformDiscovery
    $databaseServicePassed = Test-DatabaseService
    $databaseDiscoveryPassed = Test-DatabaseDiscovery
    
    # Итоги
    Write-Host "`n`n " -NoNewline
    Write-Host ("+" + "=" * 60) -ForegroundColor Cyan
    Write-Host "  РЕЗУЛЬТАТЫ ТЕСТИРОВАНИЯ" -ForegroundColor Cyan
    Write-Host ("=" * 61) -ForegroundColor Cyan
    
    $results = @(
        @{ Name = "PlatformDiscovery.ps1"; Passed = $platformPassed },
        @{ Name = "DatabaseService.ps1"; Passed = $databaseServicePassed },
        @{ Name = "DatabaseDiscovery.ps1"; Passed = $databaseDiscoveryPassed }
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
        Write-Host "Этап 4 (Database-сервис) завершен." -ForegroundColor Green
        Write-Host "Можно переходить к Этапу 5 (Отчетность).`n" -ForegroundColor Cyan
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