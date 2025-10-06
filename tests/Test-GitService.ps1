<#
.SYNOPSIS
    Тестирование Git-сервиса (Этап 2)
.DESCRIPTION
    Проверка работы GitService и GitDiscovery
.NOTES
    Проект: 1C-Sweeper
    Этап: 2 - Git-сервис
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

. (Join-Path -Path $corePath -ChildPath "Common.ps1")
. (Join-Path -Path $corePath -ChildPath "LoggingService.ps1")
. (Join-Path -Path $servicesPath -ChildPath "GitService.ps1")
. (Join-Path -Path $discoveryPath -ChildPath "GitDiscovery.ps1")

# Настройка кодировки
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# Инициализация логирования
Initialize-Logging -SilentMode $false

#region Тесты GitService

function Test-GitService {
    Write-Host "`n=== ТЕСТЫ GitService.ps1 ===" -ForegroundColor Cyan
    
    $allPassed = $true
    
    # Тест 1: Проверка доступности Git
    Write-Host "`nТест 1: Проверка доступности Git" -ForegroundColor Yellow
    try {
        $gitAvailable = Test-GitAvailable
        
        if ($gitAvailable) {
            $gitVersion = git --version
            Write-Host "  ✓ Git доступен: $gitVersion" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Git не установлен или недоступен" -ForegroundColor Red
            Write-Host "  ВНИМАНИЕ: Для полного тестирования необходим Git!" -ForegroundColor Yellow
            $allPassed = $false
        }
    }
    catch {
        Write-Host "  ✗ Ошибка: $($_.Exception.Message)" -ForegroundColor Red
        $allPassed = $false
    }
    
    # Тест 2: Проверка распознавания репозитория
    Write-Host "`nТест 2: Распознавание Git-репозитория" -ForegroundColor Yellow
    try {
        # Проверяем, не является ли сам проект Git-репозиторием
        $isRepo = Test-IsGitRepository -Path $ProjectRoot
        
        if ($isRepo) {
            Write-Host "  ✓ Корень проекта распознан как Git-репозиторий" -ForegroundColor Green
            
            # Получаем размер
            $size = Get-GitRepositorySize -RepoPath $ProjectRoot
            $sizeGB = Convert-BytesToGB -Bytes $size
            Write-Host "  ✓ Размер репозитория: $sizeGB ГБ" -ForegroundColor Green
        } else {
            Write-Host "  ⊖ Корень проекта не является Git-репозиторием (это нормально)" -ForegroundColor Gray
        }
        
        # Тестируем на несуществующем пути
        $tempDir = Join-Path -Path $env:TEMP -ChildPath "NotARepo-$(Get-Random)"
        New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
        
        $isNotRepo = Test-IsGitRepository -Path $tempDir
        if (-not $isNotRepo) {
            Write-Host "  ✓ Правильно определена обычная папка (не репозиторий)" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Ошибка: обычная папка определена как репозиторий" -ForegroundColor Red
            $allPassed = $false
        }
        
        Remove-Item -Path $tempDir -Force
    }
    catch {
        Write-Host "  ✗ Ошибка: $($_.Exception.Message)" -ForegroundColor Red
        $allPassed = $false
    }
    
    # Тест 3: Выполнение Git-команды (если Git доступен и есть репозиторий)
    Write-Host "`nТест 3: Выполнение Git-команд" -ForegroundColor Yellow
    try {
        $gitAvailable = Test-GitAvailable
        $isRepo = Test-IsGitRepository -Path $ProjectRoot
        
        if ($gitAvailable -and $isRepo) {
            Write-Host "  Выполнение тестовой команды: git status" -ForegroundColor Gray
            
            $result = Invoke-GitCommand -RepoPath $ProjectRoot -Command "status --short"
            
            if ($result.Success) {
                Write-Host "  ✓ Команда выполнена успешно (код: $($result.ExitCode))" -ForegroundColor Green
                Write-Host "  ✓ Длительность: $($result.Duration) сек" -ForegroundColor Green
            } else {
                Write-Host "  ✗ Команда завершилась с ошибкой" -ForegroundColor Red
                $allPassed = $false
            }
        } else {
            Write-Host "  ⊖ Пропущено (нет Git или репозитория для тестирования)" -ForegroundColor Gray
        }
    }
    catch {
        Write-Host "  ✗ Ошибка: $($_.Exception.Message)" -ForegroundColor Red
        $allPassed = $false
    }
    
    return $allPassed
}

