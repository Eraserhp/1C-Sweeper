<#
.SYNOPSIS
    Общие утилиты
.DESCRIPTION
    Вспомогательные функции для работы с файловой системой,
    конвертации единиц измерения и других общих операций
.NOTES
    Проект: 1C-Sweeper
    Версия: 1.0
    Дата создания: 2025-10-04
#>

#Requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region Работа с размерами

<#
.SYNOPSIS
    Получает размер директории в байтах
.PARAMETER Path
    Путь к директории
.PARAMETER Recurse
    Включать подпапки (по умолчанию: true)
.EXAMPLE
    Get-DirectorySize -Path "C:\Dev\Project1"
#>
function Get-DirectorySize {
    [CmdletBinding()]
    [OutputType([long])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -Path $_ -PathType Container })]
        [string]$Path,
        
        [Parameter(Mandatory = $false)]
        [bool]$Recurse = $true
    )
    
    try {
        $size = 0
        
        if ($Recurse) {
            $items = Get-ChildItem -Path $Path -Recurse -File -Force -ErrorAction SilentlyContinue
        } else {
            $items = Get-ChildItem -Path $Path -File -Force -ErrorAction SilentlyContinue
        }
        
        foreach ($item in $items) {
            $size += $item.Length
        }
        
        return $size
    }
    catch {
        Write-Warning "Ошибка при получении размера директории '$Path': $($_.Exception.Message)"
        return 0
    }
}

<#
.SYNOPSIS
    Получает размер файла в байтах
.PARAMETER Path
    Путь к файлу
.EXAMPLE
    Get-FileSize -Path "C:\Bases\Dev\1Cv8.1CD"
#>
function Get-FileSize {
    [CmdletBinding()]
    [OutputType([long])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -Path $_ -PathType Leaf })]
        [string]$Path
    )
    
    try {
        $file = Get-Item -Path $Path -Force
        return $file.Length
    }
    catch {
        Write-Warning "Ошибка при получении размера файла '$Path': $($_.Exception.Message)"
        return 0
    }
}

<#
.SYNOPSIS
    Конвертирует байты в гигабайты
.PARAMETER Bytes
    Количество байт
.PARAMETER Precision
    Количество знаков после запятой (по умолчанию: 2)
.EXAMPLE
    Convert-BytesToGB -Bytes 1073741824
    Вернет: 1.00
#>
function Convert-BytesToGB {
    [CmdletBinding()]
    [OutputType([double])]
    param(
        [Parameter(Mandatory = $true)]
        [long]$Bytes,
        
        [Parameter(Mandatory = $false)]
        [int]$Precision = 2
    )
    
    $gb = $Bytes / 1GB
    return [Math]::Round($gb, $Precision)
}

<#
.SYNOPSIS
    Конвертирует гигабайты в байты
.PARAMETER GB
    Количество гигабайт
.EXAMPLE
    Convert-GBToBytes -GB 15
#>
function Convert-GBToBytes {
    [CmdletBinding()]
    [OutputType([long])]
    param(
        [Parameter(Mandatory = $true)]
        [double]$GB
    )
    
    return [long]($GB * 1GB)
}

#endregion

#region Работа с файловой системой

<#
.SYNOPSIS
    Проверяет, доступен ли путь для записи
.PARAMETER Path
    Путь к директории или файлу
.EXAMPLE
    Test-PathWritable -Path "C:\MaintenanceReports"
#>
function Test-PathWritable {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    
    try {
        # Если путь не существует, проверяем родительскую папку
        if (-not (Test-Path -Path $Path)) {
            $parentPath = Split-Path -Path $Path -Parent
            if ([string]::IsNullOrEmpty($parentPath)) {
                return $false
            }
            $Path = $parentPath
        }
        
        # Пробуем создать временный файл
        $testFile = Join-Path -Path $Path -ChildPath "write_test_$(Get-Random).tmp"
        [System.IO.File]::WriteAllText($testFile, "test")
        Remove-Item -Path $testFile -Force
        return $true
    }
    catch {
        return $false
    }
}

<#
.SYNOPSIS
    Проверяет, заблокирован ли файл другим процессом
.PARAMETER Path
    Путь к файлу
.EXAMPLE
    Test-FileInUse -Path "C:\Bases\Dev\1Cv8.1CD"
#>
function Test-FileInUse {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -Path $_ -PathType Leaf })]
        [string]$Path
    )
    
    try {
        $file = [System.IO.File]::Open(
            $Path,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::ReadWrite,
            [System.IO.FileShare]::None
        )
        
        if ($file) {
            $file.Close()
            $file.Dispose()
        }
        
        return $false
    }
    catch {
        return $true
    }
}

<#
.SYNOPSIS
    Безопасно удаляет директорию с содержимым
.PARAMETER Path
    Путь к директории
