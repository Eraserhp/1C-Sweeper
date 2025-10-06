<#
.SYNOPSIS
    Генерация отчетов
.DESCRIPTION
    Формирование детальных JSON-отчетов о выполненных операциях обслуживания.
    Сбор статистики, расчет освобожденного места, агрегация данных.
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

#region Создание отчета

<#
.SYNOPSIS
    Создает новый объект отчета
.EXAMPLE
    $report = New-Report
#>
function New-Report {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    
    return @{
        ReportVersion = "1.0"
        Timestamp = Get-Timestamp
        Hostname = Get-HostName
        StartTime = Get-Date
        Duration = 0
        Summary = @{
            TotalSpaceSaved = 0.0
            GitReposProcessed = 0
            GitReposSuccess = 0
            GitReposFailed = 0
            WorkspacesProcessed = 0
            WorkspacesSuccess = 0
            WorkspacesFailed = 0
            DatabasesProcessed = 0
            DatabasesSuccess = 0
            DatabasesFailed = 0
        }
        GitRepositories = @()
        EdtWorkspaces = @()
        Databases = @()
        Errors = @()
    }
}

#endregion

#region Добавление результатов

<#
.SYNOPSIS
    Добавляет результат обработки Git-репозитория в отчет
.PARAMETER Report
    Объект отчета
.PARAMETER Result
    Результат обработки репозитория
.EXAMPLE
    Add-GitResult -Report $report -Result $gitResult
#>
function Add-GitResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Report,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$Result
    )
    
    try {
        # Формируем запись для отчета
        $entry = @{
            Path = $Result.Path
            SizeBefore = $Result.SizeBefore
            SizeAfter = $Result.SizeAfter
            SpaceSaved = $Result.SpaceSaved
            Duration = $Result.Duration
            Actions = $Result.Actions
            Status = if ($Result.Success) { "success" } else { "failed" }
            Skipped = if ($Result.Skipped) { $true } else { $false }
            Errors = @($Result.Errors)
        }
        
        # Добавляем в отчет
        $Report.GitRepositories += $entry
        
        # Обновляем сводку
        $Report.Summary.GitReposProcessed++
        
        if ($Result.Success) {
            $Report.Summary.GitReposSuccess++
            $Report.Summary.TotalSpaceSaved += $Result.SpaceSaved
        } else {
            $Report.Summary.GitReposFailed++
        }
        
        # Добавляем ошибки в общий список
        foreach ($error in $Result.Errors) {
            $Report.Errors += @{
                Type = "Git"
                Path = $Result.Path
                Message = $error
            }
        }
    }
    catch {
        Write-LogError "Ошибка добавления Git-результата: $($_.Exception.Message)"
    }
}

<#
.SYNOPSIS
    Добавляет результат обработки EDT workspace в отчет
.PARAMETER Report
    Объект отчета
.PARAMETER Result
    Результат обработки workspace
.EXAMPLE
    Add-EdtResult -Report $report -Result $edtResult
#>
function Add-EdtResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Report,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$Result
    )
    
    try {
        # Конвертируем байты в ГБ
        $sizeBeforeGB = Convert-BytesToGB -Bytes $Result.SizeBefore
        $sizeAfterGB = Convert-BytesToGB -Bytes $Result.SizeAfter
        $spaceSavedGB = Convert-BytesToGB -Bytes $Result.SpaceSaved
        
        # Формируем запись для отчета
        $entry = @{
            Path = $Result.Path
            SizeBefore = $sizeBeforeGB
            SizeAfter = $sizeAfterGB
            SpaceSaved = $spaceSavedGB
            Duration = $Result.Duration
            Actions = $Result.Actions
            Status = if ($Result.Success) { "success" } else { "failed" }
            Errors = @($Result.Errors)
        }
        
        # Добавляем в отчет
        $Report.EdtWorkspaces += $entry
        
        # Обновляем сводку
        $Report.Summary.WorkspacesProcessed++
        
        if ($Result.Success) {
            $Report.Summary.WorkspacesSuccess++
            $Report.Summary.TotalSpaceSaved += $spaceSavedGB
        } else {
            $Report.Summary.WorkspacesFailed++
        }
        
        # Добавляем ошибки в общий список
        foreach ($error in $Result.Errors) {
            $Report.Errors += @{
                Type = "EDT"
                Path = $Result.Path
                Message = $error
            }
        }
    }
    catch {
        Write-LogError "Ошибка добавления EDT-результата: $($_.Exception.Message)"
    }
}

