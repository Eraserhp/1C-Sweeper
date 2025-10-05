<#
.SYNOPSIS
    Обслуживание Git-репозиториев
.DESCRIPTION
    Оптимизация и очистка Git-репозиториев:
    - Очистка удаленных веток
    - Упаковка объектов
    - Удаление недоступных объектов
    - Сборка мусора
    - Проверка целостности
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

#region Проверка Git

<#
.SYNOPSIS
    Проверяет, установлен ли Git и доступен из командной строки
.EXAMPLE
    Test-GitAvailable
#>
function Test-GitAvailable {
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    
    try {
        $null = git --version 2>&1
        return $true
    }
    catch {
        return $false
    }
}

<#
.SYNOPSIS
    Проверяет, является ли указанный путь Git-репозиторием
.PARAMETER Path
    Путь к директории
.EXAMPLE
    Test-IsGitRepository -Path "C:\Dev\Project1"
#>
function Test-IsGitRepository {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    
    if (-not (Test-Path -Path $Path -PathType Container)) {
        return $false
    }
    
    $gitDir = Join-Path -Path $Path -ChildPath ".git"
    return (Test-Path -Path $gitDir)
}

<#
.SYNOPSIS
    Получает размер Git-репозитория в байтах
.PARAMETER RepoPath
    Путь к репозиторию
.PARAMETER GitDirOnly
    Считать только размер .git (по умолчанию: false)
.EXAMPLE
    Get-GitRepositorySize -RepoPath "C:\Dev\Project1"
#>
function Get-GitRepositorySize {
    [CmdletBinding()]
    [OutputType([long])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-IsGitRepository -Path $_ })]
        [string]$RepoPath,
        
        [Parameter(Mandatory = $false)]
        [bool]$GitDirOnly = $false
    )
    
    try {
        if ($GitDirOnly) {
            $gitDir = Join-Path -Path $RepoPath -ChildPath ".git"
            return Get-DirectorySize -Path $gitDir
        }
        else {
            return Get-DirectorySize -Path $RepoPath
        }
    }
    catch {
        Write-LogWarning "Ошибка получения размера репозитория '$RepoPath': $($_.Exception.Message)"
        return 0
    }
}

#endregion

#region Выполнение Git-команд

<#
.SYNOPSIS
    Выполняет Git-команду в контексте репозитория
.PARAMETER RepoPath
    Путь к репозиторию
.PARAMETER Command
    Git-команда (без "git")
.PARAMETER TimeoutSeconds
    Таймаут выполнения в секундах (по умолчанию: 3600 = 1 час)
.EXAMPLE
    Invoke-GitCommand -RepoPath "C:\Dev\Project1" -Command "gc --prune=now"
#>
function Invoke-GitCommand {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoPath,
        
        [Parameter(Mandatory = $true)]
        [string]$Command,
        
        [Parameter(Mandatory = $false)]
        [int]$TimeoutSeconds = 3600
    )
    
    $startTime = Get-Date
    
    try {
        Write-LogInfo "    Выполнение: git $Command"
        
        # Сохраняем текущую директорию
        $originalLocation = Get-Location
        
        # Переходим в директорию репозитория
        Set-Location -Path $RepoPath
        
        # Выполняем команду
        $gitArgs = $Command -split '\s+'
        $output = & git @gitArgs 2>&1
        $exitCode = $LASTEXITCODE

        # Возвращаемся в исходную директорию
        Set-Location -Path $originalLocation
        
        $duration = ((Get-Date) - $startTime).TotalSeconds
        
        if ($exitCode -eq 0) {
            Write-LogInfo "    ✓ Команда выполнена успешно ($(Format-Duration -Seconds ([int]$duration)))"
            
            return @{
                Success = $true
                Output = $output
                ExitCode = $exitCode
                Duration = [int]$duration
                Error = $null
            }
        }
        else {
            $errorMessage = if ($output) { $output -join "`n" } else { "Неизвестная ошибка" }
            Write-LogWarning "    ⚠ Команда завершилась с кодом $exitCode"
            
            return @{
                Success = $false
                Output = $output
                ExitCode = $exitCode
                Duration = [int]$duration
                Error = $errorMessage
            }
        }
    }
    catch {
        # Возвращаемся в исходную директорию в случае ошибки
        if ($originalLocation) {
            Set-Location -Path $originalLocation
        }
        
        $duration = ((Get-Date) - $startTime).TotalSeconds
        $errorMessage = $_.Exception.Message
        
        Write-LogError "    ✗ Ошибка выполнения команды: $errorMessage"
        
        return @{
            Success = $false
            Output = $null
            ExitCode = -1
            Duration = [int]$duration
            Error = $errorMessage
        }
    }
}

