<#
.SYNOPSIS
    Обслуживание баз 1С
.DESCRIPTION
    Тестирование и исправление информационных баз 1С
    через штатную процедуру платформы
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
$discoveryPath = Join-Path -Path (Split-Path -Parent $scriptPath) -ChildPath "discovery"

. (Join-Path -Path $corePath -ChildPath "Common.ps1")
. (Join-Path -Path $corePath -ChildPath "LoggingService.ps1")
. (Join-Path -Path $discoveryPath -ChildPath "PlatformDiscovery.ps1")

#region Проверка базы данных

<#
.SYNOPSIS
    Проверяет, является ли файл базой данных 1С
.PARAMETER Path
    Путь к файлу
.EXAMPLE
    Test-Is1CDatabase -Path "C:\Bases\Dev\1Cv8.1CD"
#>
function Test-Is1CDatabase {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    
    try {
        if (-not (Test-Path -Path $Path -PathType Leaf)) {
            return $false
        }
        
        # Проверяем расширение
        $extension = [System.IO.Path]::GetExtension($Path)
        
        return ($extension -eq ".1CD")
    }
    catch {
        Write-LogWarning "Ошибка проверки базы '$Path': $($_.Exception.Message)"
        return $false
    }
}

<#
.SYNOPSIS
    Получает размер базы данных в байтах
.PARAMETER DbPath
    Путь к базе данных
.EXAMPLE
    Get-DatabaseSize -DbPath "C:\Bases\Dev\1Cv8.1CD"
#>
function Get-DatabaseSize {
    [CmdletBinding()]
    [OutputType([long])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Is1CDatabase -Path $_ })]
        [string]$DbPath
    )
    
    try {
        return Get-FileSize -Path $DbPath
    }
    catch {
        Write-LogWarning "Ошибка получения размера базы '$DbPath': $($_.Exception.Message)"
        return 0
    }
}

<#
.SYNOPSIS
    Проверяет, доступна ли база данных (не открыта ли в 1С)
.PARAMETER DbPath
    Путь к базе данных
.EXAMPLE
    Test-DatabaseAvailable -DbPath "C:\Bases\Dev\1Cv8.1CD"
#>
function Test-DatabaseAvailable {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DbPath
    )
    
    try {
        # Проверяем, заблокирован ли файл базы
        $isLocked = Test-FileInUse -Path $DbPath
        
        if ($isLocked) {
            Write-LogWarning "База данных используется другим процессом: $DbPath"
            return $false
        }
        
        # Дополнительно проверяем файл блокировки .1CL
        $lockFile = [System.IO.Path]::ChangeExtension($DbPath, ".1CL")
        
        if (Test-Path -Path $lockFile) {
            Write-LogWarning "Обнаружен файл блокировки: $lockFile"
            return $false
        }
        
        return $true
    }
    catch {
        Write-LogWarning "Ошибка проверки доступности базы '$DbPath': $($_.Exception.Message)"
        return $false
    }
}

#endregion

#region Обслуживание базы

<#
.SYNOPSIS
    Запускает тестирование и исправление базы данных 1С
.PARAMETER DbPath
    Путь к базе данных
.PARAMETER PlatformPath
    Путь к 1cv8.exe
.PARAMETER User
    Имя пользователя (опционально)
.PARAMETER Password
    Пароль (опционально)
.PARAMETER TimeoutSeconds
    Таймаут выполнения (по умолчанию: 3600 сек = 1 час)
.EXAMPLE
    Start-TestAndRepair -DbPath "C:\Bases\Dev\1Cv8.1CD" -PlatformPath "C:\Program Files\1cv8\8.3.27.1486\bin\1cv8.exe"