.PARAMETER Force
    Принудительное удаление (по умолчанию: true)
.EXAMPLE
    Remove-DirectorySafely -Path "C:\Temp\Cache"
#>
function Remove-DirectorySafely {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        
        [Parameter(Mandatory = $false)]
        [bool]$Force = $true
    )
    
    try {
        if (Test-Path -Path $Path) {
            Remove-Item -Path $Path -Recurse -Force:$Force -ErrorAction Stop
            return $true
        }
        return $true
    }
    catch {
        Write-Warning "Не удалось удалить директорию '$Path': $($_.Exception.Message)"
        return $false
    }
}

<#
.SYNOPSIS
    Создает директорию, если она не существует
.PARAMETER Path
    Путь к директории
.EXAMPLE
    Ensure-DirectoryExists -Path "C:\MaintenanceReports"
#>
function Ensure-DirectoryExists {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    
    try {
        if (-not (Test-Path -Path $Path)) {
            New-Item -Path $Path -ItemType Directory -Force | Out-Null
        }
        return $true
    }
    catch {
        Write-Warning "Не удалось создать директорию '$Path': $($_.Exception.Message)"
        return $false
    }
}

#endregion

#region Работа со строками

<#
.SYNOPSIS
    Нормализует путь (разрешает относительные пути, убирает лишние слеши)
.PARAMETER Path
    Путь для нормализации
.EXAMPLE
    Get-NormalizedPath -Path "C:\Dev\..\Projects\Repo1"
#>
function Get-NormalizedPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Path
    )
    
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ""
    }
    
    try {
        # Разрешаем относительные пути
        $resolved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
        return $resolved
    }
    catch {
        return $Path
    }
}

<#
.SYNOPSIS
    Создает безопасное имя файла (убирает недопустимые символы)
.PARAMETER FileName
    Имя файла
.PARAMETER Replacement
    Символ замены (по умолчанию: "_")
.EXAMPLE
    Get-SafeFileName -FileName "Report: 2025-10-04"
#>
function Get-SafeFileName {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FileName,
        
        [Parameter(Mandatory = $false)]
        [string]$Replacement = "_"
    )
    
    $invalidChars = [System.IO.Path]::GetInvalidFileNameChars()
    $pattern = "[$([regex]::Escape([string]$invalidChars))]"
    
    return $FileName -replace $pattern, $Replacement
}

#endregion

#region Вспомогательные функции

<#
.SYNOPSIS
    Выполняет скриптблок с повторными попытками при ошибке
.PARAMETER ScriptBlock
    Скриптблок для выполнения
.PARAMETER MaxAttempts
    Максимальное количество попыток (по умолчанию: 3)
.PARAMETER RetryDelay
    Задержка между попытками в секундах (по умолчанию: 2)
.EXAMPLE
    Invoke-WithRetry -ScriptBlock { git gc } -MaxAttempts 3
#>
function Invoke-WithRetry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,
        
        [Parameter(Mandatory = $false)]
        [int]$MaxAttempts = 3,
        
        [Parameter(Mandatory = $false)]
        [int]$RetryDelay = 2
    )
    
    $attempt = 1
    $lastError = $null
    
    while ($attempt -le $MaxAttempts) {
        try {
            return & $ScriptBlock
        }
        catch {
            $lastError = $_
            
            if ($attempt -lt $MaxAttempts) {
                Write-Verbose "Попытка $attempt из $MaxAttempts не удалась. Повтор через $RetryDelay сек..."
                Start-Sleep -Seconds $RetryDelay
                $attempt++
            }
            else {
                throw $lastError
            }
        }
    }
}

<#
.SYNOPSIS
    Получает timestamp в формате ISO 8601
.EXAMPLE
    Get-Timestamp
    Вернет: "2025-10-04T20:15:30Z"
#>
function Get-Timestamp {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    
    return (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
}

<#
.SYNOPSIS
    Получает имя компьютера
.EXAMPLE
    Get-HostName
#>
function Get-HostName {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    
    return $env:COMPUTERNAME
}

<#
.SYNOPSIS
    Форматирует длительность в человекочитаемый вид
.PARAMETER Seconds
    Количество секунд
.EXAMPLE
    Format-Duration -Seconds 3665
    Вернет: "1ч 1м 5с"
#>
function Format-Duration {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [int]$Seconds
    )
    
    $hours = [Math]::Floor($Seconds / 3600)
    $minutes = [Math]::Floor(($Seconds % 3600) / 60)
    $secs = $Seconds % 60
    
    $parts = @()
    if ($hours -gt 0) { $parts += "${hours}ч" }
    if ($minutes -gt 0) { $parts += "${minutes}м" }
    if ($secs -gt 0 -or @($parts).Count -eq 0) { $parts += "${secs}с" }
    
    return $parts -join ' '
}

#endregion

# При dot-sourcing все функции автоматически доступны