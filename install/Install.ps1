<#
.SYNOPSIS
    Установщик 1C-Sweeper
.DESCRIPTION
    Интерактивная установка и настройка системы автоматизированного обслуживания
.NOTES
    Проект: 1C-Sweeper
    Версия: 1.0
    Дата создания: 2025-10-06
    
    Требования:
    - PowerShell 5.1+
    - Права администратора (для настройки планировщика)
    - Git (опционально)
    - 1С:Предприятие (опционально)
#>

#Requires -Version 5.1
#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$Silent,
    
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Настройка кодировки
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

#region Определение путей

$scriptPath = if ($PSScriptRoot) { 
    $PSScriptRoot 
} elseif ($MyInvocation.MyCommand.Path) {
    Split-Path -Parent $MyInvocation.MyCommand.Path
} else {
    $PWD.Path
}

$projectRoot = Split-Path -Parent $scriptPath
$srcPath = Join-Path -Path $projectRoot -ChildPath "src"
$corePath = Join-Path -Path $srcPath -ChildPath "core"

# Импорт модулей
. (Join-Path -Path $corePath -ChildPath "Common.ps1")
. (Join-Path -Path $corePath -ChildPath "LoggingService.ps1")
. (Join-Path -Path $corePath -ChildPath "ConfigManager.ps1")

$discoveryPath = Join-Path -Path $srcPath -ChildPath "discovery"
. (Join-Path -Path $discoveryPath -ChildPath "GitDiscovery.ps1")
. (Join-Path -Path $discoveryPath -ChildPath "EdtDiscovery.ps1")
. (Join-Path -Path $discoveryPath -ChildPath "DatabaseDiscovery.ps1")
. (Join-Path -Path $discoveryPath -ChildPath "PlatformDiscovery.ps1")

#endregion

#region Константы

$INSTALLER_VERSION = "1.0"
$DEFAULT_INSTALL_PATH = "C:\1C-Sweeper"
$DEFAULT_CONFIG_PATH = Join-Path -Path $DEFAULT_INSTALL_PATH -ChildPath "config"
$DEFAULT_REPORTS_PATH = Join-Path -Path $DEFAULT_INSTALL_PATH -ChildPath "reports"
$TASK_NAME = "1C-Sweeper-Maintenance"

#endregion

#region Вспомогательные функции

function Write-Banner {
    Clear-Host
    Write-Host @"

╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║                      1C-SWEEPER                           ║
║          Система автоматизированного обслуживания         ║
║                                                           ║
║                  УСТАНОВЩИК v$INSTALLER_VERSION                        ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan
}

function Write-Step {
    param([string]$Text)
    Write-Host "`n[$Text]" -ForegroundColor Yellow
    Write-Host ("=" * 60) -ForegroundColor Yellow
}

function Write-Info {
    param([string]$Text)
    Write-Host "  $Text" -ForegroundColor White
}

function Write-StatusOK {
    param([string]$Text)
    Write-Host "  ✓ $Text" -ForegroundColor Green
}

function Write-StatusFail {
    param([string]$Text)
    Write-Host "  ✗ $Text" -ForegroundColor Red
}

function Write-StatusWarn {
    param([string]$Text)
    Write-Host "  ⚠ $Text" -ForegroundColor Yellow
}

function Read-YesNo {
    param(
        [string]$Prompt,
        [bool]$Default = $true
    )
    
    $defaultChar = if ($Default) { "Y" } else { "N" }
    $response = Read-Host "$Prompt [Y/N] (по умолчанию: $defaultChar)"
    
    if ([string]::IsNullOrWhiteSpace($response)) {
        return $Default
    }
    
    return ($response -eq 'Y' -or $response -eq 'y')
}

function Read-PathWithDefault {
    param(
        [string]$Prompt,
        [string]$Default
    )
    
    Write-Host "  $Prompt" -ForegroundColor Cyan
    Write-Host "  По умолчанию: $Default" -ForegroundColor Gray
    $response = Read-Host "  Путь"
    
    if ([string]::IsNullOrWhiteSpace($response)) {
        return $Default
    }
    
    return $response
}

#endregion

#region Проверка требований