#>
function Start-TestAndRepair {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DbPath,
        
        [Parameter(Mandatory = $true)]
        [string]$PlatformPath,
        
        [Parameter(Mandatory = $false)]
        [string]$User = "",
        
        [Parameter(Mandatory = $false)]
        [string]$Password = "",
        
        [Parameter(Mandatory = $false)]
        [int]$TimeoutSeconds = 3600
    )
    
    $startTime = Get-Date
    
    try {
        Write-LogInfo "    Запуск тестирования и исправления..."
        
        # Формируем аргументы командной строки
        $arguments = @(
            "ENTERPRISE"
            "/F`"$DbPath`""
        )
        
        # Добавляем учетные данные, если указаны
        if (-not [string]::IsNullOrWhiteSpace($User)) {
            $arguments += "/N`"$User`""
        }
        
        if (-not [string]::IsNullOrWhiteSpace($Password)) {
            $arguments += "/P`"$Password`""
        }
        
        # Режим тестирования и исправления
        $arguments += "/TestAndRepair"
        
        Write-LogInfo "    Команда: 1cv8.exe $($arguments -join ' ')"
        
        # Запускаем процесс
        $processInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processInfo.FileName = $PlatformPath
        $processInfo.Arguments = $arguments -join ' '
        $processInfo.UseShellExecute = $false
        $processInfo.RedirectStandardOutput = $true
        $processInfo.RedirectStandardError = $true
        $processInfo.CreateNoWindow = $true
        $processInfo.WorkingDirectory = Split-Path -Path $DbPath -Parent
        
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $processInfo
        
        # Запускаем
        $started = $process.Start()
        
        if (-not $started) {
            throw "Не удалось запустить процесс 1cv8.exe"
        }
        
        # Ждем завершения
        $completed = $process.WaitForExit($TimeoutSeconds * 1000)
        
        $duration = [int]((Get-Date) - $startTime).TotalSeconds
        
        if (-not $completed) {
            # Таймаут
            try {
                $process.Kill()
            }
            catch {
                # Игнорируем ошибки при kill
            }
            
            Write-LogWarning "    ⚠ Таймаут выполнения ($TimeoutSeconds сек)"
            
            return @{
                Success = $false
                ExitCode = -1
                Duration = $duration
                Error = "Превышен таймаут выполнения"
                Output = ""
            }
        }
        
        # Получаем результаты
        $exitCode = $process.ExitCode
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        
        $output = @()
        if ($stdout) { $output += $stdout }
        if ($stderr) { $output += $stderr }
        
        $outputText = $output -join "`n"
        
        # Код 0 означает успех
        if ($exitCode -eq 0) {
            Write-LogInfo "    ✓ Тестирование и исправление завершено ($(Format-Duration -Seconds $duration))"
            
            return @{
                Success = $true
                ExitCode = $exitCode
                Duration = $duration
                Error = $null
                Output = $outputText
            }
        }
        else {
            $errorMsg = "Код возврата: $exitCode"
            if ($outputText) {
                $errorMsg += "`n$outputText"
            }
            
            Write-LogWarning "    ⚠ Завершено с ошибкой (код: $exitCode)"
            
            return @{
                Success = $false
                ExitCode = $exitCode
                Duration = $duration
                Error = $errorMsg
                Output = $outputText
            }
        }
    }
    catch {
        $duration = [int]((Get-Date) - $startTime).TotalSeconds
        $errorMsg = $_.Exception.Message
        
        Write-LogError "    ✗ Ошибка запуска: $errorMsg"
        
        return @{
            Success = $false
            ExitCode = -1
            Duration = $duration
            Error = $errorMsg
            Output = ""
        }
    }
}

<#
.SYNOPSIS
    Выполняет полное обслуживание базы данных 1С
.PARAMETER DbPath
    Путь к базе данных
.PARAMETER PlatformVersion
    Маска версии платформы (опционально)
.PARAMETER User
    Имя пользователя (опционально)
.PARAMETER Password
    Пароль в Base64 (опционально)
.PARAMETER SizeThresholdGB
    Порог размера для запуска обслуживания (в ГБ)
.EXAMPLE
    Invoke-DatabaseMaintenance -DbPath "C:\Bases\Dev\1Cv8.1CD" -SizeThresholdGB 3
