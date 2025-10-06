<#
.SYNOPSIS
    Главный скрипт системы обслуживания 1C-Sweeper
.DESCRIPTION
    Точка входа в систему автоматизированного обслуживания:
    - Git-репозиториев
    - EDT workspaces
    - Информационных баз 1С
    
    Выполняет автопоиск объектов, обработку с учетом параллелизма,
    формирование детальных отчетов.
.PARAMETER ConfigPath
    Путь к конфигурационному файлу (по умолчанию: config/maintenance-config.json)
.PARAMETER Silent
    Тихий режим (только ошибки в консоль, детали в лог)
.PARAMETER DryRun
    Тестовый запуск без фактического выполнения операций
.PARAMETER Force
    Игнорировать пороги размеров, обрабатывать все объекты
.PARAMETER Objects
    Обработать только указанные типы объектов (Git, EDT, Database)
.EXAMPLE
    .\MaintenanceService.ps1
    Запуск с конфигурацией по умолчанию
.EXAMPLE
    .\MaintenanceService.ps1 -ConfigPath "C:\Config\my-config.json" -Silent
    Запуск с пользовательской конфигурацией в тихом режиме
.EXAMPLE
    .\MaintenanceService.ps1 -Objects Git,EDT -Force
    Обработка только Git и EDT, игнорируя пороги размеров
.NOTES
    Проект: 1C-Sweeper
    Версия: 1.0
    Дата: 2025-10-06
#>

#Requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = "",
    
    [Parameter(Mandatory = $false)]
    [switch]$Silent,
    
    [Parameter(Mandatory = $false)]
    [switch]$DryRun,
    
    [Parameter(Mandatory = $false)]
    [switch]$Force,
    
    [Parameter(Mandatory = $false)]
    [ValidateSet("Git", "EDT", "Database")]
    [string[]]$Objects = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region Импорт зависимостей

$scriptPath = if ($PSScriptRoot) { 
    $PSScriptRoot 
} elseif ($MyInvocation.MyCommand.Path) {
    Split-Path -Parent $MyInvocation.MyCommand.Path
} else {
    $PWD.Path
}

# Базовый путь - это папка src
$corePath = Join-Path -Path $scriptPath -ChildPath "core"
$servicesPath = Join-Path -Path $scriptPath -ChildPath "services"
$discoveryPath = Join-Path -Path $scriptPath -ChildPath "discovery"

# Core
. (Join-Path -Path $corePath -ChildPath "Common.ps1")
. (Join-Path -Path $corePath -ChildPath "LoggingService.ps1")
. (Join-Path -Path $corePath -ChildPath "ConfigManager.ps1")
. (Join-Path -Path $corePath -ChildPath "ReportService.ps1")
. (Join-Path -Path $corePath -ChildPath "ParallelProcessor.ps1")

# Services
. (Join-Path -Path $servicesPath -ChildPath "GitService.ps1")
. (Join-Path -Path $servicesPath -ChildPath "EdtService.ps1")
. (Join-Path -Path $servicesPath -ChildPath "DatabaseService.ps1")

# Discovery
. (Join-Path -Path $discoveryPath -ChildPath "GitDiscovery.ps1")
. (Join-Path -Path $discoveryPath -ChildPath "EdtDiscovery.ps1")
. (Join-Path -Path $discoveryPath -ChildPath "DatabaseDiscovery.ps1")
. (Join-Path -Path $discoveryPath -ChildPath "PlatformDiscovery.ps1")

#endregion

#region Глобальные переменные

$script:Config = $null
$script:Report = $null
$script:StartTime = Get-Date

#endregion

#region Инициализация

<#
.SYNOPSIS
    Инициализирует все сервисы системы
