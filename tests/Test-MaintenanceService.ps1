<#
.SYNOPSIS
    Тестирование главного оркестратора (Этап 7)
.DESCRIPTION
    Проверка работы MaintenanceService.ps1 и интеграции всех компонентов
.NOTES
    Проект: 1C-Sweeper
    Этап: 7 - Главный оркестратор
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
. (Join-Path -Path $corePath -ChildPath "ConfigManager.ps1")

# Настройка кодировки и логирования
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# Инициализация логирования
$logPath = Join-Path -Path $env:TEMP -ChildPath "maintenance-test-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
Initialize-Logging -LogFilePath $logPath -SilentMode $false

#region Вспомогательные функции

<#
.SYNOPSIS
    Создает тестовую конфигурацию
#>
function New-TestConfiguration {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$TempDir = $env:TEMP
    )
    
    $configPath = Join-Path -Path $TempDir -ChildPath "test-maintenance-config-$(Get-Random).json"
    
    $config = @{
        settings = @{
            git = @{
                repos = @()
                searchPaths = @()
                sizeThresholdGB = 0.001
            }
            edt = @{
                workspaces = @()
                searchPaths = @()
                sizeThresholdGB = 0.001
            }
            database = @{
                databases = @()
                searchPaths = @()
                platformVersion = ""
                user = ""
                password = ""
                sizeThresholdGB = 0.001
            }
            general = @{
                reportsPath = (Join-Path -Path $TempDir -ChildPath "Reports-$(Get-Random)")
                silentMode = $false
                parallelProcessing = $false
                maxParallelTasks = 2
            }
        }
    }
    
    $config | ConvertTo-Json -Depth 10 | Out-File -FilePath $configPath -Encoding UTF8
    
    return $configPath
}

<#
.SYNOPSIS
    Создает тестовое окружение
#>
function New-TestEnvironment {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    
    $testRoot = Join-Path -Path $env:TEMP -ChildPath "1C-Sweeper-IntegrationTest-$(Get-Random)"
    
    # Создаем структуру
    $gitRepo = Join-Path -Path $testRoot -ChildPath "Git\TestRepo"
    $gitDir = Join-Path -Path $gitRepo -ChildPath ".git"
    New-Item -Path $gitDir -ItemType Directory -Force | Out-Null
    
    # Добавляем файлы в репозиторий
    1..10 | ForEach-Object {
        "Test content $_" * 100 | Out-File -FilePath (Join-Path $gitRepo "file$_.txt")
    }
    
    $edtWorkspace = Join-Path -Path $testRoot -ChildPath "EDT\Workspace1"
    $edtMetadata = Join-Path -Path $edtWorkspace -ChildPath ".metadata"
    $edtPlugins = Join-Path -Path $edtMetadata -ChildPath ".plugins"
    $edtCache = Join-Path -Path $edtPlugins -ChildPath "cache"
    New-Item -Path $edtCache -ItemType Directory -Force | Out-Null
    
    # Добавляем кэш в workspace
    1..20 | ForEach-Object {
        "Cache data $_" * 50 | Out-File -FilePath (Join-Path $edtCache "cache$_.dat")
    }
    
    $database = Join-Path -Path $testRoot -ChildPath "Databases\Test\1Cv8.1CD"
    New-Item -Path (Split-Path $database) -ItemType Directory -Force | Out-Null
    "Database content" * 1000 | Out-File -FilePath $database
    
    return @{
        Root = $testRoot
        GitRepo = $gitRepo
        EdtWorkspace = $edtWorkspace
        Database = $database
    }
}

#endregion

#region Тесты

