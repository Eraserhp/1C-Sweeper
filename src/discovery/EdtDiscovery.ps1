<#
.SYNOPSIS
    Автопоиск EDT workspace
.DESCRIPTION
    Автоматический поиск EDT workspace в указанных папках
    и объединение с явно указанными workspace
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
$servicesPath = Join-Path -Path (Split-Path -Parent $scriptPath) -ChildPath "services"

. (Join-Path -Path $corePath -ChildPath "Common.ps1")
. (Join-Path -Path $corePath -ChildPath "LoggingService.ps1")
. (Join-Path -Path $servicesPath -ChildPath "EdtService.ps1")

#region Функции поиска

<#
.SYNOPSIS
    Ищет EDT workspace в указанной папке
.PARAMETER SearchPath
    Путь для поиска workspace
.PARAMETER MaxDepth
    Максимальная глубина поиска (по умолчанию: 1 - только прямые подпапки)
.EXAMPLE
    Find-EdtWorkspaces -SearchPath "C:\EDT"
#>
function Find-EdtWorkspaces {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -Path $_ -PathType Container })]
        [string]$SearchPath,
        
        [Parameter(Mandatory = $false)]
        [int]$MaxDepth = 1
    )
    
    $foundWorkspaces = @()
    
    try {
        Write-LogInfo "Поиск workspace в: $SearchPath"
        
        # Проверяем сам путь
        if (Test-IsEdtWorkspace -Path $SearchPath) {
            $foundWorkspaces += $SearchPath
            Write-LogInfo "  ✓ Найден workspace: $SearchPath"
        }
        
        # Ищем на указанную глубину
        if ($MaxDepth -gt 0) {
            $subdirs = Get-ChildItem -Path $SearchPath -Directory -ErrorAction SilentlyContinue
            
            foreach ($subdir in $subdirs) {
                # Пропускаем скрытые папки и системные
                if ($subdir.Attributes -match 'Hidden|System') {
                    continue
                }
                
                # Проверяем, является ли папка workspace
                if (Test-IsEdtWorkspace -Path $subdir.FullName) {
                    $foundWorkspaces += $subdir.FullName
                    Write-LogInfo "  ✓ Найден workspace: $($subdir.FullName)"
                }
                
                # Рекурсивный поиск на следующем уровне (если MaxDepth > 1)
                if ($MaxDepth -gt 1) {
                    $nestedWorkspaces = Find-EdtWorkspaces -SearchPath $subdir.FullName -MaxDepth ($MaxDepth - 1)
                    $foundWorkspaces += $nestedWorkspaces
                }
            }
        }
        
        Write-LogInfo "  Найдено workspace: $($foundWorkspaces.Count)"
        
        return $foundWorkspaces
    }
    catch {
        Write-LogError "Ошибка поиска workspace в '$SearchPath': $($_.Exception.Message)"
        return @()
    }
}

<#
.SYNOPSIS
    Получает полный список workspace для обслуживания
.PARAMETER ExplicitPaths
    Массив явно указанных путей к workspace
.PARAMETER SearchPaths
    Массив путей для автоматического поиска workspace
.PARAMETER SizeThresholdGB
    Минимальный размер workspace (ГБ) для включения в обработку
.EXAMPLE
    Get-AllEdtWorkspaces -ExplicitPaths @("C:\EDT\ws1") -SearchPaths @("C:\EDT", "D:\Workspaces")