#>
function Initialize-Services {
    [CmdletBinding()]
    param()
    
    try {
        # Определение пути к конфигурации
        if ([string]::IsNullOrEmpty($ConfigPath)) {
            $configDir = Join-Path -Path (Split-Path -Parent $scriptPath) -ChildPath "config"
            $ConfigPath = Join-Path -Path $configDir -ChildPath "maintenance-config.json"
        }
        
        # Проверка существования конфигурации
        if (-not (Test-Path -Path $ConfigPath)) {
            throw "Файл конфигурации не найден: $ConfigPath"
        }
        
        Write-Host "Загрузка конфигурации: $ConfigPath" -ForegroundColor Gray
        
        # Загрузка конфигурации
        $script:Config = Get-Configuration -Path $ConfigPath
        
        # Инициализация логирования
        $logsDir = Join-Path -Path (Split-Path -Parent $scriptPath) -ChildPath "logs"
        $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
        $logFile = Join-Path -Path $logsDir -ChildPath "maintenance_$timestamp.log"
        
        Initialize-Logging -LogFilePath $logFile -SilentMode ($Silent -or $Config.General.SilentMode)
        
        # Создание отчета
        $script:Report = New-Report
        
        Write-LogSuccess "Инициализация завершена"
        
        if ($DryRun) {
            Write-LogWarning "РЕЖИМ ПРОБНОГО ЗАПУСКА (DRY RUN) - изменения не будут применены"
        }
        
        if ($Force) {
            Write-LogWarning "ФОРСИРОВАННЫЙ РЕЖИМ - пороги размеров игнорируются"
        }
        
        if (@($Objects).Count -gt 0) {
            Write-LogInfo "Фильтр типов: $($Objects -join ', ')"
        }
        
        return $true
    }
    catch {
        Write-Host "✗ ОШИБКА ИНИЦИАЛИЗАЦИИ: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

#endregion

#region Обработка объектов

<#
.SYNOPSIS
    Обрабатывает Git-репозитории
#>
function Process-GitRepositories {
    [CmdletBinding()]
    param()
    
    try {
        # Проверка фильтра
        if (@($Objects).Count -gt 0 -and $Objects -notcontains "Git") {
            Write-LogInfo "Git-репозитории пропущены (не в фильтре)"
            return
        }
        
        Write-LogSeparator -Title "GIT-РЕПОЗИТОРИИ"
        
        # Автопоиск репозиториев
        $repoData = Get-AllGitRepositories `
            -ExplicitRepos $Config.Git.Repos `
            -SearchPaths $Config.Git.SearchPaths
        
        $repositories = @($repoData.AllRepositories)
        
        if (@($repositories).Count -eq 0) {
            Write-LogWarning "Репозитории не найдены"
            return
        }
        
        # Фильтрация по размеру (если не Force)
        if (-not $Force -and $Config.Git.SizeThresholdGB -gt 0) {
            $filterResult = Filter-GitRepositoriesBySize `
                -Repositories $repositories `
                -MinSizeGB $Config.Git.SizeThresholdGB
            
            $repositories = @($filterResult.Matched)
        }
        
        if (@($repositories).Count -eq 0) {
            Write-LogWarning "Нет репозиториев, подходящих для обслуживания"
            return
        }
        
        Write-LogInfo "К обработке: $(@($repositories).Count) репозиториев"
        
        # Определение режима обработки
        $useParallel = $Config.General.ParallelProcessing -and 
                      (Test-ParallelismWorthwhile -ItemCount (@($repositories).Count))
        
        if ($useParallel) {
            Write-LogInfo "Режим: параллельная обработка"
            
            $scriptBlock = {
                param($repoPath)
                
                if ($using:DryRun) {
                    return @{
                        Success = $true
                        Skipped = $true
                        Path = $repoPath
                        SizeBefore = 0.0
                        SizeAfter = 0.0
                        SpaceSaved = 0.0
                        Duration = 0
                        Actions = @("dry_run")
                        Errors = @()
                    }
                }
                
                return Invoke-GitMaintenance `
                    -RepoPath $repoPath `
                    -SizeThresholdGB 0.0 `
                    -SkipFsck $true
            }
            
            $results = @(Start-ParallelProcessing `
                -Items $repositories `
                -ScriptBlock $scriptBlock `
                -ItemName "репозиториев" `
                -MaxThreads $Config.General.MaxParallelTasks)
        }
        else {
            Write-LogInfo "Режим: последовательная обработка"
            
            $results = @(Start-SequentialProcessing `
                -Items $repositories `
                -ScriptBlock {
                    param($repoPath)
                    
                    if ($DryRun) {
                        return @{
                            Success = $true
                            Skipped = $true
                            Path = $repoPath
                            SizeBefore = 0.0
                            SizeAfter = 0.0
                            SpaceSaved = 0.0
                            Duration = 0
                            Actions = @("dry_run")
                            Errors = @()
                        }
                    }
                    
                    return Invoke-GitMaintenance `
                        -RepoPath $repoPath `
                        -SizeThresholdGB 0.0 `
                        -SkipFsck $true
                } `
                -ItemName "репозиториев")
        }
        
        # Добавление результатов в отчет
        foreach ($result in $results) {
            Add-GitResult -Report $script:Report -Result $result
        }
    }
    catch {
        Write-LogError "Критическая ошибка обработки Git: $($_.Exception.Message)"
    }
}

<#
.SYNOPSIS
    Обрабатывает EDT workspaces
#>
function Process-EdtWorkspaces {
    [CmdletBinding()]
    param()
    
    try {
        # Проверка фильтра
        if (@($Objects).Count -gt 0 -and $Objects -notcontains "EDT") {
            Write-LogInfo "EDT workspaces пропущены (не в фильтре)"
            return
        }
        
        Write-LogSeparator -Title "EDT WORKSPACES"
        
        # Автопоиск workspaces
        $workspaces = @(Get-AllEdtWorkspaces `
            -ExplicitPaths $Config.Edt.Workspaces `
            -SearchPaths $Config.Edt.SearchPaths `
            -SizeThresholdGB $(if ($Force) { 0 } else { $Config.Edt.SizeThresholdGB }))
        
        if (@($workspaces).Count -eq 0) {
            Write-LogWarning "Workspaces не найдены или не подходят для обслуживания"
            return
        }
        
        Write-LogInfo "К обработке: $(@($workspaces).Count) workspaces"
        
        # Определение режима обработки
        $useParallel = $Config.General.ParallelProcessing -and 
                      (Test-ParallelismWorthwhile -ItemCount (@($workspaces).Count))
        
        if ($useParallel) {
            Write-LogInfo "Режим: параллельная обработка"
            
            $scriptBlock = {
                param($wsPath)
                
                if ($using:DryRun) {
                    return @{
                        Success = $true
                        Path = $wsPath
                        SizeBefore = 0
                        SizeAfter = 0
                        SpaceSaved = 0
                        Duration = 0
                        Actions = @("dry_run")
                        Errors = @()
                    }
                }
                
                return Invoke-EdtMaintenance -WorkspacePath $wsPath
            }
            
            $results = @(Start-ParallelProcessing `
                -Items $workspaces `
                -ScriptBlock $scriptBlock `
                -ItemName "workspaces" `
                -MaxThreads $Config.General.MaxParallelTasks)
        }
        else {
            Write-LogInfo "Режим: последовательная обработка"
            
            $results = @(Start-SequentialProcessing `
                -Items $workspaces `
                -ScriptBlock {
                    param($wsPath)
                    
                    if ($DryRun) {
                        return @{
                            Success = $true
                            Path = $wsPath
                            SizeBefore = 0
                            SizeAfter = 0
                            SpaceSaved = 0
                            Duration = 0
                            Actions = @("dry_run")
                            Errors = @()
                        }
                    }
                    
                    return Invoke-EdtMaintenance -WorkspacePath $wsPath
                } `
                -ItemName "workspaces")
        }
        
        # Добавление результатов в отчет
        foreach ($result in $results) {
            Add-EdtResult -Report $script:Report -Result $result
        }
    }
    catch {
        Write-LogError "Критическая ошибка обработки EDT: $($_.Exception.Message)"
    }
}

<#
.SYNOPSIS
    Обрабатывает базы данных 1С
#>
function Process-Databases {
    [CmdletBinding()]
    param()
    
    try {
        # Проверка фильтра
        if (@($Objects).Count -gt 0 -and $Objects -notcontains "Database") {
            Write-LogInfo "Базы 1С пропущены (не в фильтре)"
            return
        }
        
        Write-LogSeparator -Title "БАЗЫ ДАННЫХ 1С"
        
        # Автопоиск баз
        $databases = @(Get-AllDatabases `
            -ExplicitDatabases $Config.Database.Databases `
            -SearchPaths $Config.Database.SearchPaths `
            -SizeThresholdGB $(if ($Force) { 0 } else { $Config.Database.SizeThresholdGB }))
        
        if (@($databases).Count -eq 0) {
            Write-LogWarning "Базы данных не найдены или не подходят для обслуживания"
            return
        }
        
        Write-LogInfo "К обработке: $(@($databases).Count) баз"
        
        # Базы ВСЕГДА обрабатываются последовательно (ограничения лицензий)
        Write-LogInfo "Режим: последовательная обработка (требование лицензирования)"
        
        $results = @(Start-SequentialProcessing `
            -Items $databases `
            -ScriptBlock {
                param($dbPath)
                
                if ($using:DryRun) {
                    return @{
                        Success = $true
                        Skipped = $true
                        Path = $dbPath
                        SizeBefore = 0.0
                        SizeAfter = 0.0
                        SpaceSaved = 0.0
                        Duration = 0
                        Platform = "N/A"
                        Actions = @("dry_run")
                        Errors = @()
                    }
                }
                
                $config = $using:Config
                return Invoke-DatabaseMaintenance `
                    -DbPath $dbPath `
                    -PlatformVersion $config.Database.PlatformVersion `
                    -User $config.Database.User `
                    -Password $config.Database.Password `
                    -SizeThresholdGB 0.0
            } `
            -ItemName "баз")
        
        # Добавление результатов в отчет
        foreach ($result in $results) {
            Add-DatabaseResult -Report $script:Report -Result $result
        }
    }
    catch {
        Write-LogError "Критическая ошибка обработки баз 1С: $($_.Exception.Message)"
    }
}

<#
.SYNOPSIS
    Обрабатывает все объекты
#>
function Process-AllObjects {
    [CmdletBinding()]
    param()
    
    try {
        Write-LogSeparator -Title "НАЧАЛО ОБСЛУЖИВАНИЯ"
        Write-LogInfo "Дата: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        Write-LogInfo "Компьютер: $(Get-HostName)"
        
        # Git
        Process-GitRepositories
        
        # EDT
        Process-EdtWorkspaces
        
        # Databases
        Process-Databases
        
        Write-LogSeparator -Title "ОБСЛУЖИВАНИЕ ЗАВЕРШЕНО"
    }
    catch {
        Write-LogError "Критическая ошибка обработки: $($_.Exception.Message)"
    }
}

#endregion

#region Финализация

<#
.SYNOPSIS
    Финализирует работу системы
#>
function Complete-Maintenance {
    [CmdletBinding()]
    param()
    
    try {
        # Завершение отчета
        Complete-Report -Report $script:Report
        
        # Вывод сводки
        Show-ReportSummary -Report $script:Report
        
        # Сохранение отчета
        if (-not $DryRun) {
            $reportFile = Save-Report `
                -Report $script:Report `
                -ReportsPath $Config.General.ReportsPath
            
            if ($reportFile) {
                Write-LogInfo "`nОтчет сохранен: $reportFile"
            }
        }
        else {
            Write-LogWarning "`nОтчет не сохранен (режим DRY RUN)"
        }
        
        # Определение кода выхода
        $hasErrors = Test-ReportHasErrors -Report $script:Report
        
        if ($hasErrors) {
            Write-LogWarning "`n⚠ Обслуживание завершено с ошибками"
            return 1
        }
        else {
            Write-LogSuccess "`n✓ Обслуживание завершено успешно"
            return 0
        }
    }
    catch {
        Write-LogError "Ошибка финализации: $($_.Exception.Message)"
        return 1
    }
}

<#
.SYNOPSIS
    Очищает ресурсы при завершении
#>
function Cleanup-Resources {
    [CmdletBinding()]
    param()
    
    # В текущей реализации нет ресурсов, требующих явной очистки
    # Но функция оставлена для будущих расширений
}

#endregion

#region Главная функция

<#
.SYNOPSIS
    Главная функция запуска обслуживания
#>
function Start-Maintenance {
    [CmdletBinding()]
    param()
    
    $exitCode = 1
    
    try {
        # Инициализация
        if (-not (Initialize-Services)) {
            return 1
        }
        
        # Обработка объектов
        Process-AllObjects
        
        # Финализация
        $exitCode = Complete-Maintenance
    }
    catch {
        Write-Host "`n✗ КРИТИЧЕСКАЯ ОШИБКА:" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        Write-Host $_.ScriptStackTrace -ForegroundColor Gray
        $exitCode = 1
    }
    finally {
        # Очистка ресурсов
        Cleanup-Resources
    }
    
    return $exitCode
}

#endregion

#region Точка входа

# ASCII-арт заголовок
Write-Host @"

╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║                      1C-SWEEPER                           ║
║          Система автоматизированного обслуживания         ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

# Запуск
$exitCode = Start-Maintenance

# Выход
exit $exitCode

#endregion