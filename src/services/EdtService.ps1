<#
.SYNOPSIS
    Обслуживание EDT workspace
.DESCRIPTION
    Очистка кэшей, логов и временных файлов Eclipse/EDT workspace.
    Освобождает место и ускоряет работу EDT.
.NOTES
    Проект: 1C-Sweeper
    Версия: 1.0
    Дата создания: 2025-10-05
#>

#Requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Импорт зависимостей - ИСПРАВЛЕНО
$scriptPath = if ($PSScriptRoot) { 
    $PSScriptRoot 
} elseif ($MyInvocation.MyCommand.Path) {
    Split-Path -Parent $MyInvocation.MyCommand.Path
} else {
    $PWD.Path
}

$corePath = Join-Path -Path (Split-Path -Parent $scriptPath) -ChildPath "core"
. (Join-Path -Path $corePath -ChildPath "Common.ps1")
. (Join-Path -Path $corePath -ChildPath "LoggingService.ps1")

#region Основные функции

<#
.SYNOPSIS
    Проверяет, является ли указанная папка EDT workspace
.PARAMETER Path
    Путь к папке для проверки
.EXAMPLE
    Test-IsEdtWorkspace -Path "C:\EDT\workspace1"
#>
function Test-IsEdtWorkspace {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    
    try {
        if (-not (Test-Path -Path $Path -PathType Container)) {
            return $false
        }
        
        # Workspace определяется наличием папки .metadata
        $metadataPath = Join-Path -Path $Path -ChildPath ".metadata"
        return (Test-Path -Path $metadataPath -PathType Container)
    }
    catch {
        Write-LogError "Ошибка проверки workspace '$Path': $($_.Exception.Message)"
        return $false
    }
}

<#
.SYNOPSIS
    Получает размер EDT workspace в байтах
.PARAMETER Path
    Путь к workspace
.EXAMPLE
    Get-EdtWorkspaceSize -Path "C:\EDT\workspace1"
#>
function Get-EdtWorkspaceSize {
    [CmdletBinding()]
    [OutputType([long])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-IsEdtWorkspace -Path $_ })]
        [string]$Path
    )
    
    try {
        return Get-DirectorySize -Path $Path -Recurse $true
    }
    catch {
        Write-LogError "Ошибка получения размера workspace '$Path': $($_.Exception.Message)"
        return 0
    }
}

<#
.SYNOPSIS
    Очищает логи EDT workspace
.PARAMETER WorkspacePath
    Путь к workspace
.EXAMPLE
    Clear-EdtLogs -WorkspacePath "C:\EDT\workspace1"
#>
function Clear-EdtLogs {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkspacePath
    )
    
    $result = @{
        Success = $true
        SizeFreed = 0
        Errors = @()
    }
    
    try {
        $metadataPath = Join-Path -Path $WorkspacePath -ChildPath ".metadata"
        
        # Очистка основного лога
        $mainLogPath = Join-Path -Path $metadataPath -ChildPath ".log"
        if (Test-Path -Path $mainLogPath) {
            $sizeBefore = (Get-Item -Path $mainLogPath).Length
            Remove-Item -Path $mainLogPath -Force -ErrorAction SilentlyContinue
            $result.SizeFreed += $sizeBefore
            Write-LogInfo "    ✓ Удален основной лог (.metadata/.log)"
        }
        
        # Очистка логов плагинов
        $pluginsPath = Join-Path -Path $metadataPath -ChildPath ".plugins"
        if (Test-Path -Path $pluginsPath) {
            $logFiles = Get-ChildItem -Path $pluginsPath -Filter "*.log" -Recurse -File -ErrorAction SilentlyContinue
            foreach ($logFile in $logFiles) {
                try {
                    $sizeBefore = $logFile.Length
                    Remove-Item -Path $logFile.FullName -Force
                    $result.SizeFreed += $sizeBefore
                }
                catch {
                    $result.Errors += "Не удалось удалить лог: $($logFile.FullName)"
                }
            }
            if ($logFiles.Count -gt 0) {
                Write-LogInfo "    ✓ Удалено логов плагинов: $($logFiles.Count)"
            }
        }
    }
    catch {
        $result.Success = $false
        $result.Errors += $_.Exception.Message
        Write-LogError "    ✗ Ошибка очистки логов: $($_.Exception.Message)"
    }
    
    return $result
}