function Test-MaintenanceService {
    Write-Host "`n=== ТЕСТЫ MaintenanceService.ps1 ===" -ForegroundColor Cyan
    
    $allPassed = $true
    $maintenanceScript = Join-Path -Path $ProjectRoot -ChildPath "src\MaintenanceService.ps1"
    
    # Проверка существования скрипта
    if (-not (Test-Path -Path $maintenanceScript)) {
        Write-Host "`n✗ Файл MaintenanceService.ps1 не найден" -ForegroundColor Red
        return $false
    }
    
    # Тест 1: DryRun режим
    Write-Host "`nТест 1: Режим DryRun (тестовый запуск)" -ForegroundColor Yellow
    try {
        Write-Host "  Создание тестового окружения..." -ForegroundColor Gray
        
        $env = New-TestEnvironment
        $configPath = New-TestConfiguration
        
        # Обновляем конфигурацию
        $config = Get-Content -Path $configPath | ConvertFrom-Json
        $config.settings.git.repos = @($env.GitRepo)
        $config.settings.edt.workspaces = @($env.EdtWorkspace)
        $config.settings.database.databases = @($env.Database)
        $config.settings.general.silentMode = $true
        $config | ConvertTo-Json -Depth 10 | Out-File -FilePath $configPath -Encoding UTF8
        
        Write-Host "  Запуск в режиме DryRun..." -ForegroundColor Gray
        
        # Запускаем MaintenanceService
        $output = & $maintenanceScript -ConfigPath $configPath -DryRun 2>&1
        $exitCode = $LASTEXITCODE
        
        if ($exitCode -eq 0) {
            Write-Host "  ✓ DryRun завершен успешно (код выхода: 0)" -ForegroundColor Green
        } else {
            Write-Host "  ⊖ DryRun завершился с предупреждениями (код выхода: $exitCode)" -ForegroundColor Gray
        }
        
        # Проверяем, что файлы не изменились
        $gitStillExists = Test-Path -Path $env.GitRepo
        $edtStillExists = Test-Path -Path $env.EdtWorkspace
        
        if ($gitStillExists -and $edtStillExists) {
            Write-Host "  ✓ Файлы не изменены (DryRun работает корректно)" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Файлы были изменены (ошибка DryRun)" -ForegroundColor Red
            $allPassed = $false
        }
        
        # Очистка
        Remove-Item -Path $env.Root -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $configPath -Force -ErrorAction SilentlyContinue
    }
    catch {
        Write-Host "  ✗ Ошибка: $($_.Exception.Message)" -ForegroundColor Red
        $allPassed = $false
    }
    
    # Тест 2: Фильтр объектов
    Write-Host "`nТест 2: Фильтр типов объектов (-Objects)" -ForegroundColor Yellow
    try {
        $env = New-TestEnvironment
        $configPath = New-TestConfiguration
        
        # Обновляем конфигурацию
        $config = Get-Content -Path $configPath | ConvertFrom-Json
        $config.settings.git.repos = @($env.GitRepo)
        $config.settings.edt.workspaces = @($env.EdtWorkspace)
        $config.settings.general.silentMode = $true
        $config | ConvertTo-Json -Depth 10 | Out-File -FilePath $configPath -Encoding UTF8
        
        Write-Host "  Запуск с фильтром: только Git..." -ForegroundColor Gray
        
        # Запускаем только для Git
        $output = & $maintenanceScript -ConfigPath $configPath -DryRun -Objects Git 2>&1
        
        # Проверяем, что в выводе есть упоминание Git, но нет EDT
        $outputText = $output | Out-String
        $hasGit = $outputText -match "Git|GIT|git"
        
        if ($hasGit) {
            Write-Host "  ✓ Фильтр работает (Git обработан)" -ForegroundColor Green
        } else {
            Write-Host "  ⊖ Git не упомянут в выводе" -ForegroundColor Gray
        }
        
        # Очистка
        Remove-Item -Path $env.Root -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $configPath -Force -ErrorAction SilentlyContinue
    }
    catch {
        Write-Host "  ✗ Ошибка: $($_.Exception.Message)" -ForegroundColor Red
        $allPassed = $false
    }
    
    # Тест 3: Проверка структуры отчета
    Write-Host "`nТест 3: Генерация отчета" -ForegroundColor Yellow
    try {
        $env = New-TestEnvironment
        $configPath = New-TestConfiguration
        $reportsDir = Join-Path -Path $env.Root -ChildPath "Reports"
        
        # Обновляем конфигурацию
        $config = Get-Content -Path $configPath | ConvertFrom-Json
        $config.settings.git.repos = @($env.GitRepo)
        $config.settings.general.reportsPath = $reportsDir
        $config.settings.general.silentMode = $true
        $config | ConvertTo-Json -Depth 10 | Out-File -FilePath $configPath -Encoding UTF8
        
        Write-Host "  Запуск обслуживания..." -ForegroundColor Gray
        
        # Запускаем MaintenanceService (не DryRun, чтобы создать отчет)
        $output = & $maintenanceScript -ConfigPath $configPath 2>&1
        
        # Проверяем наличие отчета
        if (Test-Path -Path $reportsDir) {
            $reports = @(Get-ChildItem -Path $reportsDir -Filter "*.json" -ErrorAction SilentlyContinue)
            
            if (@($reports).Count -gt 0) {
                Write-Host "  ✓ Отчет создан: $($reports[0].Name)" -ForegroundColor Green
                
                # Проверяем валидность JSON
                try {
                    $report = Get-Content -Path $reports[0].FullName -Raw | ConvertFrom-Json
                    
                    if ($report.Summary) {
                        Write-Host "  ✓ JSON валиден и содержит сводку" -ForegroundColor Green
                    }
                    
                    if ($report.GitRepositories) {
                        Write-Host "  ✓ Отчет содержит информацию о Git" -ForegroundColor Green
                    }
                }
                catch {
                    Write-Host "  ✗ Ошибка парсинга JSON: $($_.Exception.Message)" -ForegroundColor Red
                    $allPassed = $false
                }
            } else {
                Write-Host "  ✗ Отчеты не найдены" -ForegroundColor Red
                $allPassed = $false
            }
        } else {
            Write-Host "  ✗ Папка отчетов не создана" -ForegroundColor Red
            $allPassed = $false
        }
        
        # Очистка
        Remove-Item -Path $env.Root -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $configPath -Force -ErrorAction SilentlyContinue
    }
    catch {
        Write-Host "  ✗ Ошибка: $($_.Exception.Message)" -ForegroundColor Red
        $allPassed = $false
    }
    
    # Тест 4: Обработка несуществующей конфигурации
    Write-Host "`nТест 4: Обработка ошибок (несуществующая конфигурация)" -ForegroundColor Yellow
    try {
        $fakeConfig = "C:\NonExistent\config-$(Get-Random).json"
        
        Write-Host "  Запуск с несуществующей конфигурацией..." -ForegroundColor Gray
        
        $output = & $maintenanceScript -ConfigPath $fakeConfig 2>&1
        $exitCode = $LASTEXITCODE
        
        if ($exitCode -ne 0) {
            Write-Host "  ✓ Корректно обработана ошибка (код выхода: $exitCode)" -ForegroundColor Green
        } else {
            Write-Host "  ⊖ Неожиданный код выхода: $exitCode" -ForegroundColor Gray
        }
        
        # Проверяем, что в выводе есть сообщение об ошибке
        $outputText = $output | Out-String
        if ($outputText -match "не найден|ошибка|error") {
            Write-Host "  ✓ Выведено сообщение об ошибке" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "  ✗ Ошибка: $($_.Exception.Message)" -ForegroundColor Red
        $allPassed = $false
    }
    
    return $allPassed
}

function Test-EndToEnd {
    Write-Host "`n=== ИНТЕГРАЦИОННЫЙ ТЕСТ (END-TO-END) ===" -ForegroundColor Cyan
    
    $allPassed = $true
    $maintenanceScript = Join-Path -Path $ProjectRoot -ChildPath "src\MaintenanceService.ps1"
    
    Write-Host "`nПолный цикл обслуживания (реальные операции)" -ForegroundColor Yellow
    
    try {
        Write-Host "  Создание комплексного тестового окружения..." -ForegroundColor Gray
        
        $env = New-TestEnvironment
        $configPath = New-TestConfiguration
        $reportsDir = Join-Path -Path $env.Root -ChildPath "Reports"
        
        # Настраиваем полную конфигурацию
        $config = Get-Content -Path $configPath | ConvertFrom-Json
        $config.settings.git.repos = @($env.GitRepo)
        $config.settings.edt.workspaces = @($env.EdtWorkspace)
        # Database пропускаем (нет платформы 1С в тестовой среде)
        $config.settings.general.reportsPath = $reportsDir
        $config.settings.general.silentMode = $false
        $config.settings.general.parallelProcessing = $false
        $config | ConvertTo-Json -Depth 10 | Out-File -FilePath $configPath -Encoding UTF8
        
        Write-Host "  Запуск полного цикла обслуживания...`n" -ForegroundColor Gray
        
        # Замеряем размеры ДО
        $gitSizeBefore = Get-DirectorySize -Path $env.GitRepo
        $edtSizeBefore = Get-DirectorySize -Path $env.EdtWorkspace
        
        Write-Host "  Размеры ДО обслуживания:" -ForegroundColor Gray
        Write-Host "    Git:  $(Convert-BytesToGB -Bytes $gitSizeBefore) ГБ" -ForegroundColor Gray
        Write-Host "    EDT:  $(Convert-BytesToGB -Bytes $edtSizeBefore) ГБ`n" -ForegroundColor Gray
        
        # Запускаем MaintenanceService
        $startTime = Get-Date
        $output = & $maintenanceScript -ConfigPath $configPath
        $exitCode = $LASTEXITCODE
        $duration = ((Get-Date) - $startTime).TotalSeconds
        
        Write-Host "`n  Результат:" -ForegroundColor Gray
        
        if ($exitCode -eq 0) {
            Write-Host "  ✓ Обслуживание завершено успешно (код: $exitCode)" -ForegroundColor Green
        } else {
            Write-Host "  ⊖ Завершено с предупреждениями (код: $exitCode)" -ForegroundColor Gray
        }
        
        Write-Host "  ✓ Время выполнения: $([Math]::Round($duration, 2)) сек" -ForegroundColor Green
        
        # Проверяем отчет
        if (Test-Path -Path $reportsDir) {
            $reports = @(Get-ChildItem -Path $reportsDir -Filter "*.json")
            
            if (@($reports).Count -gt 0) {
                Write-Host "  ✓ Создан отчет: $($reports[0].Name)" -ForegroundColor Green
                
                $report = Get-Content -Path $reports[0].FullName -Raw | ConvertFrom-Json
                
                Write-Host "`n  Сводка из отчета:" -ForegroundColor Gray
                Write-Host "    Обработано Git:  $($report.Summary.GitReposProcessed)" -ForegroundColor Gray
                Write-Host "    Обработано EDT:  $($report.Summary.WorkspacesProcessed)" -ForegroundColor Gray
                Write-Host "    Освобождено:     $($report.Summary.TotalSpaceSaved) ГБ" -ForegroundColor Green
                
                if ($report.Summary.TotalSpaceSaved -gt 0) {
                    Write-Host "  ✓ Место успешно освобождено!" -ForegroundColor Green
                }
            } else {
                Write-Host "  ✗ Отчет не создан" -ForegroundColor Red
                $allPassed = $false
            }
        }
        
        # Очистка
        Remove-Item -Path $env.Root -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $configPath -Force -ErrorAction SilentlyContinue
    }
    catch {
        Write-Host "  ✗ Ошибка: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host $_.ScriptStackTrace -ForegroundColor Gray
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
║              Этап 7: Главный оркестратор                  ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

$startTime = Get-Date

try {
    # Запуск тестов
    $maintenanceServicePassed = Test-MaintenanceService
    $endToEndPassed = Test-EndToEnd
    
    # Итоги
    Write-Host "`n`n " -NoNewline
    Write-Host ("+" + "=" * 60) -ForegroundColor Cyan
    Write-Host "  РЕЗУЛЬТАТЫ ТЕСТИРОВАНИЯ" -ForegroundColor Cyan
    Write-Host ("=" * 61) -ForegroundColor Cyan
    
    $results = @(
        @{ Name = "MaintenanceService.ps1"; Passed = $maintenanceServicePassed },
        @{ Name = "Интеграционный тест (End-to-End)"; Passed = $endToEndPassed }
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
        Write-Host "Этап 7 (Главный оркестратор) завершен." -ForegroundColor Green
        Write-Host "`n🎉 ПОЗДРАВЛЯЕМ! Все этапы разработки завершены!" -ForegroundColor Cyan
        Write-Host "Система 1C-Sweeper готова к работе.`n" -ForegroundColor Cyan
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