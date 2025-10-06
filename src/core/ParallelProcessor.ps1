<#
.SYNOPSIS
    Параллельная обработка объектов
.DESCRIPTION
    Управление параллельными задачами с использованием PowerShell Jobs.
    Ускоряет обработку Git-репозиториев и EDT workspace.
    Базы 1С обрабатываются последовательно (ограничения лицензий).
.NOTES
    Проект: 1C-Sweeper
    Версия: 1.0
    Дата создания: 2025-10-06
#>

#Requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Импорт зависимостей
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

#region Параллельная обработка

<#
.SYNOPSIS
    Обрабатывает массив элементов параллельно
.PARAMETER Items
    Массив элементов для обработки
.PARAMETER ScriptBlock
    Скриптблок, который будет выполняться для каждого элемента
.PARAMETER MaxThreads
    Максимальное количество параллельных потоков (по умолчанию: кол-во ядер - 1)
.PARAMETER TimeoutSeconds
    Таймаут для каждой задачи в секундах (по умолчанию: 3600)
.PARAMETER ItemName
    Название элемента для логирования (по умолчанию: "элемент")
.EXAMPLE
    $results = Start-ParallelProcessing -Items $repos -ScriptBlock {
        param($repoPath)
        Invoke-GitMaintenance -RepoPath $repoPath
    } -MaxThreads 4
#>
function Start-ParallelProcessing {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Items,
        
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,
        
        [Parameter(Mandatory = $false)]
        [int]$MaxThreads = ([System.Environment]::ProcessorCount - 1),
        
        [Parameter(Mandatory = $false)]
        [int]$TimeoutSeconds = 3600,
        
        [Parameter(Mandatory = $false)]
        [string]$ItemName = "элемент"
    )
    
    try {
        $itemsArray = @($Items)
        
        if (@($itemsArray).Count -eq 0) {
            Write-LogWarning "Нет элементов для обработки"
            return @()
        }
        
        # Ограничиваем количество потоков
        if ($MaxThreads -lt 1) {
            $MaxThreads = 1
        }
        
        $totalItems = @($itemsArray).Count
        
        Write-LogInfo "Параллельная обработка: $totalItems $ItemName"
        Write-LogInfo "Максимум потоков: $MaxThreads"
        Write-LogInfo "Таймаут задачи: $TimeoutSeconds сек"
        
        $jobs = @()
        $results = @()
        $completed = 0
        $failed = 0
        
        # Запускаем задачи
        for ($i = 0; $i -lt @($itemsArray).Count; $i++) {
            $item = $itemsArray[$i]
            
            # Ждем, пока освободится слот
            while ((@(Get-Job -State Running).Count) -ge $MaxThreads) {
                Start-Sleep -Milliseconds 100
                
                # Проверяем завершенные задачи
                $completedJobs = @(Get-Job -State Completed)
                foreach ($completedJob in $completedJobs) {
                    if ($jobs -contains $completedJob) {
                        $result = Receive-Job -Job $completedJob
                        $results += $result
                        Remove-Job -Job $completedJob
                        $jobs = @($jobs | Where-Object { $_ -ne $completedJob })
                        $completed++
                        
                        Write-LogInfo "  Прогресс: $completed из $totalItems"
                    }
                }
                
                # Проверяем задачи с ошибками
                $failedJobs = @(Get-Job -State Failed)
                foreach ($failedJob in $failedJobs) {
                    if ($jobs -contains $failedJob) {
                        Write-LogError "  Задача завершилась с ошибкой"
                        
                        # Создаем объект результата с ошибкой
                        $errorResult = @{
                            Success = $false
                            Errors = @("Job failed")
                        }
                        $results += $errorResult
                        
                        Remove-Job -Job $failedJob
                        $jobs = @($jobs | Where-Object { $_ -ne $failedJob })
                        $failed++
                    }
                }
            }
            
            # Запускаем новую задачу
            $job = Start-Job -ScriptBlock $ScriptBlock -ArgumentList $item
            $jobs += $job
            
            Write-LogInfo "  Запущена задача $($i + 1) из $totalItems"
        }
        
        # Ждем завершения всех оставшихся задач
        Write-LogInfo "Ожидание завершения всех задач..."
        
        $waitStartTime = Get-Date
        $allCompleted = $false
        
        while (-not $allCompleted) {
            $runningJobs = @(Get-Job -State Running)
            
            if (@($runningJobs).Count -eq 0) {
                $allCompleted = $true
                break
            }
            
            # Проверяем таймаут
            $elapsed = ((Get-Date) - $waitStartTime).TotalSeconds
            if ($elapsed -gt $TimeoutSeconds) {
                Write-LogWarning "Достигнут общий таймаут ($TimeoutSeconds сек)"
                
                # Убиваем оставшиеся задачи
                foreach ($runningJob in $runningJobs) {
                    Stop-Job -Job $runningJob
                    Remove-Job -Job $runningJob -Force
                    $failed++
                }
                
                break
            }
            
            Start-Sleep -Milliseconds 500
            
            # Собираем завершенные задачи
            $completedJobs = @(Get-Job -State Completed)
            foreach ($completedJob in $completedJobs) {
                if ($jobs -contains $completedJob) {
                    $result = Receive-Job -Job $completedJob
                    $results += $result
                    Remove-Job -Job $completedJob
                    $jobs = @($jobs | Where-Object { $_ -ne $completedJob })
                    $completed++
                    
                    Write-LogInfo "  Прогресс: $completed из $totalItems"
                }
            }
            
            # Собираем задачи с ошибками
            $failedJobs = @(Get-Job -State Failed)
            foreach ($failedJob in $failedJobs) {
                if ($jobs -contains $failedJob) {
                    Write-LogError "  Задача завершилась с ошибкой"
                    
                    $errorResult = @{
                        Success = $false
                        Errors = @("Job failed")
                    }
                    $results += $errorResult
                    
                    Remove-Job -Job $failedJob
                    $jobs = @($jobs | Where-Object { $_ -ne $failedJob })
                    $failed++
                }
            }
        }
        
        # Очистка оставшихся задач
        $remainingJobs = @(Get-Job)
        foreach ($job in $remainingJobs) {
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        }
        
        Write-LogSeparator
        Write-LogSuccess "Параллельная обработка завершена"
        Write-LogInfo "Завершено успешно: $completed"
        if ($failed -gt 0) {
            Write-LogWarning "Завершено с ошибками: $failed"
        }
        
        return $results
    }
    catch {
        Write-LogError "Критическая ошибка параллельной обработки: $($_.Exception.Message)"
        
        # Очистка всех задач при ошибке
        $allJobs = @(Get-Job)
        foreach ($job in $allJobs) {
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        }
        
        return @()
    }
}