<#
.SYNOPSIS
    Добавляет результат обработки базы 1С в отчет
.PARAMETER Report
    Объект отчета
.PARAMETER Result
    Результат обработки базы
.EXAMPLE
    Add-DatabaseResult -Report $report -Result $dbResult
#>
function Add-DatabaseResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Report,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$Result
    )
    
    try {
        # Формируем запись для отчета
        $entry = @{
            Path = $Result.Path
            SizeBefore = $Result.SizeBefore
            SizeAfter = $Result.SizeAfter
            SpaceSaved = $Result.SpaceSaved
            Duration = $Result.Duration
            Platform = $Result.Platform
            Actions = $Result.Actions
            Status = if ($Result.Success) { "success" } else { "failed" }
            Skipped = if ($Result.Skipped) { $true } else { $false }
            Errors = @($Result.Errors)
        }
        
        # Добавляем в отчет
        $Report.Databases += $entry
        
        # Обновляем сводку
        $Report.Summary.DatabasesProcessed++
        
        if ($Result.Success) {
            $Report.Summary.DatabasesSuccess++
            $Report.Summary.TotalSpaceSaved += $Result.SpaceSaved
        } else {
            $Report.Summary.DatabasesFailed++
        }
        
        # Добавляем ошибки в общий список
        foreach ($error in $Result.Errors) {
            $Report.Errors += @{
                Type = "Database"
                Path = $Result.Path
                Message = $error
            }
        }
    }
    catch {
        Write-LogError "Ошибка добавления Database-результата: $($_.Exception.Message)"
    }
}

#endregion

#region Финализация и сохранение

<#
.SYNOPSIS
    Завершает формирование отчета (рассчитывает длительность)
.PARAMETER Report
    Объект отчета
.EXAMPLE
    Complete-Report -Report $report
#>
function Complete-Report {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Report
    )
    
    try {
        if ($Report.ContainsKey('StartTime')) {
            $endTime = Get-Date
            $Report.Duration = [int](($endTime - $Report.StartTime).TotalSeconds)
            
            # Удаляем служебное поле StartTime из финального отчета
            $Report.Remove('StartTime')
        }
        
        # Округляем TotalSpaceSaved
        if ($Report.ContainsKey('Summary')) {
            $Report.Summary.TotalSpaceSaved = [Math]::Round($Report.Summary.TotalSpaceSaved, 2)
        }
    }
    catch {
        Write-LogError "Ошибка завершения отчета: $($_.Exception.Message)"
    }
}

<#
.SYNOPSIS
    Сохраняет отчет в JSON-файл
.PARAMETER Report
    Объект отчета
.PARAMETER ReportsPath
    Путь к папке для сохранения отчетов
.PARAMETER FileName
    Имя файла (опционально, если не указано - генерируется автоматически)
.EXAMPLE
    Save-Report -Report $report -ReportsPath "C:\Reports"
#>
function Save-Report {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Report,
        
        [Parameter(Mandatory = $true)]
        [string]$ReportsPath,
        
        [Parameter(Mandatory = $false)]
        [string]$FileName = ""
    )
    
    try {
        # Завершаем отчет (рассчитываем длительность)
        Complete-Report -Report $Report
        
        # Убеждаемся, что папка существует
        Ensure-DirectoryExists -Path $ReportsPath | Out-Null
        
        # Генерируем имя файла, если не указано
        if ([string]::IsNullOrEmpty($FileName)) {
            $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
            $hostname = Get-HostName
            $FileName = "maintenance-report_${hostname}_${timestamp}.json"
        }
        
        $fullPath = Join-Path -Path $ReportsPath -ChildPath $FileName
        
        # Конвертируем в JSON с отступами
        $jsonContent = $Report | ConvertTo-Json -Depth 10
        
        # Сохраняем в файл с UTF-8
        [System.IO.File]::WriteAllText($fullPath, $jsonContent, [System.Text.Encoding]::UTF8)
        
        Write-LogSuccess "Отчет сохранен: $fullPath"
        
        return $fullPath
    }
    catch {
        Write-LogError "Ошибка сохранения отчета: $($_.Exception.Message)"
        return ""
    }
}

#endregion

#region Вспомогательные функции

<#
.SYNOPSIS
    Получает сводную информацию из отчета
.PARAMETER Report
    Объект отчета
.EXAMPLE
    $summary = Get-ReportSummary -Report $report
#>
function Get-ReportSummary {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Report
    )
    
    return $Report.Summary
}