function Test-SystemRequirements {
    Write-Step "Проверка системных требований"
    
    $requirements = @{
        PowerShell = $false
        Git = $false
        Platform1C = $false
        Administrator = $false
    }
    
    # PowerShell версия
    $psVersion = $PSVersionTable.PSVersion
    if ($psVersion.Major -ge 5) {
        Write-StatusOK "PowerShell $($psVersion.Major).$($psVersion.Minor)"
        $requirements.PowerShell = $true
    } else {
        Write-StatusFail "PowerShell версии меньше 5.1"
    }
    
    # Права администратора
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($isAdmin) {
        Write-StatusOK "Запущено с правами администратора"
        $requirements.Administrator = $true
    } else {
        Write-StatusFail "Требуются права администратора для настройки планировщика"
    }
    
    # Git
    try {
        $null = git --version 2>&1
        $gitVersion = git --version
        Write-StatusOK "Git установлен: $gitVersion"
        $requirements.Git = $true
    }
    catch {
        Write-StatusWarn "Git не найден (опционально для обслуживания репозиториев)"
    }
    
    # 1C Platform
    $platforms = @(Get-InstalledPlatforms)
    if (@($platforms).Count -gt 0) {
        Write-StatusOK "Найдено платформ 1С: $(@($platforms).Count)"
        foreach ($platform in $platforms) {
            Write-Info "  • $($platform.Version.Original)"
        }
        $requirements.Platform1C = $true
    } else {
        Write-StatusWarn "Платформы 1С не найдены (опционально для обслуживания баз)"
    }
    
    Write-Host ""
    
    # Критические требования
    if (-not $requirements.PowerShell) {
        Write-Host "ОШИБКА: Требуется PowerShell 5.1 или выше" -ForegroundColor Red
        return $false
    }
    
    if (-not $requirements.Administrator) {
        Write-Host "ОШИБКА: Требуются права администратора" -ForegroundColor Red
        return $false
    }
    
    # Предупреждения
    if (-not $requirements.Git -and -not $requirements.Platform1C) {
        Write-Host "ВНИМАНИЕ: Не найдены ни Git, ни платформа 1С" -ForegroundColor Yellow
        Write-Host "Система сможет обслуживать только EDT workspace" -ForegroundColor Yellow
        Write-Host ""
        
        if (-not (Read-YesNo "Продолжить установку?" $false)) {
            return $false
        }
    }
    
    return $true
}

#endregion

#region Интерактивная настройка

function Get-InstallationPaths {
    Write-Step "Настройка путей установки"
    
    $paths = @{
        InstallPath = $DEFAULT_INSTALL_PATH
        ConfigPath = $DEFAULT_CONFIG_PATH
        ReportsPath = $DEFAULT_REPORTS_PATH
    }
    
    Write-Info "Настройка путей для установки системы"
    Write-Host ""
    
    # Основная папка
    $paths.InstallPath = Read-PathWithDefault -Prompt "Папка установки" -Default $DEFAULT_INSTALL_PATH
    
    # Конфигурация
    $defaultConfigPath = Join-Path -Path $paths.InstallPath -ChildPath "config"
    $paths.ConfigPath = Read-PathWithDefault -Prompt "Папка конфигурации" -Default $defaultConfigPath
    
    # Отчеты
    $defaultReportsPath = Join-Path -Path $paths.InstallPath -ChildPath "reports"
    $paths.ReportsPath = Read-PathWithDefault -Prompt "Папка отчетов" -Default $defaultReportsPath
    
    return $paths
}