<#
.SYNOPSIS
    Обрабатывает массив элементов последовательно
.PARAMETER Items
    Массив элементов для обработки
.PARAMETER ScriptBlock
    Скриптблок для выполнения
.PARAMETER ItemName
    Название элемента для логирования
.EXAMPLE
    $results = Start-SequentialProcessing -Items $databases -ScriptBlock {
        param($dbPath)
        Invoke-DatabaseMaintenance -DbPath $dbPath
    }
#>
function Start-SequentialProcessing {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Items,
        
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,
        
        [Parameter(Mandatory = $false)]
        [string]$ItemName = "элемент"
    )
    
    try {
        $itemsArray = @($Items)
        
        if (@($itemsArray).Count -eq 0) {
            Write-LogWarning "Нет элементов для обработки"
            return @()
        }
        
        $totalItems = @($itemsArray).Count
        
        Write-LogInfo "Последовательная обработка: $totalItems $ItemName"
        
        $results = @()
        $completed = 0
        
        for ($i = 0; $i -lt @($itemsArray).Count; $i++) {
            $item = $itemsArray[$i]
            
            Write-LogInfo "  Обработка $($i + 1) из $totalItems..."
            
            try {
                $result = & $ScriptBlock $item
                $results += $result
                $completed++
            }
            catch {
                Write-LogError "  Ошибка обработки элемента: $($_.Exception.Message)"
                
                $errorResult = @{
                    Success = $false
                    Errors = @($_.Exception.Message)
                }
                $results += $errorResult
            }
        }
        
        Write-LogSeparator
        Write-LogSuccess "Последовательная обработка завершена"
        Write-LogInfo "Обработано: $completed из $totalItems"
        
        return $results
    }
    catch {
        Write-LogError "Критическая ошибка последовательной обработки: $($_.Exception.Message)"
        return @()
    }
}

#endregion

#region Вспомогательные функции

<#
.SYNOPSIS
    Определяет оптимальное количество параллельных потоков
.PARAMETER ItemCount
    Количество элементов для обработки
.PARAMETER MaxThreads
    Максимальное количество потоков (если не указано - автоопределение)
.EXAMPLE
    $threads = Get-OptimalThreadCount -ItemCount 10
#>
function Get-OptimalThreadCount {
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory = $true)]
        [int]$ItemCount,
        
        [Parameter(Mandatory = $false)]
        [int]$MaxThreads = 0
    )
    
    try {
        # Если указано явно - используем
        if ($MaxThreads -gt 0) {
            return [Math]::Min($MaxThreads, $ItemCount)
        }
        
        # Автоопределение
        $cpuCores = [System.Environment]::ProcessorCount
        $optimalThreads = [Math]::Max(1, $cpuCores - 1)
        
        # Не больше чем элементов
        return [Math]::Min($optimalThreads, $ItemCount)
    }
    catch {
        Write-LogWarning "Ошибка определения количества потоков: $($_.Exception.Message)"
        return 1
    }
}

<#
.SYNOPSIS
    Проверяет, целесообразна ли параллельная обработка
.PARAMETER ItemCount
    Количество элементов
.PARAMETER MinItemsForParallel
    Минимальное количество элементов для параллелизма (по умолчанию: 2)
.EXAMPLE
    $shouldParallel = Test-ShouldUseParallel -ItemCount 5
#>
function Test-ShouldUseParallel {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [int]$ItemCount,
        
        [Parameter(Mandatory = $false)]
        [int]$MinItemsForParallel = 2
    )
    
    return ($ItemCount -ge $MinItemsForParallel)
}

#endregion

# При dot-sourcing все функции автоматически доступны