#endregion

#region Основные операции обслуживания

<#
.SYNOPSIS
    Очищает ссылки на удаленные ветки
.PARAMETER RepoPath
    Путь к репозиторию
.EXAMPLE
    Invoke-GitPruneRemote -RepoPath "C:\Dev\Project1"
#>
function Invoke-GitPruneRemote {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoPath
    )
    
    Write-LogInfo "  [1/4] Очистка ссылок на удаленные ветки..."
    return Invoke-GitCommand -RepoPath $RepoPath -Command "remote prune origin"
}

<#
.SYNOPSIS
    Упаковывает loose objects
.PARAMETER RepoPath
    Путь к репозиторию
.EXAMPLE
    Invoke-GitRepack -RepoPath "C:\Dev\Project1"
#>
function Invoke-GitRepack {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoPath
    )
    
    Write-LogInfo "  [2/4] Упаковка объектов..."
    return Invoke-GitCommand -RepoPath $RepoPath -Command "repack -ad"
}

<#
.SYNOPSIS
    Удаляет недоступные объекты
.PARAMETER RepoPath
    Путь к репозиторию
.EXAMPLE
    Invoke-GitPrune -RepoPath "C:\Dev\Project1"
#>
function Invoke-GitPrune {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoPath
    )
    
    Write-LogInfo "  [3/4] Удаление недоступных объектов..."
    return Invoke-GitCommand -RepoPath $RepoPath -Command "prune --expire=now"
}

<#
.SYNOPSIS
    Выполняет сборку мусора
.PARAMETER RepoPath
    Путь к репозиторию
.EXAMPLE
    Invoke-GitGC -RepoPath "C:\Dev\Project1"
#>
function Invoke-GitGC {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoPath
    )
    
    Write-LogInfo "  [4/4] Сборка мусора..."
    return Invoke-GitCommand -RepoPath $RepoPath -Command "gc --prune=now"
}

<#
.SYNOPSIS
    Проверяет целостность репозитория (опционально)
.PARAMETER RepoPath
    Путь к репозиторию
.EXAMPLE
    Invoke-GitFsck -RepoPath "C:\Dev\Project1"
#>
function Invoke-GitFsck {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoPath
    )
    
    Write-LogInfo "  [Опционально] Проверка целостности..."
    return Invoke-GitCommand -RepoPath $RepoPath -Command "fsck --full"
}

#endregion

#region Полное обслуживание

<#
.SYNOPSIS
    Выполняет полное обслуживание Git-репозитория
.PARAMETER RepoPath
    Путь к репозиторию
.PARAMETER SizeThresholdGB
    Порог размера для запуска обслуживания (в ГБ)
.PARAMETER SkipFsck
    Пропустить проверку целостности (по умолчанию: true)
.EXAMPLE
    Invoke-GitMaintenance -RepoPath "C:\Dev\Project1" -SizeThresholdGB 15
