<#
.SYNOPSIS
    Поиск Git-репозиториев
.DESCRIPTION
    Автоматический поиск Git-репозиториев в указанных папках.
    Поиск выполняется на один уровень вглубь.
.NOTES
    Проект: 1C-Sweeper
    Версия: 1.0
    Дата создания: 2025-10-05
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

$servicesPath = Join-Path -Path (Split-Path -Parent $scriptPath) -ChildPath "services"
. (Join-Path -Path $servicesPath -ChildPath "GitService.ps1")

#region Поиск репозиториев

<#
.SYNOPSIS
    Находит все Git-репозитории в указанной папке
.PARAMETER SearchPath
    Путь к папке для поиска
.PARAMETER MaxDepth
    Максимальная глубина поиска (по умолчанию: 1)
.EXAMPLE
    Find-GitRepositories -SearchPath "C:\Dev"
#>
function Find-GitRepositories {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -Path $_ -PathType Container })]
        [string]$SearchPath,
        
        [Parameter(Mandatory = $false)]
        [int]$MaxDepth = 1
    )
    
    $repositories = @()
    
    try {
        Write-LogInfo "Поиск репозиториев в: $SearchPath"
        
        # Проверяем, не является ли сама папка репозиторием
        if (Test-IsGitRepository -Path $SearchPath) {
            Write-LogInfo "  ✓ Найден репозиторий: $SearchPath"
            $repositories += $SearchPath
            return ,$repositories
        }
        
        # Ищем на указанную глубину
        $currentDepth = 0
        $foldersToCheck = @($SearchPath)
        
        while ($currentDepth -lt $MaxDepth -and $foldersToCheck.Count -gt 0) {
            $nextLevelFolders = @()
            
            foreach ($folder in $foldersToCheck) {
                try {
                    # Получаем подпапки
                    $subfolders = Get-ChildItem -Path $folder -Directory -Force -ErrorAction SilentlyContinue |
                                  Where-Object { $_.Name -ne '.git' }  # Исключаем .git папки
                    
                    foreach ($subfolder in $subfolders) {
                        $subfolderPath = $subfolder.FullName
                        
                        # Проверяем, является ли это репозиторием
                        if (Test-IsGitRepository -Path $subfolderPath) {
                            Write-LogInfo "  ✓ Найден репозиторий: $subfolderPath"
                            $repositories += $subfolderPath
                        }
                        else {
                            # Добавляем в список для проверки на следующем уровне
                            $nextLevelFolders += $subfolderPath
                        }
                    }
                }
                catch {
                    Write-LogWarning "  Ошибка доступа к папке '$folder': $($_.Exception.Message)"
                }
            }
            
            $foldersToCheck = $nextLevelFolders
            $currentDepth++
        }
        
        Write-LogInfo "  Найдено репозиториев: $($repositories.Count)"
        
        return ,$repositories
    }
    catch {
        Write-LogError "Ошибка поиска репозиториев в '$SearchPath': $($_.Exception.Message)"
        return @()
    }
}

<#
.SYNOPSIS
    Находит все Git-репозитории в нескольких папках
.PARAMETER SearchPaths
    Массив путей для поиска
.PARAMETER MaxDepth
    Максимальная глубина поиска (по умолчанию: 1)
.EXAMPLE
    Find-GitRepositoriesInPaths -SearchPaths @("C:\Dev", "D:\Projects")
#>
function Find-GitRepositoriesInPaths {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$SearchPaths,
        
        [Parameter(Mandatory = $false)]
        [int]$MaxDepth = 1
    )
    
    $allRepositories = @()
    
    Write-LogInfo "Поиск Git-репозиториев в $(@($SearchPaths).Count) папках..."
    
    foreach ($searchPath in $SearchPaths) {
        if (Test-Path -Path $searchPath -PathType Container) {
            $found = Find-GitRepositories -SearchPath $searchPath -MaxDepth $MaxDepth
            $allRepositories += $found
        }
        else {
            Write-LogWarning "Папка не существует: $searchPath"
        }
    }
    
    # Убираем дубликаты
    $uniqueRepositories = $allRepositories | Select-Object -Unique
    
    Write-LogSuccess "Всего найдено уникальных репозиториев: $($uniqueRepositories.Count)"
    
    return ,$uniqueRepositories
}

<#
.SYNOPSIS
    Получает список всех Git-репозиториев (явные + найденные)
.PARAMETER ExplicitRepos
    Массив явно указанных путей к репозиториям
.PARAMETER SearchPaths
    Массив путей для автоматического поиска
.PARAMETER MaxDepth
    Максимальная глубина поиска (по умолчанию: 1)
.EXAMPLE
    Get-AllGitRepositories -ExplicitRepos @("C:\Dev\Project1") -SearchPaths @("D:\Projects")