<#
.SYNOPSIS
    Очищает кэш EDT workspace
.PARAMETER WorkspacePath
    Путь к workspace
.EXAMPLE
    Clear-EdtCache -WorkspacePath "C:\EDT\workspace1"
#>
function Clear-EdtCache {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkspacePath
    )
    
    $result = @{
        Success = $true
        SizeFreed = 0
        Errors = @()
    }
    
    try {
        $pluginsPath = Join-Path -Path $WorkspacePath -ChildPath ".metadata\.plugins"
        
        if (-not (Test-Path -Path $pluginsPath)) {
            return $result
        }
        
        # Папки кэша для очистки
        $cachePatterns = @(
            "cache",
            "caches"
        )
        
        # Специфичные папки для очистки
        $specificPaths = @(
            "org.eclipse.core.resources\.history",
            "org.eclipse.jdt.core",
            "org.eclipse.pde.core\.bundle_pool"
        )
        
        # Очистка по паттернам
        foreach ($pattern in $cachePatterns) {
            $cacheDirs = Get-ChildItem -Path $pluginsPath -Filter $pattern -Recurse -Directory -ErrorAction SilentlyContinue
            
            foreach ($cacheDir in $cacheDirs) {
                try {
                    $sizeBefore = Get-DirectorySize -Path $cacheDir.FullName
                    Remove-DirectorySafely -Path $cacheDir.FullName -Force $true | Out-Null
                    $result.SizeFreed += $sizeBefore
                }
                catch {
                    $result.Errors += "Не удалось удалить кэш: $($cacheDir.FullName)"
                }
            }
        }
        
        # Очистка специфичных папок
        foreach ($specificPath in $specificPaths) {
            $fullPath = Join-Path -Path $pluginsPath -ChildPath $specificPath
            if (Test-Path -Path $fullPath) {
                try {
                    $sizeBefore = Get-DirectorySize -Path $fullPath
                    Remove-DirectorySafely -Path $fullPath -Force $true | Out-Null
                    $result.SizeFreed += $sizeBefore
                }
                catch {
                    $result.Errors += "Не удалось удалить: $fullPath"
                }
            }
        }
        
        Write-LogInfo "    ✓ Очищен кэш плагинов"
    }
    catch {
        $result.Success = $false
        $result.Errors += $_.Exception.Message
        Write-LogError "    ✗ Ошибка очистки кэша: $($_.Exception.Message)"
    }
    
    return $result
}

<#
.SYNOPSIS
    Очищает индексы EDT workspace
.PARAMETER WorkspacePath
    Путь к workspace
.EXAMPLE
    Clear-EdtIndexes -WorkspacePath "C:\EDT\workspace1"
#>
function Clear-EdtIndexes {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkspacePath
    )
    
    $result = @{
        Success = $true
        SizeFreed = 0
        Errors = @()
    }
    
    try {
        $pluginsPath = Join-Path -Path $WorkspacePath -ChildPath ".metadata\.plugins"
        
        if (-not (Test-Path -Path $pluginsPath)) {
            return $result
        }
        
        # Папки индексов для очистки
        $indexPatterns = @(
            "index",
            "indexes"
        )
        
        foreach ($pattern in $indexPatterns) {
            $indexDirs = Get-ChildItem -Path $pluginsPath -Filter $pattern -Recurse -Directory -ErrorAction SilentlyContinue
            
            foreach ($indexDir in $indexDirs) {
                try {
                    $sizeBefore = Get-DirectorySize -Path $indexDir.FullName
                    Remove-DirectorySafely -Path $indexDir.FullName -Force $true | Out-Null
                    $result.SizeFreed += $sizeBefore
                }
                catch {
                    $result.Errors += "Не удалось удалить индекс: $($indexDir.FullName)"
                }
            }
        }
        
        Write-LogInfo "    ✓ Очищены индексы"
    }
    catch {
        $result.Success = $false
        $result.Errors += $_.Exception.Message
        Write-LogError "    ✗ Ошибка очистки индексов: $($_.Exception.Message)"
    }
    
    return $result
}

