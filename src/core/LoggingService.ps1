<#
.SYNOPSIS
    Система логирования
.DESCRIPTION
    Логирование с цветовым кодированием и поддержкой тихого режима.
    Поддерживает уровни: INFO, SUCCESS, WARNING, ERROR
.NOTES
    Проект: 1C-Sweeper
    Версия: 1.0
    Дата создания: 2025-10-04
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

$commonPath = Join-Path -Path $scriptPath -ChildPath "Common.ps1"
if (Test-Path $commonPath) {
    . $commonPath
}

#region Глобальные переменные

# Настройки логирования
$script:LogConfig = @{
    LogFilePath = $null
    SilentMode = $false
    ConsoleOutput = $true
    FileOutput = $true
    MinLogLevel = "INFO"
}

# Уровни логирования с приоритетами
$script:LogLevels = @{
    INFO = @{ Priority = 0; Color = "White"; Symbol = "ℹ" }
    SUCCESS = @{ Priority = 1; Color = "Green"; Symbol = "✓" }
    WARNING = @{ Priority = 2; Color = "Yellow"; Symbol = "⚠" }
    ERROR = @{ Priority = 3; Color = "Red"; Symbol = "✗" }
}

#endregion

#region Инициализация

<#
.SYNOPSIS
    Инициализирует систему логирования
.PARAMETER LogFilePath
    Путь к лог-файлу
.PARAMETER SilentMode
    Тихий режим (отключает вывод INFO в консоль)
.PARAMETER ConsoleOutput
    Выводить ли сообщения в консоль
.PARAMETER FileOutput
    Записывать ли сообщения в файл
.EXAMPLE
    Initialize-Logging -LogFilePath "C:\Logs\maintenance.log" -SilentMode $false
#>
function Initialize-Logging {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$LogFilePath = $null,
        
        [Parameter(Mandatory = $false)]
        [bool]$SilentMode = $false,
        
        [Parameter(Mandatory = $false)]
        [bool]$ConsoleOutput = $true,
        
        [Parameter(Mandatory = $false)]
        [bool]$FileOutput = $true
    )
    
    # Если путь не указан, создаем в папке logs рядом со скриптом
    if ([string]::IsNullOrEmpty($LogFilePath)) {
        $logsDir = Join-Path -Path (Split-Path -Parent $scriptPath) -ChildPath "logs"
        Ensure-DirectoryExists -Path $logsDir | Out-Null
        
        $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
        $LogFilePath = Join-Path -Path $logsDir -ChildPath "maintenance_$timestamp.log"
    }
    else {
        # Убеждаемся, что папка существует
        $logDir = Split-Path -Path $LogFilePath -Parent
        if (-not [string]::IsNullOrEmpty($logDir)) {
            Ensure-DirectoryExists -Path $logDir | Out-Null
        }
    }
    
    $script:LogConfig.LogFilePath = $LogFilePath
    $script:LogConfig.SilentMode = $SilentMode
    $script:LogConfig.ConsoleOutput = $ConsoleOutput
    $script:LogConfig.FileOutput = $FileOutput
    
    # Записываем заголовок лога
    $header = @"
========================================
  1C-Sweeper - Система обслуживания
  Начало сеанса: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
  Компьютер: $(Get-HostName)
  Пользователь: $env:USERNAME
========================================

"@
    
    if ($FileOutput -and -not [string]::IsNullOrEmpty($LogFilePath)) {
        try {
            Add-Content -Path $LogFilePath -Value $header -Encoding UTF8
        }
        catch {
            Write-Warning "Не удалось записать в лог-файл: $($_.Exception.Message)"
        }
    }
    
    if ($ConsoleOutput -and -not $SilentMode) {
        Write-Host $header -ForegroundColor Cyan
    }
}

<#
.SYNOPSIS
    Получает путь к текущему лог-файлу
.EXAMPLE
    Get-LogFilePath
