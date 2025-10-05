<#
.SYNOPSIS
    Автоматическое исправление ошибки Export-ModuleMember
.DESCRIPTION
    Удаляет вызовы Export-ModuleMember из всех .ps1 файлов проекта,
    так как этот командлет работает только в .psm1 модулях
.NOTES
    Проект: 1C-Sweeper
    Дата: 2025-10-05
#>

#Requires -Version 5.1

param(
    [Parameter(Mandatory = $false)]
    [string]$ProjectRoot = (Get-Location).Path,
    
    [Parameter(Mandatory = $false)]
    [switch]$WhatIf
)

# Настройка кодировки
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

function Write-ColorOutput {
    param([string]$Message, [string]$Color = "White")
    Write-Host $Message -ForegroundColor $Color
}

Write-ColorOutput "`n╔═══════════════════════════════════════════════════════════╗" "Cyan"
Write-ColorOutput "║  Исправление ошибки Export-ModuleMember                 ║" "Cyan"
Write-ColorOutput "╚═══════════════════════════════════════════════════════════╝`n" "Cyan"

Write-ColorOutput "Корень проекта: $ProjectRoot" "Gray"
Write-ColorOutput "Режим: $(if($WhatIf){'ТЕСТОВЫЙ (WhatIf)'}else{'РЕАЛЬНОЕ ИСПРАВЛЕНИЕ'})" "Yellow"
Write-ColorOutput ""

# Поиск всех .ps1 файлов
$srcPath = Join-Path -Path $ProjectRoot -ChildPath "src"
if (-not (Test-Path $srcPath)) {
    Write-ColorOutput "✗ Папка src не найдена: $srcPath" "Red"
    exit 1
}

Write-ColorOutput "Поиск файлов с Export-ModuleMember..." "Cyan"

$allFiles = Get-ChildItem -Path $srcPath -Filter "*.ps1" -Recurse
$filesToFix = @()

foreach ($file in $allFiles) {
    $content = Get-Content -Path $file.FullName -Raw -Encoding UTF8
    
    if ($content -match 'Export-ModuleMember') {
        $filesToFix += $file
        $relativePath = $file.FullName.Replace($ProjectRoot, "").TrimStart('\')
        Write-ColorOutput "  ⚠ Найдено: $relativePath" "Yellow"
    }
}

if ($filesToFix.Count -eq 0) {
    Write-ColorOutput "`n✓ Нет файлов требующих исправления!" "Green"
    exit 0
}

Write-ColorOutput "`nНайдено файлов для исправления: $($filesToFix.Count)" "Yellow"
Write-ColorOutput ""

# Создание резервных копий
if (-not $WhatIf) {
    $backupDir = Join-Path -Path $ProjectRoot -ChildPath "backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    New-Item -Path $backupDir -ItemType Directory -Force | Out-Null
    Write-ColorOutput "📦 Создана папка резервных копий: $backupDir" "Cyan"
    Write-ColorOutput ""
}

$fixedCount = 0
$errorCount = 0

foreach ($file in $filesToFix) {
    $relativePath = $file.FullName.Replace($ProjectRoot, "").TrimStart('\')
    Write-ColorOutput "Обработка: $relativePath" "Cyan"
    
    try {
        # Чтение содержимого
        $content = Get-Content -Path $file.FullName -Raw -Encoding UTF8
        
        # Создание резервной копии
        if (-not $WhatIf) {
            $backupPath = Join-Path -Path $backupDir -ChildPath $file.Name
            Copy-Item -Path $file.FullName -Destination $backupPath -Force
            Write-ColorOutput "  ✓ Создана резервная копия" "Gray"
        }
        
        # Подсчет строк для удаления
        $exportLines = ($content -split "`n" | Where-Object { $_ -match 'Export-ModuleMember' }).Count
        
        # Удаление блока Export-ModuleMember
        # Паттерн: 
        $pattern = '(?s)# Экспорт функций.*?Export-ModuleMember\s+-Function\s+@\([^)]*\)'
        $newContent = $content -replace $pattern, ''
        
        # Альтернативный паттерн без комментария
        $pattern2 = '(?s)Export-ModuleMember\s+-Function\s+@\([^)]*\)'
        $newContent = $newContent -replace $pattern2, ''
        
        # Удаление лишних пустых строк в конце
        $newContent = $newContent.TrimEnd() + "`n"
        
        if ($WhatIf) {
            Write-ColorOutput "  [WhatIf] Будет удалено строк: ~$exportLines" "Yellow"
            Write-ColorOutput "  [WhatIf] Изменения НЕ применены" "Yellow"
        } else {
            # Сохранение исправленного файла с UTF-8 BOM
            $utf8BOM = New-Object System.Text.UTF8Encoding($true)
            [System.IO.File]::WriteAllText($file.FullName, $newContent, $utf8BOM)
            
            Write-ColorOutput "  ✓ Удалено строк Export-ModuleMember: ~$exportLines" "Green"
            Write-ColorOutput "  ✓ Файл исправлен и сохранен" "Green"
            $fixedCount++
        }
    }
    catch {
        Write-ColorOutput "  ✗ Ошибка: $($_.Exception.Message)" "Red"
        $errorCount++
    }
    
    Write-ColorOutput ""
}

# Итоги
Write-ColorOutput "═══════════════════════════════════════════════════════════" "Cyan"
Write-ColorOutput "  ИТОГИ ИСПРАВЛЕНИЯ" "Cyan"
Write-ColorOutput "═══════════════════════════════════════════════════════════" "Cyan"

if ($WhatIf) {
    Write-ColorOutput "Режим WhatIf: изменения НЕ применены" "Yellow"
    Write-ColorOutput "Файлов для исправления: $($filesToFix.Count)" "Yellow"
} else {
    Write-ColorOutput "Исправлено файлов: $fixedCount" "Green"
    if ($errorCount -gt 0) {
        Write-ColorOutput "Ошибок при исправлении: $errorCount" "Red"
    }
    Write-ColorOutput "Резервные копии сохранены в: $backupDir" "Cyan"
}

Write-ColorOutput "═══════════════════════════════════════════════════════════" "Cyan"

if (-not $WhatIf -and $fixedCount -gt 0) {
    Write-ColorOutput "`n✓ Все файлы успешно исправлены!" "Green"
    Write-ColorOutput "Теперь можно запускать тесты.`n" "Cyan"
} elseif ($WhatIf) {
    Write-ColorOutput "`nДля применения исправлений запустите без параметра -WhatIf" "Yellow"
    Write-ColorOutput "Пример: .\Fix-ExportModuleMemberError.ps1`n" "Gray"
}

exit $(if($errorCount -gt 0){1}else{0})