#endregion

#region Тесты GitDiscovery

function Test-GitDiscovery {
    Write-Host "`n=== ТЕСТЫ GitDiscovery.ps1 ===" -ForegroundColor Cyan
    
    $allPassed = $true
    
    # Тест 1: Поиск репозиториев
    Write-Host "`nТест 1: Поиск репозиториев в папке" -ForegroundColor Yellow
    try {
        # Создаем тестовую структуру
        $testRoot = Join-Path -Path $env:TEMP -ChildPath "GitDiscoveryTest-$(Get-Random)"
        New-Item -Path $testRoot -ItemType Directory -Force | Out-Null
        
        # Создаем "фейковый" репозиторий (просто папка .git)
        $fakeRepo = Join-Path -Path $testRoot -ChildPath "FakeRepo"
        $fakeGitDir = Join-Path -Path $fakeRepo -ChildPath ".git"
        New-Item -Path $fakeGitDir -ItemType Directory -Force | Out-Null
        
        # Ищем
        $found = Find-GitRepositories -SearchPath $testRoot -MaxDepth 1
        
        if (@($found).Count -eq 1 -and $found[0] -eq $fakeRepo) {
            Write-Host "  ✓ Репозиторий найден корректно" -ForegroundColor Green
        } elseif (@($found).Count -eq 1) {
            Write-Host "  ✗ Найден неверный путь: $($found[0])" -ForegroundColor Red
            $allPassed = $false
        } else {
            Write-Host "  ✗ Найдено неверное количество: $($found.Count)" -ForegroundColor Red
            $allPassed = $false
        }
        
        # Очистка
        Remove-Item -Path $testRoot -Recurse -Force
    }
    catch {
        Write-Host "  ✗ Ошибка: $($_.Exception.Message)" -ForegroundColor Red
        $allPassed = $false
    }
    
    # Тест 2: Объединение явных и найденных
    Write-Host "`nТест 2: Объединение явных путей и автопоиска" -ForegroundColor Yellow
    try {
        # Если корень проекта - это репозиторий, используем его
        if (Test-IsGitRepository -Path $ProjectRoot) {
            $result = Get-AllGitRepositories `
                -ExplicitRepos @($ProjectRoot) `
                -SearchPaths @()
            
            if ($result.TotalCount -ge 1) {
                Write-Host "  ✓ Явные репозитории обработаны корректно" -ForegroundColor Green
            } else {
                Write-Host "  ✗ Ошибка обработки явных путей" -ForegroundColor Red
                $allPassed = $false
            }
        } else {
            Write-Host "  ⊖ Пропущено (нет репозитория для тестирования)" -ForegroundColor Gray
        }
    }
    catch {
        Write-Host "  ✗ Ошибка: $($_.Exception.Message)" -ForegroundColor Red
        $allPassed = $false
    }
    
    # Тест 3: Фильтрация по размеру
    Write-Host "`nТест 3: Фильтрация по размеру" -ForegroundColor Yellow
    try {
        if (Test-IsGitRepository -Path $ProjectRoot) {
            $size = Get-GitRepositorySize -RepoPath $ProjectRoot
            $sizeGB = Convert-BytesToGB -Bytes $size
            
            # Фильтруем с порогом выше размера репозитория
            $result = Filter-GitRepositoriesBySize `
                -Repositories @($ProjectRoot) `
                -MinSizeGB ($sizeGB + 1)
            
            if ($result.BelowThreshold.Count -eq 1) {
                Write-Host "  ✓ Фильтрация по минимальному размеру работает" -ForegroundColor Green
            } else {
                Write-Host "  ✗ Ошибка фильтрации" -ForegroundColor Red
                $allPassed = $false
            }
            
            # Фильтруем с порогом ниже размера
            $result2 = Filter-GitRepositoriesBySize `
                -Repositories @($ProjectRoot) `
                -MinSizeGB 0.0
            
            if ($result2.Matched.Count -eq 1) {
                Write-Host "  ✓ Репозитории, подходящие по размеру, правильно выбраны" -ForegroundColor Green
            } else {
                Write-Host "  ✗ Ошибка выбора подходящих репозиториев" -ForegroundColor Red
                $allPassed = $false
            }
        } else {
            Write-Host "  ⊖ Пропущено (нет репозитория для тестирования)" -ForegroundColor Gray
        }
    }
    catch {
        Write-Host "  ✗ Ошибка: $($_.Exception.Message)" -ForegroundColor Red
        $allPassed = $false
    }
    
    return $allPassed
}

