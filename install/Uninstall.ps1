<#
.SYNOPSIS
    Деинсталлятор 1C-Sweeper
.DESCRIPTION
    Удаление системы автоматизированного обслуживания
.NOTES
    Проект: 1C-Sweeper
    Версия: 1.0
    Дата создания: 2025-10-06
#>

#Requires -Version 5.1
#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$Force,
    
    [Parameter(Mandatory = $false)]
    [string]$InstallPath = "C:\1C-Sweeper"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Настройка кодировки
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

#region Константы

$TASK_NAME = "1C-Sweeper-Maintenance"

#endregion

#region Вспомогательные функции

function Write-Banner {
    Clear-Host
    Write-Host @"

╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║                      1C-SWEEPER                           ║
║                                                           ║
║                    ДЕИНСТАЛЛЯТОР                          ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan
}

function Write-Step {
    param([string]$Text)
    Write-Host "`n[$Text]" -ForegroundColor Yellow
    Write-Host ("=" * 60) -ForegroundColor Yellow
}

function Write-StatusOK {
    param([string]$Text)
    Write-Host "  ✓ $Text" -ForegroundColor Green
}

function Write-StatusFail {
    param([string]$Text)
    Write-Host "  ✗ $Text" -ForegroundColor Red
}

function Write-StatusWarn {
    param([string]$Text)
    Write-Host "  ⚠ $Text" -ForegroundColor Yellow
}

function Read-YesNo {
    param(
        [string]$Prompt,
        [bool]$Default = $false
    )
    
    $defaultChar = if ($Default) { "Y" } else { "N" }
    $response = Read-Host "$Prompt [Y/N] (по умолчанию: $defaultChar)"
    
    if ([string]::IsNullOrWhiteSpace($response)) {
        return $Default
    }
    
    return ($response -eq 'Y' -or $response -eq 'y')
}

#endregion

#region Функции удаления

function Remove-ScheduledTaskIfExists {
    Write-Step "Удаление задачи планировщика"
    
    try {
        $task = Get-ScheduledTask -TaskName $TASK_NAME -ErrorAction SilentlyContinue
        
        if ($task) {
            Unregister-ScheduledTask -TaskName $TASK_NAME -Confirm:$false
            Write-StatusOK "Задача '$TASK_NAME' удалена"
            return $true
        } else {
            Write-StatusWarn "Задача '$TASK_NAME' не найдена"
            return $true
        }
    }
    catch {
        Write-StatusFail "Ошибка удаления задачи: $($_.Exception.Message)"
        return $false
    }
}

function Remove-InstallationFiles {
    param([string]$Path)
    
    Write-Step "Удаление файлов"
    
    if (-not (Test-Path $Path)) {
        Write-StatusWarn "Папка установки не найдена: $Path"
        return $true
    }
    
    try {
        Write-Host "  Удаление: $Path" -ForegroundColor White
        
        # Показываем содержимое
        $size = 0
        Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
            $size += $_.Length
        }
        
        $sizeGB = [Math]::Round($size / 1GB, 2)
        Write-Host "  Размер: $sizeGB ГБ" -ForegroundColor Gray
        
        Remove-Item -Path $Path -Recurse -Force -ErrorAction Stop
        Write-StatusOK "Папка удалена"
        return $true
    }
    catch {
        Write-StatusFail "Ошибка удаления файлов: $($_.Exception.Message)"
        return $false
    }
}

function Backup-Reports {
    param([string]$InstallPath)
    
    $reportsPath = Join-Path -Path $InstallPath -ChildPath "reports"
    
    if (-not (Test-Path $reportsPath)) {
        return $null
    }
    
    $reports = @(Get-ChildItem -Path $reportsPath -Filter "*.json" -File -ErrorAction SilentlyContinue)
    
    if (@($reports).Count -eq 0) {
        return $null
    }
    
    Write-Host ""
    Write-Host "  Найдено отчетов: $(@($reports).Count)" -ForegroundColor Cyan
    
    if (Read-YesNo "  Создать резервную копию отчетов?" $true) {
        $backupPath = Join-Path -Path $env:USERPROFILE -ChildPath "Desktop\1C-Sweeper-Reports-Backup"
        
        try {
            if (-not (Test-Path $backupPath)) {
                New-Item -Path $backupPath -ItemType Directory -Force | Out-Null
            }
            
            Copy-Item -Path "$reportsPath\*" -Destination $backupPath -Force
            Write-StatusOK "Отчеты скопированы в: $backupPath"
            return $backupPath
        }
        catch {
            Write-StatusWarn "Не удалось создать backup: $($_.Exception.Message)"
            return $null
        }
    }
    
    return $null
}