function Find-GitRepositoriesInteractive {
    Write-Step "Поиск Git-репозиториев"
    
    $repos = @()
    $searchPaths = @()
    
    Write-Info "Система может автоматически найти Git-репозитории на вашем компьютере"
    Write-Host ""
    
    if (Read-YesNo "Выполнить автоматический поиск репозиториев?" $true) {
        Write-Host ""
        Write-Info "Укажите папки для поиска (например: C:\Dev, D:\Projects)"
        Write-Info "Пустая строка завершит ввод"
        Write-Host ""
        
        $commonPaths = @(
            "C:\Git",
            "C:\Projects",
            "$env:USERPROFILE\Documents\Projects"
        )
        
        Write-Info "Предлагаемые папки:"
        for ($i = 0; $i -lt $commonPaths.Count; $i++) {
            if (Test-Path $commonPaths[$i]) {
                Write-Host "  [$($i+1)] $($commonPaths[$i]) " -NoNewline -ForegroundColor Cyan
                Write-Host "✓" -ForegroundColor Green
            }
        }
        Write-Host ""
        
        while ($true) {
            $path = Read-Host "  Папка для поиска (или Enter для завершения)"
            
            if ([string]::IsNullOrWhiteSpace($path)) {
                break
            }
            
            # Проверка на номер из списка
            if ($path -match '^\d+$') {
                $index = [int]$path - 1
                if ($index -ge 0 -and $index -lt $commonPaths.Count) {
                    $path = $commonPaths[$index]
                }
            }
            
            if (Test-Path $path) {
                $searchPaths += $path
                Write-StatusOK "Добавлена: $path"
            } else {
                Write-StatusWarn "Папка не существует: $path"
            }
        }
        
        # Выполняем поиск
        if (@($searchPaths).Count -gt 0) {
            Write-Host ""
            Write-Info "Поиск репозиториев..."
            
            $found = @(Find-GitRepositoriesInPaths -SearchPaths $searchPaths -MaxDepth 2)
            
            if (@($found).Count -gt 0) {
                Write-StatusOK "Найдено репозиториев: $(@($found).Count)"
                
                foreach ($repo in $found) {
                    $size = Get-GitRepositorySize -RepoPath $repo
                    $sizeGB = Convert-BytesToGB -Bytes $size
                    Write-Info "  • $repo ($sizeGB ГБ)"
                }
                
                Write-Host ""
                if (Read-YesNo "Добавить все найденные репозитории?" $true) {
                    $repos = $found
                }
            } else {
                Write-StatusWarn "Репозитории не найдены"
            }
        }
    }
    
    # Возможность добавить вручную
    Write-Host ""
    if (Read-YesNo "Добавить репозитории вручную?" $false) {
        Write-Host ""
        Write-Info "Укажите пути к репозиториям (пустая строка завершит ввод)"
        Write-Host ""
        
        while ($true) {
            $path = Read-Host "  Путь к репозиторию"
            
            if ([string]::IsNullOrWhiteSpace($path)) {
                break
            }
            
            if (Test-Path $path) {
                if (Test-IsGitRepository -Path $path) {
                    $repos += $path
                    Write-StatusOK "Добавлен: $path"
                } else {
                    Write-StatusWarn "Не является Git-репозиторием: $path"
                }
            } else {
                Write-StatusWarn "Путь не существует: $path"
            }
        }
    }
    
    return @{
        Repos = @($repos | Select-Object -Unique)
        SearchPaths = $searchPaths
    }
}

function Find-EdtWorkspacesInteractive {
    Write-Step "Поиск EDT Workspaces"
    
    $workspaces = @()
    $searchPaths = @()
    
    Write-Info "Поиск workspace Eclipse/EDT"
    Write-Host ""
    
    if (Read-YesNo "Выполнить автоматический поиск workspace?" $true) {
        Write-Host ""
        Write-Info "Укажите папки для поиска workspace"
        Write-Info "Пустая строка завершит ввод"
        Write-Host ""
        
        $commonPaths = @(
            "C:\EDT",
            "$env:USERPROFILE\Documents\EDT"
        )
        
        Write-Info "Предлагаемые папки:"
        for ($i = 0; $i -lt $commonPaths.Count; $i++) {
            if (Test-Path $commonPaths[$i]) {
                Write-Host "  [$($i+1)] $($commonPaths[$i]) " -NoNewline -ForegroundColor Cyan
                Write-Host "✓" -ForegroundColor Green
            }
        }
        Write-Host ""
        
        while ($true) {
            $path = Read-Host "  Папка для поиска (или Enter для завершения)"
            
            if ([string]::IsNullOrWhiteSpace($path)) {
                break
            }
            
            if ($path -match '^\d+$') {
                $index = [int]$path - 1
                if ($index -ge 0 -and $index -lt $commonPaths.Count) {
                    $path = $commonPaths[$index]
                }
            }
            
            if (Test-Path $path) {
                $searchPaths += $path
                Write-StatusOK "Добавлена: $path"
            } else {
                Write-StatusWarn "Папка не существует: $path"
            }
        }
        
        if (@($searchPaths).Count -gt 0) {
            Write-Host ""
            Write-Info "Поиск workspace..."
            
            foreach ($searchPath in $searchPaths) {
                $found = @(Find-EdtWorkspaces -SearchPath $searchPath -MaxDepth 2)
                
                if (@($found).Count -gt 0) {
                    Write-StatusOK "Найдено в $searchPath : $(@($found).Count)"
                    
                    foreach ($ws in $found) {
                        $size = Get-EdtWorkspaceSize -Path $ws
                        $sizeGB = Convert-BytesToGB -Bytes $size
                        Write-Info "  • $ws ($sizeGB ГБ)"
                        $workspaces += $ws
                    }
                }
            }
            
            $workspaces = @($workspaces | Select-Object -Unique)
        }
    }
    
    return @{
        Workspaces = $workspaces
        SearchPaths = $searchPaths
    }
}

