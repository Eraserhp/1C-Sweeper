<#
.SYNOPSIS
    Исправление запятых в return в DatabaseDiscovery.ps1
.DESCRIPTION
    Убирает унарный оператор запятой из return statements
.NOTES
    Проект: 1C-Sweeper
    Дата: 2025-10-06
#>

#Requires -Version 5.1

param(
    [Parameter(Mandatory = $false)]
    [string]$ProjectRoot = "D:\OneDrive\Projects\1C-Sweeper"
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "`nИсправление запятых в return...`n" -ForegroundColor Yellow

$filePath = Join-Path -Path $ProjectRoot -ChildPath "src\discovery\DatabaseDiscovery.ps1"

if (-not (Test-Path $filePath)) {
    Write-Host "✗ Файл не найден: $filePath" -ForegroundColor Red
    exit 1
}

# Создание резервной копии
$backupPath = "$filePath.backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
Copy-Item -Path $filePath -Destination $backupPath
Write-Host "✓ Резервная копия: $backupPath`n" -ForegroundColor Green

try {
    $content = Get-Content -Path $filePath -Raw -Encoding UTF8
    
    # Список замен (все return с запятой)
    $replacements = @(
        @{
            Old = '        return ,$databases'
            New = '        return $databases'
            Description = 'Find-Databases'
        },
        @{
            Old = '    return ,$uniqueDatabases'
            New = '    return $uniqueDatabases'
            Description = 'Find-DatabasesInPaths'
        },
        @{
            Old = '        return ,$validDatabases'
            New = '        return $validDatabases'
            Description = 'Get-AllDatabases'
        },
        @{
            Old = '        return ,$filtered'
            New = '        return $filtered'
            Description = 'Get-FilteredDatabases'
        }
    )
    
    $changedCount = 0
    
    foreach ($replacement in $replacements) {
        if ($content.Contains($replacement.Old)) {
            $content = $content.Replace($replacement.Old, $replacement.New)
            Write-Host "  ✓ Исправлено: $($replacement.Description)" -ForegroundColor Green
            $changedCount++
        }
        else {
            Write-Host "  ⊖ Не найдено: $($replacement.Description)" -ForegroundColor Gray
        }
    }
    
    # Сохраняем с UTF-8 BOM
    [System.IO.File]::WriteAllText($filePath, $content, [System.Text.Encoding]::UTF8)
    
    Write-Host "`n✓ Всего исправлений: $changedCount" -ForegroundColor Green
    Write-Host "✓ Файл обновлен: $filePath`n" -ForegroundColor Green
    
    Write-Host "СЛЕДУЮЩИЙ ШАГ: Запустите тесты" -ForegroundColor Cyan
    Write-Host ".\tests\Test-DatabaseService.ps1`n" -ForegroundColor White
}
catch {
    Write-Host "`n✗ ОШИБКА: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Восстановите из резервной копии: $backupPath`n" -ForegroundColor Yellow
    exit 1
}