#>
function Invoke-GitMaintenance {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoPath,
        
        [Parameter(Mandatory = $false)]
        [double]$SizeThresholdGB = 15.0,
        
        [Parameter(Mandatory = $false)]
        [bool]$SkipFsck = $true
    )
    
    $startTime = Get-Date
    $errors = @()
    $actions = @()
    
    try {
        Write-LogSeparator
        Write-LogInfo "Обслуживание репозитория: $RepoPath"
        
        # Проверка существования
        if (-not (Test-Path -Path $RepoPath)) {
            throw "Путь не существует: $RepoPath"
        }
        
        # Проверка, что это Git-репозиторий
        if (-not (Test-IsGitRepository -Path $RepoPath)) {
            throw "Путь не является Git-репозиторием: $RepoPath"
        }
        
        # Получение размера ДО обслуживания
        $sizeBefore = Get-GitRepositorySize -RepoPath $RepoPath
        $sizeBeforeGB = Convert-BytesToGB -Bytes $sizeBefore
        
        Write-LogInfo "Размер репозитория: $sizeBeforeGB ГБ"
        
        # Проверка порога
        $thresholdBytes = Convert-GBToBytes -GB $SizeThresholdGB
        if ($sizeBefore -lt $thresholdBytes) {
            Write-LogWarning "Размер меньше порога ($SizeThresholdGB ГБ), пропускаем обслуживание"
            
            return @{
                Success = $true
                Skipped = $true
                Path = $RepoPath
                SizeBefore = $sizeBeforeGB
                SizeAfter = $sizeBeforeGB
                SpaceSaved = 0.0
                Duration = 0
                Actions = @()
                Errors = @()
            }
        }
        
        Write-LogInfo "Начало обслуживания..."
        
        # 1. Prune remote
        $pruneResult = Invoke-GitPruneRemote -RepoPath $RepoPath
        if ($pruneResult.Success) {
            $actions += "prune_remote"
        } else {
            $errors += "prune_remote: $($pruneResult.Error)"
        }
        
        # 2. Repack
        $repackResult = Invoke-GitRepack -RepoPath $RepoPath
        if ($repackResult.Success) {
            $actions += "repack"
        } else {
            $errors += "repack: $($repackResult.Error)"
        }
        
        # 3. Prune objects
        $pruneObjResult = Invoke-GitPrune -RepoPath $RepoPath
        if ($pruneObjResult.Success) {
            $actions += "prune"
        } else {
            $errors += "prune: $($pruneObjResult.Error)"
        }
        
        # 4. Garbage collection
        $gcResult = Invoke-GitGC -RepoPath $RepoPath
        if ($gcResult.Success) {
            $actions += "gc"
        } else {
            $errors += "gc: $($gcResult.Error)"
        }
        
        # 5. Fsck (опционально)
        if (-not $SkipFsck) {
            $fsckResult = Invoke-GitFsck -RepoPath $RepoPath
            if ($fsckResult.Success) {
                $actions += "fsck"
            } else {
                $errors += "fsck: $($fsckResult.Error)"
            }
        }
        
        # Получение размера ПОСЛЕ обслуживания
        $sizeAfter = Get-GitRepositorySize -RepoPath $RepoPath
        $sizeAfterGB = Convert-BytesToGB -Bytes $sizeAfter
        $spaceSaved = $sizeBeforeGB - $sizeAfterGB
        
        $duration = ((Get-Date) - $startTime).TotalSeconds
        
        # Результаты
        Write-LogSeparator
        Write-LogSuccess "Обслуживание завершено"
        Write-LogInfo "Размер до:        $sizeBeforeGB ГБ"
        Write-LogInfo "Размер после:     $sizeAfterGB ГБ"
        Write-LogSuccess "Освобождено:      $spaceSaved ГБ"
        Write-LogInfo "Время:            $(Format-Duration -Seconds ([int]$duration))"
        
        if ($errors.Count -gt 0) {
            Write-LogWarning "Ошибки: $($errors.Count)"
            foreach ($error in $errors) {
                Write-LogWarning "  - $error"
            }
        }
        
        return @{
            Success = ($errors.Count -eq 0)
            Skipped = $false
            Path = $RepoPath
            SizeBefore = $sizeBeforeGB
            SizeAfter = $sizeAfterGB
            SpaceSaved = $spaceSaved
            Duration = [int]$duration
            Actions = $actions
            Errors = $errors
        }
    }
    catch {
        $duration = ((Get-Date) - $startTime).TotalSeconds
        $errorMessage = $_.Exception.Message
        
        Write-LogError "✗ Ошибка обслуживания репозитория: $errorMessage"
        
        return @{
            Success = $false
            Skipped = $false
            Path = $RepoPath
            SizeBefore = 0.0
            SizeAfter = 0.0
            SpaceSaved = 0.0
            Duration = [int]$duration
            Actions = $actions
            Errors = @($errorMessage)
        }
    }
}

#endregion