function Find-DatabasesInteractive {
    Write-Step "Поиск баз данных 1С"
    
    $databases = @()
    $searchPaths = @()
    
    Write-Info "Поиск информационных баз 1С (.1CD)"
    Write-Host ""
    
    if (Read-YesNo "Выполнить автоматический поиск баз?" $true) {
        Write-Host ""
        Write-Info "Укажите папки для поиска баз"
        Write-Info "Пустая строка завершит ввод"
        Write-Host ""
        
        $commonPaths = @(
            "C:\Bases",
            "$env:USERPROFILE\Documents\1C"
        )
        
        Write-Info "Предлагаемые папки:"
        for ($i = 0; $i -lt $commonPaths.Count; $i++) {
            if (Test-Path $commonPaths[$i]) {
                Write-Host "  [$($i+1)] $($commonPaths[$i]) " -NoNewline -ForegroundColor Cyan
                Write-Host "✓" -ForegroundColor Green
            }
        }
        Write-Host ""
        
        while ($true) {
            $path = Read-Host "  Папка для поиска (или Enter для завершения)"
            
            if ([string]::IsNullOrWhiteSpace($path)) {
                break
            }
            
            if ($path -match '^\d+$') {
                $index = [int]$path - 1
                if ($index -ge 0 -and $index -lt $commonPaths.Count) {
                    $path = $commonPaths[$index]
                }
            }
            
            if (Test-Path $path) {
                $searchPaths += $path
                Write-StatusOK "Добавлена: $path"
            } else {
                Write-StatusWarn "Папка не существует: $path"
            }
        }
        
        if (@($searchPaths).Count -gt 0) {
            Write-Host ""
            Write-Info "Поиск баз данных..."
            
            $found = @(Find-DatabasesInPaths -SearchPaths $searchPaths -MaxDepth 3)
            
            if (@($found).Count -gt 0) {
                Write-StatusOK "Найдено баз: $(@($found).Count)"
                
                foreach ($db in $found) {
                    $size = Get-DatabaseSize -DbPath $db
                    $sizeGB = Convert-BytesToGB -Bytes $size
                    Write-Info "  • $db ($sizeGB ГБ)"
                }
                
                $databases = $found
            }
        }
    }
    
    return @{
        Databases = $databases
        SearchPaths = $searchPaths
    }
}

function Get-ConfigurationSettings {
    Write-Step "Настройка параметров обслуживания"
    
    Write-Info "Настройка порогов размера для запуска обслуживания"
    Write-Host ""
    
    # Git threshold
    Write-Host "  Git-репозитории:" -ForegroundColor Cyan
    Write-Host "  Рекомендуемый порог: 15 ГБ" -ForegroundColor Gray
    $gitThreshold = Read-Host "  Минимальный размер (ГБ)"
    if ([string]::IsNullOrWhiteSpace($gitThreshold)) {
        $gitThreshold = 15.0
    } else {
        $gitThreshold = [double]$gitThreshold
    }
    Write-Host ""
    
    # EDT threshold
    Write-Host "  EDT Workspaces:" -ForegroundColor Cyan
    Write-Host "  Рекомендуемый порог: 5 ГБ" -ForegroundColor Gray
    $edtThreshold = Read-Host "  Минимальный размер (ГБ)"
    if ([string]::IsNullOrWhiteSpace($edtThreshold)) {
        $edtThreshold = 5.0
    } else {
        $edtThreshold = [double]$edtThreshold
    }
    Write-Host ""
    
    # Database threshold
    Write-Host "  Базы данных 1С:" -ForegroundColor Cyan
    Write-Host "  Рекомендуемый порог: 3 ГБ" -ForegroundColor Gray
    $dbThreshold = Read-Host "  Минимальный размер (ГБ)"
    if ([string]::IsNullOrWhiteSpace($dbThreshold)) {
        $dbThreshold = 3.0
    } else {
        $dbThreshold = [double]$dbThreshold
    }
    Write-Host ""
    
    # Platform version
    Write-Host "  Версия платформы 1С:" -ForegroundColor Cyan
    Write-Host "  Примеры: 8.3.27, 8.3.*, пусто = любая" -ForegroundColor Gray
    $platformVersion = Read-Host "  Маска версии"
    Write-Host ""
    
    # Parallel processing
    $parallelProcessing = Read-YesNo "Использовать параллельную обработку?" $true
    Write-Host ""
    
    return @{
        GitThreshold = $gitThreshold
        EdtThreshold = $edtThreshold
        DbThreshold = $dbThreshold
        PlatformVersion = $platformVersion
        ParallelProcessing = $parallelProcessing
    }
}

