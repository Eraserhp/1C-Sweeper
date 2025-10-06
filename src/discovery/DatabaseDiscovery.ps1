<#
.SYNOPSIS
    Поиск баз 1С
.DESCRIPTION
    Автоматический поиск информационных баз 1С (.1CD файлов)
    в указанных папках
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
$servicesPath = Join-Path -Path (Split-Path -Parent $scriptPath) -ChildPath "services"

. (Join-Path -Path $corePath -ChildPath "Common.ps1")
. (Join-Path -Path $corePath -ChildPath "LoggingService.ps1")
. (Join-Path -Path $servicesPath -ChildPath "DatabaseService.ps1")

#region Функции поиска

<#
.SYNOPSIS
    Ищет файлы баз данных 1С в указанной папке
.PARAMETER SearchPath
    Путь для поиска
.PARAMETER MaxDepth
    Максимальная глубина поиска (по умолчанию: 2)
.EXAMPLE
    Find-Databases -SearchPath "C:\Bases"
#>
function Find-Databases {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -Path $_ -PathType Container })]
        [string]$SearchPath,
        
        [Parameter(Mandatory = $false)]
        [int]$MaxDepth = 2
    )
    
    $databases = @()
    
    try {
        Write-LogInfo "Поиск баз данных в: $SearchPath"
        
        # Ищем .1CD файлы
        $files = @(Get-ChildItem -Path $SearchPath -Filter "*.1CD" -Recurse -File -Depth $MaxDepth -ErrorAction SilentlyContinue)
        
        foreach ($file in $files) {
            # Проверяем, что это действительно база
            if (Test-Is1CDatabase -Path $file.FullName) {
                $databases += $file.FullName
                Write-LogInfo "  ✓ Найдена база: $($file.FullName)"
            }
        }
        
        Write-LogInfo "  Найдено баз: $(@($databases).Count)"
        
        return $databases
    }
    catch {
        Write-LogError "Ошибка поиска баз в '$SearchPath': $($_.Exception.Message)"
        return @()
    }
}

<#
.SYNOPSIS
    Ищет базы данных в нескольких папках
.PARAMETER SearchPaths
    Массив путей для поиска
.PARAMETER MaxDepth
    Максимальная глубина поиска
.EXAMPLE
    Find-DatabasesInPaths -SearchPaths @("C:\Bases", "D:\1C_Bases")
#>
function Find-DatabasesInPaths {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$SearchPaths,
        
        [Parameter(Mandatory = $false)]
        [int]$MaxDepth = 2
    )
    
    $allDatabases = @()
    
    Write-LogInfo "Поиск баз данных в $(@($SearchPaths).Count) папках..."
    
    foreach ($searchPath in $SearchPaths) {
        if (Test-Path -Path $searchPath -PathType Container) {
            $found = @(Find-Databases -SearchPath $searchPath -MaxDepth $MaxDepth)
            $allDatabases += $found
        }
        else {
            Write-LogWarning "Папка не существует: $searchPath"
        }
    }
    
    # Убираем дубликаты и нормализуем пути
    $uniqueDatabases = @($allDatabases | Select-Object -Unique | ForEach-Object {
        Get-NormalizedPath -Path $_
    } | Select-Object -Unique)
    
    Write-LogSuccess "Всего найдено уникальных баз: $(@($uniqueDatabases).Count)"
    
    return $uniqueDatabases
}

<#
.SYNOPSIS
    Получает список всех баз данных для обслуживания
.PARAMETER ExplicitDatabases
    Массив явно указанных путей к базам
.PARAMETER SearchPaths
    Массив путей для автоматического поиска
.PARAMETER SizeThresholdGB
    Минимальный размер базы (ГБ) для включения в обработку
.PARAMETER MaxDepth
    Максимальная глубина поиска
.EXAMPLE
    Get-AllDatabases -ExplicitDatabases @("C:\Bases\Dev\1Cv8.1CD") -SearchPaths @("C:\Bases")