#>
function Invoke-DatabaseMaintenance {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -Path $_ -PathType Leaf })]
        [string]$DbPath,
        
        [Parameter(Mandatory = $false)]
        [string]$PlatformVersion = "",
        
        [Parameter(Mandatory = $false)]
        [string]$User = "",
        
        [Parameter(Mandatory = $false)]
        [string]$Password = "",
        
        [Parameter(Mandatory = $false)]
        [double]$SizeThresholdGB = 3.0
    )
    
    $startTime = Get-Date
    $errors = @()
    $actions = @()
    
    try {
        Write-LogSeparator
        Write-LogInfo "Обслуживание базы 1С: $DbPath"
        
        # Проверка, что это база данных 1С
        if (-not (Test-Is1CDatabase -Path $DbPath)) {
            throw "Файл не является базой данных 1С (.1CD): $DbPath"
        }
        
        # Получение размера ДО обслуживания
        Write-LogInfo "Измерение размера..."
        $sizeBefore = Get-DatabaseSize -DbPath $DbPath
        $sizeBeforeGB = Convert-BytesToGB -Bytes $sizeBefore
        
        Write-LogInfo "Размер базы: $sizeBeforeGB ГБ"
        
        # Проверка порога
        if ($sizeBeforeGB -lt $SizeThresholdGB) {
            Write-LogWarning "Размер меньше порога ($SizeThresholdGB ГБ), пропускаем обслуживание"
            
            return @{
                Success = $true
                Skipped = $true
                Path = $DbPath
                SizeBefore = $sizeBeforeGB
                SizeAfter = $sizeBeforeGB
                SpaceSaved = 0.0
                Duration = 0
                Platform = $null
                Actions = @()
                Errors = @()
            }
        }
        
        # Проверка доступности базы
        Write-LogInfo "Проверка доступности базы..."
        if (-not (Test-DatabaseAvailable -DbPath $DbPath)) {
            $errorMsg = "База данных занята (открыта в 1С или заблокирована)"
            Write-LogError $errorMsg
            $errors += $errorMsg
            
            return @{
                Success = $false
                Skipped = $false
                Path = $DbPath
                SizeBefore = $sizeBeforeGB
                SizeAfter = $sizeBeforeGB
                SpaceSaved = 0.0
                Duration = 0
                Platform = $null
                Actions = @()
                Errors = @($errorMsg)
            }
        }
        
        Write-LogInfo "База доступна для обслуживания"
        
        # Поиск платформы 1С
        Write-LogInfo "Поиск платформы 1С..."
        $platformResult = Find-Platform1C -VersionMask $PlatformVersion
        
        if (-not $platformResult.Success) {
            $errorMsg = $platformResult.Error
            Write-LogError $errorMsg
            $errors += $errorMsg
            
            return @{
                Success = $false
                Skipped = $false
                Path = $DbPath
                SizeBefore = $sizeBeforeGB
                SizeAfter = $sizeBeforeGB
                SpaceSaved = 0.0
                Duration = 0
                Platform = $null
                Actions = @()
                Errors = @($errorMsg)
            }
        }
        
        $platform = $platformResult.Platform
        Write-LogInfo "Используется платформа: $($platform.Version.Original)"
        
        # Декодирование пароля (если указан в Base64)
        $decodedPassword = if (-not [string]::IsNullOrWhiteSpace($Password)) {
            ConvertFrom-Base64Password -EncodedPassword $Password
        } else {
            ""
        }
        
        # Запуск тестирования и исправления
        Write-LogInfo "Начало обслуживания..."
        
        $repairResult = Start-TestAndRepair `
            -DbPath $DbPath `
            -PlatformPath $platform.Path `
            -User $User `
            -Password $decodedPassword
        
        if ($repairResult.Success) {
            $actions += "test_and_repair"
        } else {
            $errors += "test_and_repair: $($repairResult.Error)"
        }
        
        # Получение размера ПОСЛЕ обслуживания
        $sizeAfter = Get-DatabaseSize -DbPath $DbPath
        $sizeAfterGB = Convert-BytesToGB -Bytes $sizeAfter
        $spaceSaved = $sizeBeforeGB - $sizeAfterGB
        
        $duration = [int]((Get-Date) - $startTime).TotalSeconds
        
        # Результаты
        Write-LogSeparator
        
        if ($repairResult.Success) {
            Write-LogSuccess "Обслуживание завершено"
        } else {
            Write-LogWarning "Обслуживание завершено с ошибками"
        }
        
        Write-LogInfo "Размер до:        $sizeBeforeGB ГБ"
        Write-LogInfo "Размер после:     $sizeAfterGB ГБ"
        
        if ($spaceSaved -gt 0) {
            Write-LogSuccess "Освобождено:      $spaceSaved ГБ"
        } elseif ($spaceSaved -lt 0) {
            Write-LogInfo "Изменение:        $([Math]::Abs($spaceSaved)) ГБ (увеличение)"
        } else {
            Write-LogInfo "Изменение:        0 ГБ"
        }
        
        Write-LogInfo "Время:            $(Format-Duration -Seconds $duration)"
        
        if (@($errors).Count -gt 0) {
            Write-LogWarning "Ошибки: $(@($errors).Count)"
            foreach ($error in $errors) {
                Write-LogWarning "  - $error"
            }
        }
        
        return @{
            Success = (@($errors).Count -eq 0)
            Skipped = $false
            Path = $DbPath
            SizeBefore = $sizeBeforeGB
            SizeAfter = $sizeAfterGB
            SpaceSaved = $spaceSaved
            Duration = $duration
            Platform = $platform.Version.Original
            Actions = $actions
            Errors = $errors
        }
    }
    catch {
        $duration = [int]((Get-Date) - $startTime).TotalSeconds
        $errorMessage = $_.Exception.Message
        
        Write-LogError "✗ Ошибка обслуживания базы: $errorMessage"
        
        return @{
            Success = $false
            Skipped = $false
            Path = $DbPath
            SizeBefore = 0.0
            SizeAfter = 0.0
            SpaceSaved = 0.0
            Duration = $duration
            Platform = $null
            Actions = $actions
            Errors = @($errorMessage)
        }
    }
}

#endregion

# При dot-sourcing все функции автоматически доступны