#endregion

#region Создание конфигурации

function New-ConfigurationFile {
    param(
        [hashtable]$Paths,
        [hashtable]$GitData,
        [hashtable]$EdtData,
        [hashtable]$DatabaseData,
        [hashtable]$Settings
    )
    
    Write-Step "Создание конфигурации"
    
    # Создаем папки
    Ensure-DirectoryExists -Path $Paths.InstallPath | Out-Null
    Ensure-DirectoryExists -Path $Paths.ConfigPath | Out-Null
    Ensure-DirectoryExists -Path $Paths.ReportsPath | Out-Null
    
    $configFile = Join-Path -Path $Paths.ConfigPath -ChildPath "maintenance-config.json"
    
    # Формируем конфигурацию
    $config = @{
        settings = @{
            git = @{
                repos = @($GitData.Repos)
                searchPaths = @($GitData.SearchPaths)
                sizeThresholdGB = $Settings.GitThreshold
            }
            edt = @{
                workspaces = @($EdtData.Workspaces)
                searchPaths = @($EdtData.SearchPaths)
                sizeThresholdGB = $Settings.EdtThreshold
            }
            database = @{
                databases = @($DatabaseData.Databases)
                searchPaths = @($DatabaseData.SearchPaths)
                platformVersion = $Settings.PlatformVersion
                user = ""
                password = ""
                sizeThresholdGB = $Settings.DbThreshold
            }
            general = @{
                reportsPath = $Paths.ReportsPath
                silentMode = $false
                parallelProcessing = $Settings.ParallelProcessing
                maxParallelTasks = ([System.Environment]::ProcessorCount - 1)
            }
        }
    }
    
    # Сохраняем
    $jsonContent = $config | ConvertTo-Json -Depth 10
    $utf8WithBom = New-Object System.Text.UTF8Encoding $true
    [System.IO.File]::WriteAllText($configFile, $jsonContent, $utf8WithBom)
    
    Write-StatusOK "Конфигурация сохранена: $configFile"
    
    return $configFile
}

#endregion

#region Настройка планировщика