#>
function Get-LogFilePath {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    
    return $script:LogConfig.LogFilePath
}

<#
.SYNOPSIS
    Устанавливает режим тихого логирования
.PARAMETER Enabled
    Включить тихий режим
.EXAMPLE
    Set-SilentMode -Enabled $true
#>
function Set-SilentMode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Enabled
    )
    
    $script:LogConfig.SilentMode = $Enabled
}

#endregion

#region Основные функции логирования

<#
.SYNOPSIS
    Записывает сообщение в лог
.PARAMETER Level
    Уровень логирования (INFO, SUCCESS, WARNING, ERROR)
.PARAMETER Message
    Текст сообщения
.PARAMETER NoTimestamp
    Не добавлять временную метку
.EXAMPLE
    Write-Log -Level "INFO" -Message "Начало обработки репозитория"
    Write-Log -Level "ERROR" -Message "Ошибка выполнения команды"
#>
function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("INFO", "SUCCESS", "WARNING", "ERROR")]
        [string]$Level,
        
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [switch]$NoTimestamp
    )
    
    # Проверка уровня логирования
    if (-not $script:LogLevels.ContainsKey($Level)) {
        $Level = "INFO"
    }
    
    # Формирование временной метки
    $timestamp = if ($NoTimestamp) { "" } else { Get-Date -Format "yyyy-MM-dd HH:mm:ss" }
    
    # Формирование сообщения для файла
    $fileMessage = if ($NoTimestamp) {
        "[$Level] $Message"
    } else {
        "[$timestamp] [$Level] $Message"
    }
    
    # Запись в файл
    if ($script:LogConfig.FileOutput -and -not [string]::IsNullOrEmpty($script:LogConfig.LogFilePath)) {
        try {
            Add-Content -Path $script:LogConfig.LogFilePath -Value $fileMessage -Encoding UTF8
        }
        catch {
            # Игнорируем ошибки записи в файл, чтобы не прерывать работу
        }
    }
    
    # Вывод в консоль
    if ($script:LogConfig.ConsoleOutput) {
        $shouldOutput = $true
        
        # В тихом режиме выводим только ERROR и WARNING
        if ($script:LogConfig.SilentMode) {
            $shouldOutput = ($Level -eq "ERROR" -or $Level -eq "WARNING")
        }
        
        if ($shouldOutput) {
            $levelInfo = $script:LogLevels[$Level]
            $color = $levelInfo.Color
            $symbol = $levelInfo.Symbol
            
            # Формирование сообщения для консоли
            $consoleMessage = if ($NoTimestamp) {
                "[$symbol $Level] $Message"
            } else {
                "[$timestamp] [$symbol $Level] $Message"
            }
            
            Write-Host $consoleMessage -ForegroundColor $color
        }
    }
}

<#
.SYNOPSIS
    Записывает информационное сообщение
.PARAMETER Message
    Текст сообщения
.EXAMPLE
    Write-LogInfo "Обработка репозитория C:\Dev\Project1"
#>
function Write-LogInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )
    
    Write-Log -Level "INFO" -Message $Message
}

<#
.SYNOPSIS
    Записывает сообщение об успехе
.PARAMETER Message
    Текст сообщения
.EXAMPLE
    Write-LogSuccess "Репозиторий успешно оптимизирован"
#>
function Write-LogSuccess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )
    
    Write-Log -Level "SUCCESS" -Message $Message
}

<#
.SYNOPSIS
    Записывает предупреждение
.PARAMETER Message
    Текст сообщения
.EXAMPLE
    Write-LogWarning "Размер репозитория ниже порога, пропускаем"
#>
function Write-LogWarning {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )
    
    Write-Log -Level "WARNING" -Message $Message
}

<#
.SYNOPSIS
    Записывает сообщение об ошибке
.PARAMETER Message
    Текст сообщения
.EXAMPLE
    Write-LogError "Не удалось выполнить git gc: access denied"
