#Requires -Version 5.1
<#
.SYNOPSIS
    Создание структуры проекта 1C-Sweeper
.DESCRIPTION
    Скрипт создает полную структуру каталогов и базовые файлы проекта
    системы автоматизированного обслуживания Git-репозиториев и баз 1С
.PARAMETER Path
    Путь для создания проекта (по умолчанию: текущая директория)
.EXAMPLE
    .\Initialize-ProjectStructure.ps1
    Создает проект в текущей директории
.EXAMPLE
    .\Initialize-ProjectStructure.ps1 -Path "C:\Projects"
    Создает проект в указанной директории
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$Path = (Get-Location).Path
)

# Установка кодировки консоли для корректного отображения кириллицы
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# Константы
$ProjectName = "1C-Sweeper"
$ProjectRoot = Join-Path -Path $Path -ChildPath $ProjectName

# Цвета для вывода
$ColorInfo = "Cyan"
$ColorSuccess = "Green"
$ColorWarning = "Yellow"
$ColorError = "Red"

#region Функции

function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

function New-ProjectDirectory {
    param(
        [string]$DirPath,
        [string]$Description = ""
    )
    
    if (-not (Test-Path -Path $DirPath)) {
        New-Item -Path $DirPath -ItemType Directory -Force | Out-Null
        $relativePath = $DirPath.Replace($ProjectRoot, "").TrimStart('\')
        Write-ColorOutput "  [+] $relativePath $(if($Description){" - $Description"})" $ColorSuccess
    }
}

function New-ProjectFile {
    param(
        [string]$FilePath,
        [string]$Content = "",
        [string]$Description = ""
    )
    
    if (-not (Test-Path -Path $FilePath)) {
        # ВАЖНО: Сохраняем в UTF-8 с BOM для корректной работы PowerShell
        $utf8BOM = New-Object System.Text.UTF8Encoding($true)
        [System.IO.File]::WriteAllText($FilePath, $Content, $utf8BOM)
        
        $relativePath = $FilePath.Replace($ProjectRoot, "").TrimStart('\')
        Write-ColorOutput "  [+] $relativePath $(if($Description){" - $Description"})" $ColorSuccess
    }
}

#endregion

#region Шаблоны файлов

$ReadmeContent = @"
# 1C-Sweeper 🧹

**Автоматическая "уборка" для разработчиков на 1С**

Система автоматизированного обслуживания локальных копий Git-репозиториев, EDT workspace и информационных баз 1С.

## Возможности

- ✅ Автоматическая оптимизация Git-репозиториев
- ✅ Очистка EDT workspace
- ✅ Тестирование и исправление баз 1С
- ✅ Автоматический поиск объектов обслуживания
- ✅ Параллельная обработка для ускорения
- ✅ Детальные JSON-отчеты
- ✅ Автоматический запуск по расписанию

## Быстрый старт 🚀

1. Запустите установщик:
``````powershell
.\install\Install.ps1
``````

2. Следуйте инструкциям интерактивного мастера

3. Система настроится автоматически!

## Документация

- [Руководство по установке](docs/INSTALLATION.md)
- [Настройка конфигурации](docs/CONFIGURATION.md)
- [Решение проблем](docs/TROUBLESHOOTING.md)
- [План реализации](docs/IMPLEMENTATION_PLAN.md)
- [Техническое задание](docs/TZ.md)

## Требования

- Windows 10/11 или Windows Server 2016+
- PowerShell 5.1 или выше
- Git (доступен из командной строки)
- Платформа 1С:Предприятие 8.3

## Структура проекта

``````
src/              # Исходный код
├── core/         # Базовые модули
├── services/     # Сервисы обслуживания
└── discovery/    # Автопоиск объектов

install/          # Установка и настройка
config/           # Конфигурационные файлы
tests/            # Тесты
docs/             # Документация
examples/         # Примеры конфигураций
``````

## Лицензия

MIT License

## Контакты

По вопросам и предложениям создавайте Issue в репозитории.
"@

$GitignoreContent = @"
# PowerShell
*.ps1~

# Конфигурация
config/maintenance-config.json

# Логи
*.log
logs/

# Отчеты
reports/
*.report.json

# Временные файлы
*.tmp
*.temp
~$*

# Windows
Thumbs.db
desktop.ini

# IDE
.vscode/
.idea/
*.code-workspace

# Тесты
TestResults/
"@

$LicenseContent = @"
MIT License

Copyright (c) 2025

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
"@

$ChangelogContent = @"
# История изменений

## [Unreleased]

### Планируется
- Базовая инфраструктура (ConfigManager, LoggingService)
- Git-сервис обслуживания
- EDT-сервис обслуживания
- Database-сервис обслуживания
- Система отчетов
- Параллельная обработка
- Установщик

## [0.1.0] - $(Get-Date -Format 'yyyy-MM-dd')

### Добавлено
- Начальная структура проекта
- Техническое задание
- План реализации
"@

$ConfigTemplateContent = @"
{
  "settings": {
    "git": {
      "repos": [
        "C:\\Dev\\Project1",
        "C:\\Dev\\Project2"
      ],
      "searchPaths": [
        "C:\\Dev",
        "D:\\Projects"
      ],
      "sizeThresholdGB": 15
    },
    "edt": {
      "workspaces": [
        "C:\\EDT\\workspace1"
      ],
      "searchPaths": [
        "C:\\EDT",
        "D:\\Workspaces"
      ],
      "sizeThresholdGB": 5
    },
    "database": {
      "databases": [
        "C:\\Bases\\Dev\\1Cv8.1CD"
      ],
      "searchPaths": [
        "C:\\Bases",
        "D:\\1C_Bases"
      ],
      "platformVersion": "8.3.*",
      "user": "",
      "password": "",
      "sizeThresholdGB": 3
    },
    "general": {
      "reportsPath": "C:\\MaintenanceReports",
      "silentMode": false,
      "parallelProcessing": true,
      "maxParallelTasks": 3
    }
  }
}
"@

$FileHeaderTemplate = @"
<#
.SYNOPSIS
    {SYNOPSIS}
.DESCRIPTION
    {DESCRIPTION}
.NOTES
    Проект: 1C-Sweeper
    Автор: 
    Дата создания: $(Get-Date -Format 'yyyy-MM-dd')
#>

#Requires -Version 5.1
"@

#endregion

#region Основной код

try {
    Write-ColorOutput "`n========================================" $ColorInfo
    Write-ColorOutput "  Инициализация проекта" $ColorInfo
    Write-ColorOutput "  $ProjectName" $ColorInfo
    Write-ColorOutput "========================================`n" $ColorInfo

    # Проверка существования корневой папки
    if (Test-Path -Path $ProjectRoot) {
        Write-ColorOutput "Проект уже существует: $ProjectRoot" $ColorWarning
        $response = Read-Host "Продолжить? Существующие файлы будут пропущены (Y/N)"
        if ($response -ne 'Y' -and $response -ne 'y') {
            Write-ColorOutput "Отменено пользователем." $ColorWarning
            exit 0
        }
    }

    # Создание корневой директории
    Write-ColorOutput "`n[1/5] Создание структуры каталогов..." $ColorInfo
    New-ProjectDirectory -DirPath $ProjectRoot -Description "Корневая директория проекта"

    # Создание основных директорий
    $directories = @{
        "src" = "Исходный код"
        "src\core" = "Базовые модули системы"
        "src\services" = "Сервисы обслуживания"
        "src\discovery" = "Модули автопоиска"
        "install" = "Скрипты установки"
        "config" = "Конфигурационные файлы"
        "tests" = "Тесты"
        "docs" = "Документация"
        "examples" = "Примеры конфигураций"
        "logs" = "Лог-файлы"
        "reports" = "JSON-отчеты"
    }

    foreach ($dir in $directories.GetEnumerator()) {
        $fullPath = Join-Path -Path $ProjectRoot -ChildPath $dir.Key
        New-ProjectDirectory -DirPath $fullPath -Description $dir.Value
    }

    # Создание заглушек для PowerShell файлов
    Write-ColorOutput "`n[2/5] Создание заглушек PowerShell файлов..." $ColorInfo

    # Главный скрипт
    $mainServiceContent = $FileHeaderTemplate -replace '{SYNOPSIS}', 'Главный скрипт обслуживания' `
        -replace '{DESCRIPTION}', 'Точка входа в систему автоматизированного обслуживания'
    $mainServiceContent += "`n`n# TODO: Реализовать главный оркестратор`n"
    New-ProjectFile -FilePath (Join-Path $ProjectRoot "src\MaintenanceService.ps1") -Content $mainServiceContent

    # Core модули
    $coreModules = @{
        "ConfigManager.ps1" = @("Управление конфигурацией", "Загрузка и валидация JSON конфигурации")
        "LoggingService.ps1" = @("Система логирования", "Логирование с цветовым кодированием и поддержкой тихого режима")
        "ReportService.ps1" = @("Генерация отчетов", "Формирование JSON-отчетов о выполненных операциях")
        "ParallelProcessor.ps1" = @("Параллельная обработка", "Управление параллельными задачами")
        "Common.ps1" = @("Общие утилиты", "Вспомогательные функции для работы с файловой системой")
    }

    foreach ($module in $coreModules.GetEnumerator()) {
        $content = $FileHeaderTemplate -replace '{SYNOPSIS}', $module.Value[0] -replace '{DESCRIPTION}', $module.Value[1]
        $content += "`n`n# TODO: Реализовать $($module.Value[0])`n"
        New-ProjectFile -FilePath (Join-Path $ProjectRoot "src\core\$($module.Key)") -Content $content
    }

    # Service модули
    $serviceModules = @{
        "GitService.ps1" = @("Обслуживание Git-репозиториев", "Оптимизация и очистка Git-репозиториев")
        "EdtService.ps1" = @("Обслуживание EDT workspace", "Очистка кэшей и временных файлов EDT")
        "DatabaseService.ps1" = @("Обслуживание баз 1С", "Тестирование и исправление информационных баз 1С")
    }

    foreach ($module in $serviceModules.GetEnumerator()) {
        $content = $FileHeaderTemplate -replace '{SYNOPSIS}', $module.Value[0] -replace '{DESCRIPTION}', $module.Value[1]
        $content += "`n`n# TODO: Реализовать $($module.Value[0])`n"
        New-ProjectFile -FilePath (Join-Path $ProjectRoot "src\services\$($module.Key)") -Content $content
    }

    # Discovery модули
    $discoveryModules = @{
        "GitDiscovery.ps1" = @("Поиск Git-репозиториев", "Автоматический поиск Git-репозиториев")
        "EdtDiscovery.ps1" = @("Поиск EDT workspace", "Автоматический поиск EDT workspace")
        "DatabaseDiscovery.ps1" = @("Поиск баз 1С", "Автоматический поиск информационных баз 1С")
        "PlatformDiscovery.ps1" = @("Поиск платформы 1С", "Поиск установленной платформы 1С по маске версии")
    }

    foreach ($module in $discoveryModules.GetEnumerator()) {
        $content = $FileHeaderTemplate -replace '{SYNOPSIS}', $module.Value[0] -replace '{DESCRIPTION}', $module.Value[1]
        $content += "`n`n# TODO: Реализовать $($module.Value[0])`n"
        New-ProjectFile -FilePath (Join-Path $ProjectRoot "src\discovery\$($module.Key)") -Content $content
    }

    # Install скрипты
    $installScripts = @{
        "Install.ps1" = @("Интерактивный установщик", "Автоматическая установка и настройка системы")
        "Uninstall.ps1" = @("Деинсталлятор", "Удаление системы")
        "Update.ps1" = @("Обновление системы", "Обновление до новой версии")
    }

    foreach ($script in $installScripts.GetEnumerator()) {
        $content = $FileHeaderTemplate -replace '{SYNOPSIS}', $script.Value[0] -replace '{DESCRIPTION}', $script.Value[1]
        $content += "`n`n# TODO: Реализовать $($script.Value[0])`n"
        New-ProjectFile -FilePath (Join-Path $ProjectRoot "install\$($script.Key)") -Content $content
    }

    # Test скрипты
    $testScripts = @(
        "Test-GitService.ps1",
        "Test-EdtService.ps1",
        "Test-DatabaseService.ps1",
        "Test-Integration.ps1"
    )

    foreach ($test in $testScripts) {
        $content = $FileHeaderTemplate -replace '{SYNOPSIS}', "Тесты для $test" -replace '{DESCRIPTION}', "Unit-тесты"
        $content += "`n`n# TODO: Реализовать тесты`n"
        New-ProjectFile -FilePath (Join-Path $ProjectRoot "tests\$test") -Content $content
    }

    # Создание файлов конфигурации
    Write-ColorOutput "`n[3/5] Создание конфигурационных файлов..." $ColorInfo
    New-ProjectFile -FilePath (Join-Path $ProjectRoot "config\maintenance-config.template.json") -Content $ConfigTemplateContent
    
    $schemaContent = @"
{
  "`$schema": "http://json-schema.org/draft-07/schema#",
  "title": "Maintenance Configuration Schema",
  "type": "object",
  "required": ["settings"],
  "properties": {
    "settings": {
      "type": "object"
    }
  }
}
"@
    New-ProjectFile -FilePath (Join-Path $ProjectRoot "config\maintenance-config.schema.json") -Content $schemaContent

    # Создание примеров конфигураций
    Write-ColorOutput "`n[4/5] Создание примеров конфигураций..." $ColorInfo
    
    $minimalConfig = @"
{
  "settings": {
    "git": {
      "searchPaths": ["C:\\Dev"],
      "sizeThresholdGB": 15
    },
    "general": {
      "reportsPath": "C:\\MaintenanceReports",
      "silentMode": false
    }
  }
}
"@
    New-ProjectFile -FilePath (Join-Path $ProjectRoot "examples\config-minimal.json") -Content $minimalConfig
    New-ProjectFile -FilePath (Join-Path $ProjectRoot "examples\config-full.json") -Content $ConfigTemplateContent
    New-ProjectFile -FilePath (Join-Path $ProjectRoot "examples\config-enterprise.json") -Content $ConfigTemplateContent

    # Создание документации
    Write-ColorOutput "`n[5/5] Создание базовых файлов документации..." $ColorInfo
    
    New-ProjectFile -FilePath (Join-Path $ProjectRoot "README.md") -Content $ReadmeContent
    New-ProjectFile -FilePath (Join-Path $ProjectRoot ".gitignore") -Content $GitignoreContent
    New-ProjectFile -FilePath (Join-Path $ProjectRoot "LICENSE") -Content $LicenseContent
    New-ProjectFile -FilePath (Join-Path $ProjectRoot "docs\CHANGELOG.md") -Content $ChangelogContent
    
    # Заглушки для остальной документации
    New-ProjectFile -FilePath (Join-Path $ProjectRoot "docs\INSTALLATION.md") -Content "# Руководство по установке`n`n(В разработке)"
    New-ProjectFile -FilePath (Join-Path $ProjectRoot "docs\CONFIGURATION.md") -Content "# Настройка конфигурации`n`n(В разработке)"
    New-ProjectFile -FilePath (Join-Path $ProjectRoot "docs\TROUBLESHOOTING.md") -Content "# Решение проблем`n`n(В разработке)"

    # Завершение
    Write-ColorOutput "`n========================================" $ColorSuccess
    Write-ColorOutput "✓ Структура проекта успешно создана!" $ColorSuccess
    Write-ColorOutput "========================================`n" $ColorSuccess

    Write-ColorOutput "Расположение проекта:" $ColorInfo
    Write-ColorOutput "  $ProjectRoot`n" $ColorInfo

    Write-ColorOutput "Следующие шаги:" $ColorInfo
    Write-ColorOutput "  1. Перейдите в папку проекта:" $ColorInfo
    Write-ColorOutput "     cd `"$ProjectRoot`"`n" "White"
    Write-ColorOutput "  2. Сохраните ТЗ в:" $ColorInfo
    Write-ColorOutput "     docs\TZ.md`n" "White"
    Write-ColorOutput "  3. Сохраните план реализации в:" $ColorInfo
    Write-ColorOutput "     docs\IMPLEMENTATION_PLAN.md`n" "White"
    Write-ColorOutput "  4. Начните разработку с Этапа 1!" $ColorInfo

} catch {
    Write-ColorOutput "`n✗ Ошибка при создании проекта:" $ColorError
    Write-ColorOutput $_.Exception.Message $ColorError
    exit 1
}

#endregion