#endregion

#region Основной процесс

function Start-Uninstall {
    Write-Banner
    
    Write-Host "Деинсталляция 1C-Sweeper" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Будут выполнены следующие действия:" -ForegroundColor White
    Write-Host "  • Удаление задачи из планировщика Windows" -ForegroundColor White
    Write-Host "  • Удаление установленных файлов" -ForegroundColor White
    Write-Host "  • Опционально: резервная копия отчетов" -ForegroundColor White
    Write-Host ""
    Write-Host "Папка установки: $InstallPath" -ForegroundColor Gray
    Write-Host ""
    
    if ($Force) {
        Write-Host "РЕЖИМ FORCE: деинсталляция без подтверждений" -ForegroundColor Red
        Write-Host ""
    } else {
        if (-not (Read-YesNo "Продолжить деинсталляцию?" $false)) {
            Write-Host "`nДеинсталляция отменена" -ForegroundColor Yellow
            return
        }
    }
    
    Write-Host ""
    
    # 1. Резервная копия отчетов
    $backupPath = $null
    if (-not $Force) {
        $backupPath = Backup-Reports -InstallPath $InstallPath
    }
    
    # 2. Удаление задачи планировщика
    $taskRemoved = Remove-ScheduledTaskIfExists
    
    # 3. Удаление файлов
    $filesRemoved = Remove-InstallationFiles -Path $InstallPath
    
    # Итоги
    Write-Step "Деинсталляция завершена"
    
    Write-Host ""
    
    if ($taskRemoved -and $filesRemoved) {
        Write-Host "╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Green
        Write-Host "║                                                           ║" -ForegroundColor Green
        Write-Host "║          ✓ ДЕИНСТАЛЛЯЦИЯ ЗАВЕРШЕНА УСПЕШНО!               ║" -ForegroundColor Green
        Write-Host "║                                                           ║" -ForegroundColor Green
        Write-Host "╚═══════════════════════════════════════════════════════════╝" -ForegroundColor Green
        Write-Host ""
        
        Write-Host "1C-Sweeper полностью удален из системы" -ForegroundColor White
        Write-Host ""
        
        if ($backupPath) {
            Write-Host "Резервная копия отчетов сохранена:" -ForegroundColor Cyan
            Write-Host "  $backupPath" -ForegroundColor White
            Write-Host ""
        }
        
        Write-Host "Спасибо за использование 1C-Sweeper!" -ForegroundColor Gray
        Write-Host ""
    } else {
        Write-Host "╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
        Write-Host "║                                                           ║" -ForegroundColor Yellow
        Write-Host "║       ⚠ ДЕИНСТАЛЛЯЦИЯ ЗАВЕРШЕНА С ПРЕДУПРЕЖДЕНИЯМИ        ║" -ForegroundColor Yellow
        Write-Host "║                                                           ║" -ForegroundColor Yellow
        Write-Host "╚═══════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
        Write-Host ""
        
        if (-not $taskRemoved) {
            Write-Host "  ⚠ Задача планировщика не удалена (возможно, не существовала)" -ForegroundColor Yellow
        }
        
        if (-not $filesRemoved) {
            Write-Host "  ⚠ Не все файлы удалены" -ForegroundColor Yellow
            Write-Host "    Вы можете удалить вручную: $InstallPath" -ForegroundColor Gray
        }
        
        Write-Host ""
    }
}

#endregion

# Запуск деинсталляции
try {
    Start-Uninstall
}
catch {
    Write-Host "`n✗ КРИТИЧЕСКАЯ ОШИБКА:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Gray
    exit 1
}