#>
function Write-LogError {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )
    
    Write-Log -Level "ERROR" -Message $Message
}

#endregion

#region Дополнительные функции

<#
.SYNOPSIS
    Записывает разделительную линию в лог
.PARAMETER Title
    Заголовок раздела (опционально)
.PARAMETER Width
    Ширина линии (по умолчанию: 60)
.EXAMPLE
    Write-LogSeparator -Title "Обслуживание Git-репозиториев"
#>
function Write-LogSeparator {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Title = "",
        
        [Parameter(Mandatory = $false)]
        [int]$Width = 60
    )
    
    if ([string]::IsNullOrEmpty($Title)) {
        $line = "=" * $Width
        Write-Log -Level "INFO" -Message $line -NoTimestamp
    }
    else {
        $titleLength = $Title.Length
        $padding = $Width - $titleLength - 4
        
        if ($padding -gt 0) {
            $leftPadding = [Math]::Floor($padding / 2)
            $rightPadding = $padding - $leftPadding
            
            $line = "=" * $leftPadding + "  $Title  " + "=" * $rightPadding
        }
        else {
            $line = "  $Title  "
        }
        
        Write-Log -Level "INFO" -Message "" -NoTimestamp
        Write-Log -Level "INFO" -Message $line -NoTimestamp
        Write-Log -Level "INFO" -Message "" -NoTimestamp
    }
}

<#
.SYNOPSIS
    Записывает начало операции
.PARAMETER OperationName
    Название операции
.EXAMPLE
    Write-LogOperationStart "Оптимизация репозитория"
#>
function Write-LogOperationStart {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$OperationName
    )
    
    Write-LogInfo "▶ Начало: $OperationName"
}

<#
.SYNOPSIS
    Записывает завершение операции
.PARAMETER OperationName
    Название операции
.PARAMETER Success
    Успешно ли завершена операция
.PARAMETER Duration
    Длительность в секундах (опционально)
.EXAMPLE
    Write-LogOperationEnd "Оптимизация репозитория" -Success $true -Duration 450
#>
function Write-LogOperationEnd {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$OperationName,
        
        [Parameter(Mandatory = $true)]
        [bool]$Success,
        
        [Parameter(Mandatory = $false)]
        [int]$Duration = 0
    )
    
    $durationText = if ($Duration -gt 0) {
        " ($(Format-Duration -Seconds $Duration))"
    } else {
        ""
    }
    
    if ($Success) {
        Write-LogSuccess "■ Завершено: $OperationName$durationText"
    }
    else {
        Write-LogError "■ Не удалось: $OperationName$durationText"
    }
}

<#
.SYNOPSIS
    Записывает прогресс операции
.PARAMETER Current
    Текущий элемент
.PARAMETER Total
    Всего элементов
.PARAMETER ItemName
    Название элемента
.EXAMPLE
    Write-LogProgress -Current 3 -Total 10 -ItemName "репозиториев"
#>
function Write-LogProgress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$Current,
        
        [Parameter(Mandatory = $true)]
        [int]$Total,
        
        [Parameter(Mandatory = $false)]
        [string]$ItemName = "элементов"
    )
    
    $percent = [Math]::Round(($Current / $Total) * 100, 0)
    Write-LogInfo "  Прогресс: $Current из $Total $ItemName ($percent%)"
}

<#
.SYNOPSIS
    Записывает итоговую информацию в лог
.PARAMETER Summary
    Хеш-таблица с итоговыми данными
.EXAMPLE
    Write-LogSummary @{ "Обработано" = 4; "Успешно" = 4; "Ошибок" = 0 }
#>
function Write-LogSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Summary
    )
    
    Write-LogSeparator -Title "ИТОГИ"
    
    foreach ($key in $Summary.Keys) {
        Write-LogInfo "  $key : $($Summary[$key])"
    }
    
    Write-LogSeparator
}

#endregion

# При dot-sourcing все функции автоматически доступны