#endregion

#region Интеграционный тест

function Test-GitIntegration {
    Write-Host "`n=== ИНТЕГРАЦИОННЫЙ ТЕСТ ===" -ForegroundColor Cyan
    
    $allPassed = $true
    
    Write-Host "`nИнтеграционный тест: Полное обслуживание репозитория" -ForegroundColor Yellow
    
    try {
        if (-not (Test-GitAvailable)) {
            Write-Host "  ⊖ Пропущено (Git не доступен)" -ForegroundColor Gray
            return $true
        }
        
        if (-not (Test-IsGitRepository -Path $ProjectRoot)) {
            Write-Host "  ⊖ Пропущено (нет репозитория для тестирования)" -ForegroundColor Gray
            return $true
        }
        
        Write-Host "  ВНИМАНИЕ: Будет выполнено обслуживание текущего репозитория!" -ForegroundColor Yellow
        Write-Host "  Репозиторий: $ProjectRoot" -ForegroundColor Gray
        Write-Host "  Это безопасная операция, но займет некоторое время." -ForegroundColor Gray
        Write-Host ""
        
        $response = Read-Host "  Продолжить? (Y/N)"
        
        if ($response -ne 'Y' -and $response -ne 'y') {
            Write-Host "  ⊖ Пропущено пользователем" -ForegroundColor Gray
            return $true
        }
        
        Write-Host ""
        Write-Host "  Запуск обслуживания..." -ForegroundColor Cyan
        
        $result = Invoke-GitMaintenance `
            -RepoPath $ProjectRoot `
            -SizeThresholdGB 0.0 `
            -SkipFsck $true
        
        if ($result.Success -and -not $result.Skipped) {
            Write-Host "`n  ✓ Обслуживание выполнено успешно!" -ForegroundColor Green
            Write-Host "  ✓ Размер до:      $($result.SizeBefore) ГБ" -ForegroundColor Green
            Write-Host "  ✓ Размер после:   $($result.SizeAfter) ГБ" -ForegroundColor Green
            Write-Host "  ✓ Освобождено:    $($result.SpaceSaved) ГБ" -ForegroundColor Green
            Write-Host "  ✓ Время:          $($result.Duration) сек" -ForegroundColor Green
            Write-Host "  ✓ Действия:       $($result.Actions -join ', ')" -ForegroundColor Green
        }
        elseif ($result.Skipped) {
            Write-Host "`n  ⊖ Обслуживание пропущено (размер ниже порога)" -ForegroundColor Gray
        }
        else {
            Write-Host "`n  ✗ Обслуживание завершилось с ошибками" -ForegroundColor Red
            Write-Host "  Ошибки: $($result.Errors -join ', ')" -ForegroundColor Red
            $allPassed = $false
        }
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
║              Этап 2: Git-сервис                           ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

$startTime = Get-Date

try {
    # Запуск тестов
    $gitServicePassed = Test-GitService
    $gitDiscoveryPassed = Test-GitDiscovery
    $integrationPassed = Test-GitIntegration
    
    # Итоги
    Write-Host "`n`n" + ("=" * 60) -ForegroundColor Cyan
    Write-Host "  РЕЗУЛЬТАТЫ ТЕСТИРОВАНИЯ" -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor Cyan
    
    $results = @(
        @{ Name = "GitService.ps1"; Passed = $gitServicePassed },
        @{ Name = "GitDiscovery.ps1"; Passed = $gitDiscoveryPassed },
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
    
    Write-Host ("=" * 60) -ForegroundColor Cyan
    
    if ($totalPassed -eq $totalTests) {
        Write-Host "`n✓ ВСЕ ТЕСТЫ ПРОЙДЕНЫ УСПЕШНО!" -ForegroundColor Green
        Write-Host "Этап 2 (Git-сервис) завершен." -ForegroundColor Green
        Write-Host "Можно переходить к Этапу 3 (EDT-сервис).`n" -ForegroundColor Cyan
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