function Install-ScheduledTask {
    param(
        [string]$ScriptPath,
        [string]$ConfigPath
    )
    
    Write-Step "Настройка планировщика задач"
    
    Write-Info "Создание задачи автоматического обслуживания"
    Write-Host ""
    
    # Проверяем существование задачи
    $existingTask = Get-ScheduledTask -TaskName $TASK_NAME -ErrorAction SilentlyContinue
    
    if ($existingTask) {
        Write-StatusWarn "Задача '$TASK_NAME' уже существует"
        
        if (Read-YesNo "Удалить существующую задачу и создать новую?" $true) {
            Unregister-ScheduledTask -TaskName $TASK_NAME -Confirm:$false
            Write-StatusOK "Существующая задача удалена"
        } else {
            Write-StatusWarn "Оставлена существующая задача"
            return $false
        }
    }
    
    # Расписание
    Write-Host ""
    Write-Info "Настройка расписания:"
    Write-Host "  1. Еженедельно (рекомендуется)" -ForegroundColor Cyan
    Write-Host "  2. Ежедневно" -ForegroundColor Cyan
    Write-Host "  3. Ежемесячно" -ForegroundColor Cyan
    Write-Host ""
    
    $scheduleChoice = Read-Host "  Выберите вариант [1-3]"
    if ([string]::IsNullOrWhiteSpace($scheduleChoice)) {
        $scheduleChoice = "1"
    }
    
    Write-Host ""
    Write-Host "  Время запуска (рекомендуется вне рабочего времени):" -ForegroundColor Cyan
    $timeStr = Read-Host "  Время (формат: HH:MM, по умолчанию: 20:00)"
    if ([string]::IsNullOrWhiteSpace($timeStr)) {
        $timeStr = "20:00"
    }
    
    try {
        $time = [datetime]::ParseExact($timeStr, "HH:mm", $null)
    }
    catch {
        Write-StatusWarn "Неверный формат времени, используется 20:00"
        $time = [datetime]::ParseExact("20:00", "HH:mm", $null)
    }
    
    # Создаем триггер
    switch ($scheduleChoice) {
        "1" {
            # Еженедельно, в субботу
            $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Saturday -At $time
            Write-StatusOK "Расписание: каждую субботу в $($time.ToString('HH:mm'))"
        }
        "2" {
            # Ежедневно
            $trigger = New-ScheduledTaskTrigger -Daily -At $time
            Write-StatusOK "Расписание: ежедневно в $($time.ToString('HH:mm'))"
        }
        "3" {
            # Ежемесячно, 1-го числа
            $trigger = New-ScheduledTaskTrigger -Monthly -DaysOfMonth 1 -At $time
            Write-StatusOK "Расписание: 1-го числа каждого месяца в $($time.ToString('HH:mm'))"
        }
        default {
            $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Saturday -At $time
            Write-StatusOK "Расписание: каждую субботу в $($time.ToString('HH:mm'))"
        }
    }
    
    # Создаем действие
    $action = New-ScheduledTaskAction `
        -Execute "PowerShell.exe" `
        -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`" -ConfigPath `"$ConfigPath`""
    
    # Настройки задачи
    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -RunOnlyIfNetworkAvailable:$false `
        -WakeToRun:$false
    
    # Регистрируем задачу
    try {
        Register-ScheduledTask `
            -TaskName $TASK_NAME `
            -Action $action `
            -Trigger $trigger `
            -Settings $settings `
            -Description "Автоматическое обслуживание Git-репозиториев, EDT workspace и баз 1С" `
            -RunLevel Highest | Out-Null
        
        Write-StatusOK "Задача планировщика создана успешно"
        return $true
    }
    catch {
        Write-StatusFail "Ошибка создания задачи: $($_.Exception.Message)"
        return $false
    }
}

#endregion

#region Тестовый запуск

function Test-Installation {
    param([string]$ScriptPath, [string]$ConfigPath)
    
    Write-Step "Тестовый запуск"
    
    Write-Info "Выполнение пробного запуска системы (DryRun)"
    Write-Host ""
    
    if (-not (Read-YesNo "Запустить тестовый режим?" $true)) {
        return $true
    }
    
    Write-Host ""
    Write-Info "Запуск..."
    Write-Host ""
    
    try {
        & PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File $ScriptPath -ConfigPath $ConfigPath -DryRun
        
        Write-Host ""
        Write-StatusOK "Тестовый запуск завершен"
        return $true
    }
    catch {
        Write-Host ""
        Write-StatusFail "Ошибка при тестовом запуске: $($_.Exception.Message)"
        return $false
    }
}

#endregion

#region Основной процесс установки

function Start-Installation {
    Write-Banner
    
    Write-Host "Добро пожаловать в установщик 1C-Sweeper!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Эта программа автоматизирует обслуживание:" -ForegroundColor White
    Write-Host "  • Git-репозиториев (очистка, сжатие)" -ForegroundColor White
    Write-Host "  • EDT Workspaces (очистка кэша, логов)" -ForegroundColor White
    Write-Host "  • Баз данных 1С (тестирование и исправление)" -ForegroundColor White
    Write-Host ""
    Write-Host "Установка займет около 5-10 минут" -ForegroundColor Gray
    Write-Host ""
    
    if (-not (Read-YesNo "Начать установку?" $true)) {
        Write-Host "`nУстановка отменена пользователем" -ForegroundColor Yellow
        return
    }
    
    # 1. Проверка требований
    if (-not (Test-SystemRequirements)) {
        Write-Host "`n✗ Системные требования не выполнены" -ForegroundColor Red
        Write-Host "Установка прервана" -ForegroundColor Red
        return
    }
    
    # 2. Пути установки
    $paths = Get-InstallationPaths
    
    # 3. Поиск Git-репозиториев
    $gitData = Find-GitRepositoriesInteractive
    
    # 4. Поиск EDT workspaces
    $edtData = Find-EdtWorkspacesInteractive
    
    # 5. Поиск баз 1С
    $databaseData = Find-DatabasesInteractive
    
    # 6. Настройки
    $settings = Get-ConfigurationSettings
    
    # 7. Копирование файлов
    Write-Step "Копирование файлов"
    
    $targetSrcPath = Join-Path -Path $paths.InstallPath -ChildPath "src"
    
    if (Test-Path $targetSrcPath) {
        Write-StatusWarn "Папка уже существует: $targetSrcPath"
        if (Read-YesNo "Перезаписать?" $true) {
            Remove-Item -Path $targetSrcPath -Recurse -Force
            Write-StatusOK "Старая версия удалена"
        }
    }
    
    Write-Info "Копирование исходных файлов..."
    Copy-Item -Path $srcPath -Destination $targetSrcPath -Recurse -Force
    Write-StatusOK "Файлы скопированы в $targetSrcPath"
    
    # Путь к главному скрипту
    $mainScript = Join-Path -Path $targetSrcPath -ChildPath "MaintenanceService.ps1"
    
    # 8. Создание конфигурации
    $configFile = New-ConfigurationFile `
        -Paths $paths `
        -GitData $gitData `
        -EdtData $edtData `
        -DatabaseData $databaseData `
        -Settings $settings
    
    # 9. Настройка планировщика
    $taskCreated = Install-ScheduledTask -ScriptPath $mainScript -ConfigPath $configFile
    
    # 10. Тестовый запуск
    $testPassed = Test-Installation -ScriptPath $mainScript -ConfigPath $configFile
    
    # Итоги
    Write-Step "Установка завершена"
    
    Write-Host ""
    Write-Host "╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║                                                           ║" -ForegroundColor Green
    Write-Host "║              ✓ УСТАНОВКА ЗАВЕРШЕНА УСПЕШНО!               ║" -ForegroundColor Green
    Write-Host "║                                                           ║" -ForegroundColor Green
    Write-Host "╚═══════════════════════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""
    
    Write-Host "Информация об установке:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Папка установки:    $($paths.InstallPath)" -ForegroundColor White
    Write-Host "  Конфигурация:       $configFile" -ForegroundColor White
    Write-Host "  Отчеты:             $($paths.ReportsPath)" -ForegroundColor White
    Write-Host "  Главный скрипт:     $mainScript" -ForegroundColor White
    Write-Host ""
    
    if ($taskCreated) {
        Write-Host "  Задача планировщика:" -ForegroundColor Cyan
        Write-Host "    Имя:  $TASK_NAME" -ForegroundColor White
        Write-Host "    Просмотр: Планировщик заданий Windows" -ForegroundColor Gray
    }
    Write-Host ""
    
    Write-Host "Найденные объекты для обслуживания:" -ForegroundColor Cyan
    Write-Host "  Git-репозитории:   $(@($gitData.Repos).Count)" -ForegroundColor White
    Write-Host "  EDT Workspaces:    $(@($edtData.Workspaces).Count)" -ForegroundColor White
    Write-Host "  Базы данных 1С:    $(@($databaseData.Databases).Count)" -ForegroundColor White
    Write-Host ""
    
    Write-Host "Следующие шаги:" -ForegroundColor Cyan
    Write-Host "  1. Проверьте конфигурацию: $configFile" -ForegroundColor White
    Write-Host "  2. При необходимости отредактируйте вручную" -ForegroundColor White
    Write-Host "  3. Запустите вручную для проверки:" -ForegroundColor White
    Write-Host "     PowerShell -ExecutionPolicy Bypass -File `"$mainScript`" -ConfigPath `"$configFile`"" -ForegroundColor Gray
    Write-Host "  4. Система будет запускаться автоматически по расписанию" -ForegroundColor White
    Write-Host ""
    
    Write-Host "Для деинсталляции используйте: .\install\Uninstall.ps1" -ForegroundColor Gray
    Write-Host ""
}

#endregion

# Запуск установки
try {
    Start-Installation
}
catch {
    Write-Host "`n✗ КРИТИЧЕСКАЯ ОШИБКА:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Gray
    exit 1
}