<#
.SYNOPSIS
    Выполняет полное обслуживание EDT workspace
.PARAMETER WorkspacePath
    Путь к workspace
.EXAMPLE
    Invoke-EdtMaintenance -WorkspacePath "C:\EDT\workspace1"
#>
function Invoke-EdtMaintenance {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -Path $_ -PathType Container })]
        [string]$WorkspacePath
    )
    
    $startTime = Get-Date
    
    $result = @{
        Success = $false
        Path = $WorkspacePath
        SizeBefore = 0
        SizeAfter = 0
        SpaceSaved = 0
        Duration = 0
        Actions = @()
        Errors = @()
    }
    
    try {
        Write-LogSeparator
        Write-LogInfo "Обслуживание workspace: $WorkspacePath"
        
        # Проверка, что это workspace
        if (-not (Test-IsEdtWorkspace -Path $WorkspacePath)) {
            $result.Errors += "Указанный путь не является EDT workspace"
            Write-LogError "✗ Не является EDT workspace"
            return $result
        }
        
        # Получение размера до обслуживания
        Write-LogInfo "Измерение размера..."
        $result.SizeBefore = Get-EdtWorkspaceSize -Path $WorkspacePath
        $sizeBeforeGB = Convert-BytesToGB -Bytes $result.SizeBefore
        Write-LogInfo "Размер workspace: $sizeBeforeGB ГБ"
        
        Write-LogInfo "Начало обслуживания..."
        
        # 1. Очистка логов
        Write-LogInfo "  [1/3] Очистка логов..."
        $logsResult = Clear-EdtLogs -WorkspacePath $WorkspacePath
        if ($logsResult.Success) {
            $result.Actions += "clear_logs"
        }
        $result.Errors += $logsResult.Errors
        
        # 2. Очистка кэша
        Write-LogInfo "  [2/3] Очистка кэша..."
        $cacheResult = Clear-EdtCache -WorkspacePath $WorkspacePath
        if ($cacheResult.Success) {
            $result.Actions += "clear_cache"
        }
        $result.Errors += $cacheResult.Errors
        
        # 3. Очистка индексов
        Write-LogInfo "  [3/3] Очистка индексов..."
        $indexesResult = Clear-EdtIndexes -WorkspacePath $WorkspacePath
        if ($indexesResult.Success) {
            $result.Actions += "clear_indexes"
        }
        $result.Errors += $indexesResult.Errors
        
        Write-LogSeparator
        
        # Получение размера после обслуживания
        $result.SizeAfter = Get-EdtWorkspaceSize -Path $WorkspacePath
        $sizeAfterGB = Convert-BytesToGB -Bytes $result.SizeAfter
        
        # Расчет освобожденного места
        $result.SpaceSaved = $result.SizeBefore - $result.SizeAfter
        $spaceSavedGB = Convert-BytesToGB -Bytes $result.SpaceSaved
        
        # Время выполнения
        $result.Duration = [int]((Get-Date) - $startTime).TotalSeconds
        
        # Итоги
        $result.Success = ($result.Errors.Count -eq 0)
        
        if ($result.Success) {
            Write-LogSuccess "Обслуживание завершено"
        } else {
            Write-LogWarning "Обслуживание завершено с ошибками ($(($result.Errors).Count))"
        }
        
        Write-LogInfo "Размер до:        $sizeBeforeGB ГБ"
        Write-LogInfo "Размер после:     $sizeAfterGB ГБ"
        Write-LogSuccess "Освобождено:      $spaceSavedGB ГБ"
        Write-LogInfo "Время:            $($result.Duration)с"
        
        return $result
    }
    catch {
        $result.Success = $false
        $result.Errors += $_.Exception.Message
        $result.Duration = [int]((Get-Date) - $startTime).TotalSeconds
        
        Write-LogError "✗ Критическая ошибка обслуживания: $($_.Exception.Message)"
        return $result
    }
}

#endregion