#>
function Get-AllDatabases {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$ExplicitDatabases = @(),
        
        [Parameter(Mandatory = $false)]
        [string[]]$SearchPaths = @(),
        
        [Parameter(Mandatory = $false)]
        [double]$SizeThresholdGB = 0,
        
        [Parameter(Mandatory = $false)]
        [int]$MaxDepth = 2
    )
    
    $allDatabases = @()
    $validDatabases = @()
    
    try {
        Write-LogSeparator -Title "ПОИСК БАЗ ДАННЫХ 1С"
        
        # 1. Обработка явно указанных баз
        if (@($ExplicitDatabases).Count -gt 0) {
            Write-LogInfo "Проверка явно указанных баз ($(@($ExplicitDatabases).Count))..."
            
            foreach ($dbPath in $ExplicitDatabases) {
                if (Test-Path -Path $dbPath) {
                    if (Test-Is1CDatabase -Path $dbPath) {
                        $allDatabases += $dbPath
                        Write-LogInfo "  ✓ Валидная база: $dbPath"
                    }
                    else {
                        Write-LogWarning "  ⊖ Не является базой 1С: $dbPath"
                    }
                }
                else {
                    Write-LogWarning "  ⊖ Файл не существует: $dbPath"
                }
            }
        }
        
        # 2. Автоматический поиск в указанных папках
        if (@($SearchPaths).Count -gt 0) {
            Write-LogInfo "Автоматический поиск в папках ($(@($SearchPaths).Count))..."
            
            $foundDatabases = @(Find-DatabasesInPaths -SearchPaths $SearchPaths -MaxDepth $MaxDepth)
            
            foreach ($db in $foundDatabases) {
                # Избегаем дубликатов
                if ($allDatabases -notcontains $db) {
                    $allDatabases += $db
                }
            }
        }
        
        Write-LogSeparator
        
        # 3. Удаление дубликатов и нормализация путей
        $uniqueDatabases = @($allDatabases | Select-Object -Unique | ForEach-Object {
            Get-NormalizedPath -Path $_
        } | Select-Object -Unique)
        
        if (@($uniqueDatabases).Count -eq 0) {
            Write-LogWarning "Не найдено ни одной базы данных для обслуживания"
            return @()
        }
        
        Write-LogSuccess "Итого баз данных для обслуживания: $(@($uniqueDatabases).Count)"
        Write-LogInfo "  - Явно указанных: $(@($ExplicitDatabases).Count)"
        Write-LogInfo "  - Найдено автопоиском: $(@($uniqueDatabases).Count - @($ExplicitDatabases).Count)"
        
        # 4. Фильтрация по размеру (если задан порог)
        if ($SizeThresholdGB -gt 0) {
            $validDatabases = @(Get-FilteredDatabases -Databases $uniqueDatabases -SizeThresholdGB $SizeThresholdGB)
        }
        else {
            $validDatabases = $uniqueDatabases
        }
        
        return $validDatabases
    }
    catch {
        Write-LogError "Критическая ошибка при поиске баз: $($_.Exception.Message)"
        return @()
    }
}

<#
.SYNOPSIS
    Фильтрует базы по размеру
.PARAMETER Databases
    Массив путей к базам
.PARAMETER SizeThresholdGB
    Минимальный размер базы (ГБ)
.EXAMPLE
    Get-FilteredDatabases -Databases @("C:\Bases\Dev\1Cv8.1CD") -SizeThresholdGB 3
#>
function Get-FilteredDatabases {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Databases,
        
        [Parameter(Mandatory = $true)]
        [double]$SizeThresholdGB
    )
    
    $filtered = @()
    $belowThreshold = 0
    
    try {
        Write-LogInfo "Фильтрация баз по размеру..."
        Write-LogInfo "  Минимальный размер: $SizeThresholdGB ГБ"
        
        $thresholdBytes = Convert-GBToBytes -GB $SizeThresholdGB
        
        foreach ($dbPath in $Databases) {
            try {
                $sizeBytes = Get-DatabaseSize -DbPath $dbPath
                $sizeGB = Convert-BytesToGB -Bytes $sizeBytes
                
                if ($sizeBytes -ge $thresholdBytes) {
                    $filtered += $dbPath
                    Write-LogInfo "  ✓ Подходит: $dbPath ($sizeGB ГБ)"
                }
                else {
                    $belowThreshold++
                    Write-LogInfo "  ⊖ Меньше порога: $dbPath ($sizeGB ГБ)"
                }
            }
            catch {
                Write-LogWarning "  ⚠ Ошибка проверки размера: $dbPath"
            }
        }
        
        Write-LogSeparator
        Write-LogInfo "Результат фильтрации:"
        Write-LogSuccess "  - Подходящих: $(@($filtered).Count)"
        if ($belowThreshold -gt 0) {
            Write-LogInfo "  - Меньше порога: $belowThreshold"
        }
        
        return $filtered
    }
    catch {
        Write-LogError "Ошибка фильтрации баз: $($_.Exception.Message)"
        return ,$Databases
    }
}

#endregion

# При dot-sourcing все функции автоматически доступны