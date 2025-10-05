<#
.SYNOPSIS
    Тестирование EDT-сервиса (Этап 3)
.DESCRIPTION
    Проверка работы EdtService и EdtDiscovery
.NOTES
    Проект: 1C-Sweeper
    Этап: 3 - EDT-сервис
    Дата создания: 2025-10-05
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
. (Join-Path -Path $servicesPath -ChildPath "EdtService.ps1")
. (Join-Path -Path $discoveryPath -ChildPath "EdtDiscovery.ps1")

# Настройка кодировки и логирования
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# Инициализация логирования
$logPath = Join-Path -Path $env:TEMP -ChildPath "edt-test-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
Initialize-Logging -LogFilePath $logPath -SilentMode $false

#region Тесты EdtService

function Test-EdtService {
    Write-Host "`n=== ТЕСТЫ EdtService.ps1 ===" -ForegroundColor Cyan
    
    $allPassed = $true
    
    # Тест 1: Распознавание workspace
    Write-Host "`nТест 1: Распознавание EDT workspace" -ForegroundColor Yellow
    try {
        # Создаем фейковый workspace
        $testWsPath = Join-Path -Path $env:TEMP -ChildPath "EdtWorkspaceTest-$(Get-Random)"
        $metadataPath = Join-Path -Path $testWsPath -ChildPath ".metadata"
        New-Item -Path $metadataPath -ItemType Directory -Force | Out-Null
        
        $isWorkspace = Test-IsEdtWorkspace -Path $testWsPath
        if ($isWorkspace) {
            Write-Host "  ✓ Фейковый workspace распознан корректно" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Не удалось распознать workspace" -ForegroundColor Red
            $allPassed = $false
        }
        
        # Проверка обычной папки
        $normalDir = Join-Path -Path $env:TEMP -ChildPath "NormalDir-$(Get-Random)"
        New-Item -Path $normalDir -ItemType Directory -Force | Out-Null
        
        $isNotWorkspace = -not (Test-IsEdtWorkspace -Path $normalDir)
        if ($isNotWorkspace) {
            Write-Host "  ✓ Правильно определена обычная папка (не workspace)" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Обычная папка ошибочно распознана как workspace" -ForegroundColor Red
            $allPassed = $false
        }
        
        # Очистка
        Remove-Item -Path $testWsPath -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $normalDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    catch {
        Write-Host "  ✗ Ошибка: $($_.Exception.Message)" -ForegroundColor Red
        $allPassed = $false
    }
    
    # Тест 2: Получение размера workspace
    Write-Host "`nТест 2: Получение размера workspace" -ForegroundColor Yellow
    try {
        # Создаем тестовый workspace с файлами
        $testWsPath = Join-Path -Path $env:TEMP -ChildPath "EdtWorkspaceTest-$(Get-Random)"
        $metadataPath = Join-Path -Path $testWsPath -ChildPath ".metadata"
        New-Item -Path $metadataPath -ItemType Directory -Force | Out-Null
        
        # Создаем несколько тестовых файлов
        1..5 | ForEach-Object {
            $testFile = Join-Path -Path $metadataPath -ChildPath "testfile$_.log"
            "Test content $(Get-Random)" * 1000 | Out-File -FilePath $testFile
        }
        
        $size = Get-EdtWorkspaceSize -Path $testWsPath
        $sizeGB = Convert-BytesToGB -Bytes $size
        
        if ($size -gt 0) {
            Write-Host "  ✓ Размер workspace: $sizeGB ГБ ($size байт)" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Не удалось получить размер workspace" -ForegroundColor Red
            $allPassed = $false
        }
        
        # Очистка
        Remove-Item -Path $testWsPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    catch {
        Write-Host "  ✗ Ошибка: $($_.Exception.Message)" -ForegroundColor Red
        $allPassed = $false
    }
    
    # Тест 3: Очистка логов
    Write-Host "`nТест 3: Очистка логов" -ForegroundColor Yellow
    try {
        # Создаем workspace с логами
        $testWsPath = Join-Path -Path $env:TEMP -ChildPath "EdtWorkspaceTest-$(Get-Random)"
        $metadataPath = Join-Path -Path $testWsPath -ChildPath ".metadata"
        $pluginsPath = Join-Path -Path $metadataPath -ChildPath ".plugins"
        New-Item -Path $pluginsPath -ItemType Directory -Force | Out-Null
        
        # Создаем основной лог
        $mainLog = Join-Path -Path $metadataPath -ChildPath ".log"
        "Main log content" * 100 | Out-File -FilePath $mainLog
        
        # Создаем логи плагинов
        $plugin1Path = Join-Path -Path $pluginsPath -ChildPath "plugin1"
        New-Item -Path $plugin1Path -ItemType Directory -Force | Out-Null
        $pluginLog = Join-Path -Path $plugin1Path -ChildPath "plugin.log"
        "Plugin log" * 50 | Out-File -FilePath $pluginLog
        
        # Очистка
        $result = Clear-EdtLogs -WorkspacePath $testWsPath
        
        if ($result.Success) {
            Write-Host "  ✓ Логи очищены успешно" -ForegroundColor Green
            Write-Host "  ✓ Освобождено: $(Convert-BytesToGB -Bytes $result.SizeFreed) ГБ" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Ошибка очистки логов" -ForegroundColor Red
            $allPassed = $false
        }
        
        # Проверка, что файлы удалены
        if (-not (Test-Path $mainLog)) {
            Write-Host "  ✓ Основной лог удален" -ForegroundColor Green
        }
        
        # Очистка
        Remove-Item -Path $testWsPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    catch {
        Write-Host "  ✗ Ошибка: $($_.Exception.Message)" -ForegroundColor Red
        $allPassed = $false
    }
    
    # Тест 4: Очистка кэша и индексов
    Write-Host "`nТест 4: Очистка кэша и индексов" -ForegroundColor Yellow
    try {
        # Создаем workspace с кэшем и индексами
        $testWsPath = Join-Path -Path $env:TEMP -ChildPath "EdtWorkspaceTest-$(Get-Random)"
        $metadataPath = Join-Path -Path $testWsPath -ChildPath ".metadata"
        $pluginsPath = Join-Path -Path $metadataPath -ChildPath ".plugins"
        $cachePath = Join-Path -Path $pluginsPath -ChildPath "some.plugin\cache"
        $indexPath = Join-Path -Path $pluginsPath -ChildPath "another.plugin\index"
        
        New-Item -Path $cachePath -ItemType Directory -Force | Out-Null
        New-Item -Path $indexPath -ItemType Directory -Force | Out-Null
        
        # Создаем файлы в кэше и индексах
        "Cache data" * 100 | Out-File -FilePath (Join-Path $cachePath "cache.dat")
        "Index data" * 100 | Out-File -FilePath (Join-Path $indexPath "index.dat")
        
        # Очистка кэша
        $cacheResult = Clear-EdtCache -WorkspacePath $testWsPath
        if ($cacheResult.Success) {
            Write-Host "  ✓ Кэш очищен" -ForegroundColor Green
        }
        
        # Очистка индексов
        $indexResult = Clear-EdtIndexes -WorkspacePath $testWsPath
        if ($indexResult.Success) {
            Write-Host "  ✓ Индексы очищены" -ForegroundColor Green
        }
        
        # Очистка
        Remove-Item -Path $testWsPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    catch {
        Write-Host "  ✗ Ошибка: $($_.Exception.Message)" -ForegroundColor Red
        $allPassed = $false
    }
    
    return $allPassed
}

#endregion

#region Тесты EdtDiscovery

function Test-EdtDiscovery {
    Write-Host "`n=== ТЕСТЫ EdtDiscovery.ps1 ===" -ForegroundColor Cyan
    
    $allPassed = $true
    
    # Тест 1: Поиск workspace в папке
    Write-Host "`nТест 1: Поиск workspace в папке" -ForegroundColor Yellow
    try {
        # Создаем структуру для теста
        $testDir = Join-Path -Path $env:TEMP -ChildPath "EdtDiscoveryTest-$(Get-Random)"
        $ws1Path = Join-Path -Path $testDir -ChildPath "Workspace1"
        $ws2Path = Join-Path -Path $testDir -ChildPath "Workspace2"
        $normalDir = Join-Path -Path $testDir -ChildPath "NotWorkspace"
        
        # Создаем workspace
        New-Item -Path (Join-Path $ws1Path ".metadata") -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path $ws2Path ".metadata") -ItemType Directory -Force | Out-Null
        New-Item -Path $normalDir -ItemType Directory -Force | Out-Null
        
        # Поиск
        $found = Find-EdtWorkspaces -SearchPath $testDir -MaxDepth 1
        
        if ($found.Count -eq 2) {
            Write-Host "  ✓ Найдено workspace: $($found.Count)" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Ожидалось 2, найдено: $($found.Count)" -ForegroundColor Red
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
        # Создаем тестовый workspace
        $explicitWs = Join-Path -Path $env:TEMP -ChildPath "ExplicitWs-$(Get-Random)"
        New-Item -Path (Join-Path $explicitWs ".metadata") -ItemType Directory -Force | Out-Null
        
        # Получаем все workspace
        $all = Get-AllEdtWorkspaces -ExplicitPaths @($explicitWs) -SearchPaths @() -SizeThresholdGB 0
        
        if ($all.Count -ge 1) {
            Write-Host "  ✓ Явный workspace обработан корректно" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Явный workspace не найден" -ForegroundColor Red
            $allPassed = $false
        }
        
        # Очистка
        Remove-Item -Path $explicitWs -Recurse -Force -ErrorAction SilentlyContinue
    }
    catch {
        Write-Host "  ✗ Ошибка: $($_.Exception.Message)" -ForegroundColor Red
        $allPassed = $false
    }
    
    # Тест 3: Фильтрация по размеру
    Write-Host "`nТест 3: Фильтрация по размеру" -ForegroundColor Yellow
    try {
        # Создаем маленький workspace
        $smallWs = Join-Path -Path $env:TEMP -ChildPath "SmallWs-$(Get-Random)"
        New-Item -Path (Join-Path $smallWs ".metadata") -ItemType Directory -Force | Out-Null
        
        # Фильтрация с большим порогом
        $filtered = Get-FilteredEdtWorkspaces -Workspaces @($smallWs) -SizeThresholdGB 999
        
        if ($filtered.Count -eq 0) {
            Write-Host "  ✓ Фильтрация по размеру работает" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Ошибка фильтрации" -ForegroundColor Red
            $allPassed = $false
        }
        
        # Фильтрация с нулевым порогом
        $allWs = Get-FilteredEdtWorkspaces -Workspaces @($smallWs) -SizeThresholdGB 0
        
        if ($allWs.Count -eq 1) {
            Write-Host "  ✓ При нулевом пороге все workspace включены" -ForegroundColor Green
        }
        
        # Очистка
        Remove-Item -Path $smallWs -Recurse -Force -ErrorAction SilentlyContinue
    }
    catch {
        Write-Host "  ✗ Ошибка: $($_.Exception.Message)" -ForegroundColor Red
        $allPassed = $false
    }
    
    return $allPassed
}

#endregion

#region Интеграционный тест

function Test-Integration {
    Write-Host "`n=== ИНТЕГРАЦИОННЫЙ ТЕСТ ===" -ForegroundColor Cyan
    
    $allPassed = $true
    
    Write-Host "`nИнтеграционный тест: Полное обслуживание workspace" -ForegroundColor Yellow
    try {
        # Создаем реалистичный тестовый workspace
        $testWsPath = Join-Path -Path $env:TEMP -ChildPath "IntegrationTestWs-$(Get-Random)"
        $metadataPath = Join-Path -Path $testWsPath -ChildPath ".metadata"
        $pluginsPath = Join-Path -Path $metadataPath -ChildPath ".plugins"
        
        Write-Host "  Создание тестового workspace: $testWsPath" -ForegroundColor Gray
        
        # Создаем структуру workspace
        New-Item -Path $pluginsPath -ItemType Directory -Force | Out-Null
        
        # Создаем логи
        $mainLog = Join-Path -Path $metadataPath -ChildPath ".log"
        1..100 | ForEach-Object { "Log entry $_" } | Out-File -FilePath $mainLog
        
        # Создаем кэш
        $cachePath = Join-Path -Path $pluginsPath -ChildPath "org.eclipse.core\cache"
        New-Item -Path $cachePath -ItemType Directory -Force | Out-Null
        1..50 | ForEach-Object {
            "Cache data $_" * 10 | Out-File -FilePath (Join-Path $cachePath "cache_$_.dat")
        }
        
        # Создаем индексы
        $indexPath = Join-Path -Path $pluginsPath -ChildPath "org.eclipse.jdt.core\index"
        New-Item -Path $indexPath -ItemType Directory -Force | Out-Null
        1..30 | ForEach-Object {
            "Index data $_" * 10 | Out-File -FilePath (Join-Path $indexPath "index_$_.idx")
        }
        
        Write-Host "  Запуск обслуживания...`n" -ForegroundColor Gray
        
        # Выполняем обслуживание
        $result = Invoke-EdtMaintenance -WorkspacePath $testWsPath
        
        if ($result.Success) {
            Write-Host "`n  ✓ Обслуживание выполнено успешно!" -ForegroundColor Green
            Write-Host "  ✓ Размер до:      $(Convert-BytesToGB -Bytes $result.SizeBefore) ГБ" -ForegroundColor Green
            Write-Host "  ✓ Размер после:   $(Convert-BytesToGB -Bytes $result.SizeAfter) ГБ" -ForegroundColor Green
            Write-Host "  ✓ Освобождено:    $(Convert-BytesToGB -Bytes $result.SpaceSaved) ГБ" -ForegroundColor Green
            Write-Host "  ✓ Время:          $($result.Duration) сек" -ForegroundColor Green
            Write-Host "  ✓ Действия:       $($result.Actions -join ', ')" -ForegroundColor Green
            
            if ($result.SpaceSaved -gt 0) {
                Write-Host "  ✓ Место успешно освобождено" -ForegroundColor Green
            }
        } else {
            Write-Host "  ✗ Обслуживание завершено с ошибками" -ForegroundColor Red
            Write-Host "  Ошибки: $($result.Errors -join ', ')" -ForegroundColor Red
            $allPassed = $false
        }
        
        # Очистка
        Remove-Item -Path $testWsPath -Recurse -Force -ErrorAction SilentlyContinue
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
║              Этап 3: EDT-сервис                           ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

$startTime = Get-Date

try {
    # Запуск тестов
    $edtServicePassed = Test-EdtService
    $edtDiscoveryPassed = Test-EdtDiscovery
    $integrationPassed = Test-Integration
    
    # Итоги
    Write-Host "`n`n " -NoNewline
    Write-Host ("+" + "=" * 60) -ForegroundColor Cyan
    Write-Host "  РЕЗУЛЬТАТЫ ТЕСТИРОВАНИЯ" -ForegroundColor Cyan
    Write-Host ("=" * 61) -ForegroundColor Cyan
    
    $results = @(
        @{ Name = "EdtService.ps1"; Passed = $edtServicePassed },
        @{ Name = "EdtDiscovery.ps1"; Passed = $edtDiscoveryPassed },
        @{ Name = "Интеграционный тест"; Passed = $integrationPassed }
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
        Write-Host "Этап 3 (EDT-сервис) завершен." -ForegroundColor Green
        Write-Host "Можно переходить к Этапу 4 (Database-сервис).`n" -ForegroundColor Cyan
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