#>
function Get-AllGitRepositories {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$ExplicitRepos = @(),
        
        [Parameter(Mandatory = $false)]
        [string[]]$SearchPaths = @(),
        
        [Parameter(Mandatory = $false)]
        [int]$MaxDepth = 1
    )
    
    Write-LogSeparator -Title "ПОИСК GIT-РЕПОЗИТОРИЕВ"
    
    $validRepos = @()
    $invalidRepos = @()
    $foundRepos = @()
    
    # Обработка явно указанных репозиториев
    if (@($ExplicitRepos).Count -gt 0) {
        Write-LogInfo "Проверка явно указанных репозиториев ($(@($ExplicitRepos).Count))..."
        
        foreach ($repo in $ExplicitRepos) {
            if (Test-Path -Path $repo) {
                if (Test-IsGitRepository -Path $repo) {
                    Write-LogInfo "  ✓ Валидный репозиторий: $repo"
                    $validRepos += $repo
                }
                else {
                    Write-LogWarning "  ✗ Не является Git-репозиторием: $repo"
                    $invalidRepos += $repo
                }
            }
            else {
                Write-LogWarning "  ✗ Путь не существует: $repo"
                $invalidRepos += $repo
            }
        }
    }
    
    # Автоматический поиск
    if (@($SearchPaths).Count -gt 0) {
        Write-LogInfo "`nАвтоматический поиск в $(@($SearchPaths).Count) папках..."
        $foundRepos = Find-GitRepositoriesInPaths -SearchPaths $SearchPaths -MaxDepth $MaxDepth
    }
    
    # Объединение и устранение дубликатов
    $allRepos = @($validRepos) + @($foundRepos) | Select-Object -Unique
    
    Write-LogSeparator
    Write-LogSuccess "Итого Git-репозиториев для обслуживания: $(@($allRepos).Count)"
    
    if (@($validRepos).Count -gt 0) {
        Write-LogInfo "  - Явно указанных: $(@($validRepos).Count)"
    }
    if (@($foundRepos).Count -gt 0) {
        Write-LogInfo "  - Найдено автоматически: $(@($foundRepos).Count)"
    }
    if (@($invalidRepos).Count -gt 0) {
        Write-LogWarning "  - Невалидных путей: $(@($invalidRepos).Count)"
    }
    
    return @{
        AllRepositories = $allRepos
        ExplicitValid = $validRepos
        ExplicitInvalid = $invalidRepos
        Found = $foundRepos
        TotalCount = @($allRepos).Count
    }
}

#endregion

#region Фильтрация репозиториев

<#
.SYNOPSIS
    Фильтрует репозитории по размеру
.PARAMETER Repositories
    Массив путей к репозиториям
.PARAMETER MinSizeGB
    Минимальный размер в ГБ (по умолчанию: 0)
.PARAMETER MaxSizeGB
    Максимальный размер в ГБ (по умолчанию: не ограничен)
.EXAMPLE
    Filter-GitRepositoriesBySize -Repositories @("C:\Dev\Repo1") -MinSizeGB 15
#>
function Filter-GitRepositoriesBySize {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Repositories,
        
        [Parameter(Mandatory = $false)]
        [double]$MinSizeGB = 0.0,
        
        [Parameter(Mandatory = $false)]
        [double]$MaxSizeGB = [double]::MaxValue
    )
    
    $matched = @()
    $belowThreshold = @()
    $aboveThreshold = @()
    
    Write-LogInfo "Фильтрация репозиториев по размеру..."
    Write-LogInfo "  Минимальный размер: $MinSizeGB ГБ"
    if ($MaxSizeGB -lt [double]::MaxValue) {
        Write-LogInfo "  Максимальный размер: $MaxSizeGB ГБ"
    }
    
    foreach ($repo in $Repositories) {
        $size = Get-GitRepositorySize -RepoPath $repo
        $sizeGB = Convert-BytesToGB -Bytes $size
        
        if ($sizeGB -lt $MinSizeGB) {
            $belowThreshold += $repo
            Write-LogInfo "  ⊖ Меньше порога: $repo ($sizeGB ГБ)"
        }
        elseif ($sizeGB -gt $MaxSizeGB) {
            $aboveThreshold += $repo
            Write-LogInfo "  ⊕ Больше порога: $repo ($sizeGB ГБ)"
        }
        else {
            $matched += $repo
            Write-LogInfo "  ✓ Подходит: $repo ($sizeGB ГБ)"
        }
    }
    
    Write-LogInfo "`nРезультат фильтрации:"
    Write-LogSuccess "  - Подходящих: $($matched.Count)"
    if ($belowThreshold.Count -gt 0) {
        Write-LogInfo "  - Меньше порога: $($belowThreshold.Count)"
    }
    if ($aboveThreshold.Count -gt 0) {
        Write-LogInfo "  - Больше порога: $($aboveThreshold.Count)"
    }
    
    return @{
        Matched = $matched
        BelowThreshold = $belowThreshold
        AboveThreshold = $aboveThreshold
    }
}

#endregion