#>
function Get-AllEdtWorkspaces {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$ExplicitPaths = @(),
        
        [Parameter(Mandatory = $false)]
        [string[]]$SearchPaths = @(),
        
        [Parameter(Mandatory = $false)]
        [double]$SizeThresholdGB = 0
    )
    
    $allWorkspaces = @()
    $validWorkspaces = @()
    
    try {
        Write-LogSeparator -Title "ПОИСК EDT WORKSPACE"
        
        # 1. Обработка явно указанных workspace
        if ($ExplicitPaths.Count -gt 0) {
            Write-LogInfo "Проверка явно указанных workspace ($($ExplicitPaths.Count))..."
            
            foreach ($wsPath in $ExplicitPaths) {
                if (Test-Path -Path $wsPath) {
                    if (Test-IsEdtWorkspace -Path $wsPath) {
                        $allWorkspaces += $wsPath
                        Write-LogInfo "  ✓ Валидный workspace: $wsPath"
                    }
                    else {
                        Write-LogWarning "  ⊖ Не является workspace: $wsPath"
                    }
                }
                else {
                    Write-LogWarning "  ⊖ Путь не существует: $wsPath"
                }
            }
        }
        
        # 2. Автоматический поиск в указанных папках
        if ($SearchPaths.Count -gt 0) {
            Write-LogInfo "Автоматический поиск в папках ($($SearchPaths.Count))..."
            
            foreach ($searchPath in $SearchPaths) {
                if (Test-Path -Path $searchPath) {
                    $foundWorkspaces = Find-EdtWorkspaces -SearchPath $searchPath -MaxDepth 1
                    
                    foreach ($ws in $foundWorkspaces) {
                        # Избегаем дубликатов
                        if ($allWorkspaces -notcontains $ws) {
                            $allWorkspaces += $ws
                        }
                    }
                }
                else {
                    Write-LogWarning "  ⊖ Папка поиска не существует: $searchPath"
                }
            }
        }
        
        Write-LogSeparator
        
        # 3. Удаление дубликатов и нормализация путей
        $uniqueWorkspaces = $allWorkspaces | Select-Object -Unique | ForEach-Object {
            Get-NormalizedPath -Path $_
        } | Select-Object -Unique
        
        if ($uniqueWorkspaces.Count -eq 0) {
            Write-LogWarning "Не найдено ни одного workspace для обслуживания"
            return @()
        }
        
        Write-LogSuccess "Итого EDT workspace для обслуживания: $($uniqueWorkspaces.Count)"
        Write-LogInfo "  - Явно указанных: $($ExplicitPaths.Count)"
        Write-LogInfo "  - Найдено автопоиском: $($uniqueWorkspaces.Count - $ExplicitPaths.Count)"
        
        # 4. Фильтрация по размеру (если задан порог)
        if ($SizeThresholdGB -gt 0) {
            $validWorkspaces = Get-FilteredEdtWorkspaces -Workspaces $uniqueWorkspaces -SizeThresholdGB $SizeThresholdGB
        }
        else {
            $validWorkspaces = $uniqueWorkspaces
        }
        
        return $validWorkspaces
    }
    catch {
        Write-LogError "Критическая ошибка при поиске workspace: $($_.Exception.Message)"
        return @()
    }
}

<#
.SYNOPSIS
    Фильтрует workspace по размеру
.PARAMETER Workspaces
    Массив путей к workspace
.PARAMETER SizeThresholdGB
    Минимальный размер workspace (ГБ)
.EXAMPLE
    Get-FilteredEdtWorkspaces -Workspaces @("C:\EDT\ws1", "C:\EDT\ws2") -SizeThresholdGB 5
#>
function Get-FilteredEdtWorkspaces {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Workspaces,
        
        [Parameter(Mandatory = $true)]
        [double]$SizeThresholdGB
    )
    
    $filtered = @()
    $belowThreshold = 0
    
    try {
        Write-LogInfo "Фильтрация workspace по размеру..."
        Write-LogInfo "  Минимальный размер: $SizeThresholdGB ГБ"
        
        $thresholdBytes = Convert-GBToBytes -GB $SizeThresholdGB
        
        foreach ($wsPath in $Workspaces) {
            try {
                $sizeBytes = Get-EdtWorkspaceSize -Path $wsPath
                $sizeGB = Convert-BytesToGB -Bytes $sizeBytes
                
                if ($sizeBytes -ge $thresholdBytes) {
                    $filtered += $wsPath
                    Write-LogInfo "  ✓ Подходит: $wsPath ($sizeGB ГБ)"
                }
                else {
                    $belowThreshold++
                    Write-LogInfo "  ⊖ Меньше порога: $wsPath ($sizeGB ГБ)"
                }
            }
            catch {
                Write-LogWarning "  ⚠ Ошибка проверки размера: $wsPath"
            }
        }
        
        Write-LogInfo ""
        Write-LogInfo "Результат фильтрации:"
        Write-LogSuccess "  - Подходящих: $($filtered.Count)"
        if ($belowThreshold -gt 0) {
            Write-LogInfo "  - Меньше порога: $belowThreshold"
        }
        
        return $filtered
    }
    catch {
        Write-LogError "Ошибка фильтрации workspace: $($_.Exception.Message)"
        return $Workspaces
    }
}

#endregion