<#
.SYNOPSIS
    Выводит сводку отчета в консоль
.PARAMETER Report
    Объект отчета
.EXAMPLE
    Show-ReportSummary -Report $report
#>
function Show-ReportSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Report
    )
    
    try {
        Write-LogSeparator -Title "ИТОГИ ОБСЛУЖИВАНИЯ"
        
        $summary = $Report.Summary
        
        # Git-репозитории
        if ($summary.GitReposProcessed -gt 0) {
            Write-LogInfo "Git-репозитории:"
            Write-LogInfo "  Обработано:  $($summary.GitReposProcessed)"
            Write-LogSuccess "  Успешно:     $($summary.GitReposSuccess)"
            if ($summary.GitReposFailed -gt 0) {
                Write-LogError "  Ошибок:      $($summary.GitReposFailed)"
            }
        }
        
        # EDT workspaces
        if ($summary.WorkspacesProcessed -gt 0) {
            Write-LogInfo "`nEDT workspaces:"
            Write-LogInfo "  Обработано:  $($summary.WorkspacesProcessed)"
            Write-LogSuccess "  Успешно:     $($summary.WorkspacesSuccess)"
            if ($summary.WorkspacesFailed -gt 0) {
                Write-LogError "  Ошибок:      $($summary.WorkspacesFailed)"
            }
        }
        
        # Базы данных 1С
        if ($summary.DatabasesProcessed -gt 0) {
            Write-LogInfo "`nБазы данных 1С:"
            Write-LogInfo "  Обработано:  $($summary.DatabasesProcessed)"
            Write-LogSuccess "  Успешно:     $($summary.DatabasesSuccess)"
            if ($summary.DatabasesFailed -gt 0) {
                Write-LogError "  Ошибок:      $($summary.DatabasesFailed)"
            }
        }
        
        # Итого
        Write-LogSeparator
        $totalProcessed = $summary.GitReposProcessed + $summary.WorkspacesProcessed + $summary.DatabasesProcessed
        $totalSuccess = $summary.GitReposSuccess + $summary.WorkspacesSuccess + $summary.DatabasesSuccess
        $totalFailed = $summary.GitReposFailed + $summary.WorkspacesFailed + $summary.DatabasesFailed
        
        Write-LogInfo "Всего объектов:"
        Write-LogInfo "  Обработано:  $totalProcessed"
        Write-LogSuccess "  Успешно:     $totalSuccess"
        if ($totalFailed -gt 0) {
            Write-LogError "  Ошибок:      $totalFailed"
        }
        
        Write-LogSeparator
        Write-LogSuccess "ОСВОБОЖДЕНО МЕСТА: $($summary.TotalSpaceSaved) ГБ"
        
        $durationText = Format-Duration -Seconds $Report.Duration
        Write-LogInfo "ВРЕМЯ ВЫПОЛНЕНИЯ: $durationText"
        
        Write-LogSeparator
        
        # Ошибки
        if (@($Report.Errors).Count -gt 0) {
            Write-LogWarning "`nОбнаружены ошибки ($(@($Report.Errors).Count)):"
            foreach ($error in $Report.Errors) {
                Write-LogWarning "  [$($error.Type)] $($error.Path): $($error.Message)"
            }
        }
    }
    catch {
        Write-LogError "Ошибка вывода сводки: $($_.Exception.Message)"
    }
}

<#
.SYNOPSIS
    Проверяет, есть ли в отчете ошибки
.PARAMETER Report
    Объект отчета
.EXAMPLE
    $hasErrors = Test-ReportHasErrors -Report $report
#>
function Test-ReportHasErrors {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Report
    )
    
    return (@($Report.Errors).Count -gt 0)
}

<#
.SYNOPSIS
    Получает количество успешно обработанных объектов
.PARAMETER Report
    Объект отчета
.EXAMPLE
    $successCount = Get-ReportSuccessCount -Report $report
#>
function Get-ReportSuccessCount {
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Report
    )
    
    $summary = $Report.Summary
    return ($summary.GitReposSuccess + $summary.WorkspacesSuccess + $summary.DatabasesSuccess)
}

<#
.SYNOPSIS
    Получает количество обработанных объектов с ошибками
.PARAMETER Report
    Объект отчета
.EXAMPLE
    $failedCount = Get-ReportFailedCount -Report $report
#>
function Get-ReportFailedCount {
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Report
    )
    
    $summary = $Report.Summary
    return ($summary.GitReposFailed + $summary.WorkspacesFailed + $summary.DatabasesFailed)
}

#endregion