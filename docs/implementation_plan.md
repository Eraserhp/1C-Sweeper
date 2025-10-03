# План структуры реализации 1C-Sweeper 🧹

**Версия документа:** 1.0  
**Дата:** 03.10.2025  
**Статус:** Утверждено

---

## 1. АРХИТЕКТУРА РЕШЕНИЯ

### 1.1. Общая архитектура

```
┌─────────────────────────────────────────────────┐
│           Планировщик задач Windows             │
│              (автоматический запуск)            │
└────────────────────┬────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────┐
│         MaintenanceService.ps1                  │
│         (главный оркестратор)                   │
└─────┬───────────────────────────────────────────┘
      │
      ├──► ConfigManager ────► maintenance-config.json
      │
      ├──► GitService ───────► Git репозитории
      │
      ├──► EdtService ───────► EDT workspaces
      │
      ├──► DatabaseService ──► 1C базы данных
      │
      ├──► ReportService ────► JSON отчеты
      │
      ├──► LoggingService ───► Лог-файлы
      │
      └──► ParallelProcessor ─► Управление потоками
```

---

## 2. СТРУКТУРА ПРОЕКТА

```
1C-Sweeper/
│
├── src/                              # Исходный код
│   ├── MaintenanceService.ps1        # Главный скрипт (точка входа)
│   │
│   ├── core/                         # Ядро системы
│   │   ├── ConfigManager.ps1         # Управление конфигурацией
│   │   ├── LoggingService.ps1        # Система логирования
│   │   ├── ReportService.ps1         # Генерация JSON-отчетов
│   │   ├── ParallelProcessor.ps1     # Параллельная обработка
│   │   └── Common.ps1                # Общие утилиты и функции
│   │
│   ├── services/                     # Сервисы обслуживания
│   │   ├── GitService.ps1            # Обслуживание Git
│   │   ├── EdtService.ps1            # Обслуживание EDT
│   │   └── DatabaseService.ps1       # Обслуживание 1C баз
│   │
│   └── discovery/                    # Автопоиск объектов
│       ├── GitDiscovery.ps1          # Поиск Git-репозиториев
│       ├── EdtDiscovery.ps1          # Поиск EDT workspace
│       ├── DatabaseDiscovery.ps1     # Поиск 1C баз
│       └── PlatformDiscovery.ps1     # Поиск платформы 1C
│
├── install/                          # Установка и настройка
│   ├── Install.ps1                   # Интерактивный установщик
│   ├── Uninstall.ps1                 # Деинсталлятор
│   └── Update.ps1                    # Обновление системы
│
├── config/                           # Конфигурационные файлы
│   ├── maintenance-config.template.json  # Шаблон конфигурации
│   └── maintenance-config.schema.json    # JSON-схема для валидации
│
├── tests/                            # Тесты
│   ├── Test-GitService.ps1
│   ├── Test-EdtService.ps1
│   ├── Test-DatabaseService.ps1
│   └── Test-Integration.ps1
│
├── docs/                             # Документация
│   ├── README.md                     # Обзорная документация
│   ├── INSTALLATION.md               # Руководство по установке
│   ├── CONFIGURATION.md              # Описание конфигурации
│   ├── TROUBLESHOOTING.md            # Решение проблем
│   └── CHANGELOG.md                  # История изменений
│
├── examples/                         # Примеры конфигураций
│   ├── config-minimal.json           # Минимальная конфигурация
│   ├── config-full.json              # Полная конфигурация
│   └── config-enterprise.json        # Корпоративная конфигурация
│
└── LICENSE                           # Лицензия
```

---

## 3. ДЕКОМПОЗИЦИЯ МОДУЛЕЙ

### 3.1. MaintenanceService.ps1 (главный скрипт)

**Ответственность:**
- Точка входа в систему
- Разбор параметров командной строки
- Инициализация всех сервисов
- Оркестрация процесса обслуживания
- Обработка глобальных исключений

**Основные функции:**
```powershell
function Start-Maintenance {
    # Главная функция запуска обслуживания
}

function Initialize-Services {
    # Инициализация всех сервисов
}

function Process-AllObjects {
    # Обработка всех объектов (Git, EDT, 1C)
}

function Cleanup-Resources {
    # Очистка ресурсов при завершении
}
```

**Параметры командной строки:**
- `-ConfigPath` - путь к конфигурационному файлу
- `-Silent` - тихий режим
- `-DryRun` - тестовый запуск без изменений
- `-Force` - игнорировать пороги размеров
- `-Objects` - обработать только определенные типы (Git, EDT, 1C)

---

### 3.2. Core-модули

#### ConfigManager.ps1

**Ответственность:**
- Загрузка и валидация конфигурации
- Парсинг JSON
- Предоставление доступа к настройкам
- Валидация путей и параметров

**Основные функции:**
```powershell
function Get-Configuration {
    # Загрузка конфигурации из JSON
}

function Test-ConfigurationValid {
    # Валидация конфигурации
}

function Get-ConfigValue {
    param($Path)
    # Получение конкретного значения
}

function Resolve-Paths {
    # Разрешение и проверка всех путей
}
```

**Структура данных:**
```powershell
class Configuration {
    [GitSettings] $Git
    [EdtSettings] $Edt
    [DatabaseSettings] $Database
    [GeneralSettings] $General
}
```

#### LoggingService.ps1

**Ответственность:**
- Запись логов в файл
- Вывод в консоль с цветовым кодированием
- Управление уровнями логирования
- Поддержка тихого режима

**Основные функции:**
```powershell
function Write-Log {
    param($Level, $Message)
    # INFO, SUCCESS, WARNING, ERROR
}

function Initialize-Logging {
    # Инициализация логирования
}

function Get-LogPath {
    # Получение пути к лог-файлу
}

function Write-ConsoleColored {
    # Цветной вывод в консоль
}
```

**Уровни логирования:**
- `INFO` - информационные сообщения (белый)
- `SUCCESS` - успешные операции (зеленый)
- `WARNING` - предупреждения (желтый)
- `ERROR` - ошибки (красный)

#### ReportService.ps1

**Ответственность:**
- Сбор статистики выполнения
- Формирование JSON-отчетов
- Расчет освобожденного места
- Агрегация данных

**Основные функции:**
```powershell
function New-Report {
    # Создание нового отчета
}

function Add-GitResult {
    param($RepoPath, $Result)
}

function Add-EdtResult {
    param($WorkspacePath, $Result)
}

function Add-DatabaseResult {
    param($DbPath, $Result)
}

function Save-Report {
    param($ReportPath)
    # Сохранение отчета в JSON
}

function Get-ReportSummary {
    # Получение сводной информации
}
```

**Структура отчета:**
```powershell
class MaintenanceReport {
    [datetime] $Timestamp
    [int] $Duration
    [string] $Hostname
    [ReportSummary] $Summary
    [array] $GitRepositories
    [array] $EdtWorkspaces
    [array] $Databases
    [array] $Errors
}
```

#### ParallelProcessor.ps1

**Ответственность:**
- Управление параллельными задачами
- Ограничение количества потоков
- Сбор результатов
- Обработка ошибок в потоках

**Основные функции:**
```powershell
function Start-ParallelProcessing {
    param($Items, $ScriptBlock, $MaxThreads)
}

function Wait-ParallelTasks {
    # Ожидание завершения задач
}

function Get-ParallelResults {
    # Сбор результатов из всех потоков
}
```

**Реализация:**
- Использование `Start-Job` для параллелизации
- Контроль количества одновременных задач
- Управление таймаутами

#### Common.ps1

**Ответственность:**
- Общие утилиты
- Работа с файловой системой
- Конвертация единиц измерения
- Вспомогательные функции

**Основные функции:**
```powershell
function Get-DirectorySize {
    param($Path)
    # Получение размера папки в байтах
}

function Convert-BytesToGB {
    param($Bytes)
}

function Test-PathWritable {
    param($Path)
}

function Get-ProcessLockingFile {
    param($FilePath)
    # Проверка блокировки файла
}

function Invoke-WithRetry {
    param($ScriptBlock, $MaxAttempts)
}
```

---

### 3.3. Services-модули

#### GitService.ps1

**Ответственность:**
- Обслуживание Git-репозиториев
- Выполнение Git-команд
- Проверка целостности
- Сбор статистики

**Основные функции:**
```powershell
function Invoke-GitMaintenance {
    param($RepoPath)
}

function Test-IsGitRepository {
    param($Path)
}

function Get-GitRepositorySize {
    param($RepoPath)
}

function Optimize-GitRepository {
    param($RepoPath)
    # Выполнение всех команд оптимизации
}

function Test-GitIntegrity {
    param($RepoPath)
}
```

**Последовательность команд:**
1. `git remote prune origin`
2. `git repack -ad`
3. `git prune --expire=now`
4. `git gc --prune=now`
5. Опционально: `git fsck`

#### EdtService.ps1

**Ответственность:**
- Обслуживание EDT workspace
- Очистка кэшей и логов
- Удаление временных файлов
- Проверка состояния

**Основные функции:**
```powershell
function Invoke-EdtMaintenance {
    param($WorkspacePath)
}

function Test-IsEdtWorkspace {
    param($Path)
}

function Get-EdtWorkspaceSize {
    param($WorkspacePath)
}

function Clear-EdtCache {
    param($WorkspacePath)
}

function Clear-EdtLogs {
    param($WorkspacePath)
}

function Clear-EdtIndexes {
    param($WorkspacePath)
}
```

**Очищаемые папки:**
- `.metadata/.log`
- `.metadata/.plugins/*/cache`
- `.metadata/.plugins/*/indexes`
- `.metadata/.plugins/*/history`

#### DatabaseService.ps1

**Ответственность:**
- Обслуживание баз 1С
- Поиск платформы 1С
- Запуск тестирования и исправления
- Проверка доступности базы

**Основные функции:**
```powershell
function Invoke-DatabaseMaintenance {
    param($DbPath, $PlatformPath, $Credentials)
}

function Test-IsDatabaseAvailable {
    param($DbPath)
}

function Get-DatabaseSize {
    param($DbPath)
}

function Find-Platform1C {
    param($VersionMask)
    # Поиск установленной платформы
}

function Start-TestAndRepair {
    param($DbPath, $PlatformPath, $User, $Password)
}
```

**Команда запуска:**
```powershell
& "C:\Program Files\1cv8\8.3.27.1486\bin\1cv8.exe" `
    ENTERPRISE /F"$DbPath" `
    /N"$User" /P"$Password" `
    /UC"$LockCode" `
    /TestAndRepair
```

---

### 3.4. Discovery-модули

#### GitDiscovery.ps1

**Основные функции:**
```powershell
function Find-GitRepositories {
    param($SearchPaths)
    # Поиск всех Git-репозиториев
}

function Test-IsGitRepository {
    param($Path)
}

function Get-AllGitRepositories {
    param($ExplicitPaths, $SearchPaths)
    # Объединение явных путей и найденных
}
```

**Логика поиска:**
- Проверка наличия папки `.git`
- Поиск на 1 уровень вглубь
- Исключение вложенных подмодулей

#### EdtDiscovery.ps1

**Основные функции:**
```powershell
function Find-EdtWorkspaces {
    param($SearchPaths)
}

function Test-IsEdtWorkspace {
    param($Path)
}

function Get-AllEdtWorkspaces {
    param($ExplicitPaths, $SearchPaths)
}
```

**Логика поиска:**
- Проверка наличия папки `.metadata`
- Валидация структуры workspace

#### DatabaseDiscovery.ps1

**Основные функции:**
```powershell
function Find-Databases {
    param($SearchPaths)
}

function Test-IsDatabase {
    param($Path)
}

function Get-AllDatabases {
    param($ExplicitPaths, $SearchPaths)
}
```

**Логика поиска:**
- Поиск файлов с расширением `.1CD`
- Проверка валидности базы

#### PlatformDiscovery.ps1

**Основные функции:**
```powershell
function Find-Platform1C {
    param($VersionMask)
}

function Get-InstalledPlatforms {
    # Список всех установленных платформ
}

function Test-VersionMatchesMask {
    param($Version, $Mask)
}

function Get-MaxMatchingVersion {
    param($Versions, $Mask)
}
```

**Логика поиска:**
- Сканирование стандартных путей установки
- Проверка реестра Windows
- Фильтрация по маске версии
- Выбор максимальной подходящей версии

---

## 4. ПЛАН РАЗРАБОТКИ ПО ЭТАПАМ

### Этап 1: Базовая инфраструктура (1-2 дня)

**Задачи:**
- [x] Создание структуры проекта
- [ ] Реализация ConfigManager
- [ ] Реализация LoggingService
- [ ] Реализация Common утилит
- [ ] Создание шаблона конфигурации

**Результат:** Базовый каркас с загрузкой конфигурации и логированием

---

### Этап 2: Git-сервис (1-2 дня)

**Задачи:**
- [ ] Реализация GitService
- [ ] Реализация GitDiscovery
- [ ] Тестирование на реальных репозиториях
- [ ] Оптимизация последовательности команд
- [ ] Обработка ошибок

**Результат:** Полностью рабочее обслуживание Git-репозиториев

---

### Этап 3: EDT-сервис (1 день)

**Задачи:**
- [ ] Реализация EdtService
- [ ] Реализация EdtDiscovery
- [ ] Идентификация всех очищаемых папок
- [ ] Тестирование на workspace
- [ ] Проверка безопасности очистки

**Результат:** Полностью рабочее обслуживание EDT workspace

---

### Этап 4: Database-сервис (2-3 дня)

**Задачи:**
- [ ] Реализация DatabaseService
- [ ] Реализация DatabaseDiscovery
- [ ] Реализация PlatformDiscovery
- [ ] Поддержка аутентификации
- [ ] Проверка блокировок базы
- [ ] Тестирование тестирования и исправления

**Результат:** Полностью рабочее обслуживание баз 1С

---

### Этап 5: Отчетность (1 день)

**Задачи:**
- [ ] Реализация ReportService
- [ ] Формирование JSON-структуры
- [ ] Сбор статистики по всем операциям
- [ ] Расчет освобожденного места
- [ ] Форматирование отчетов

**Результат:** Детальные JSON-отчеты о выполнении

---

### Этап 6: Параллелизация (1-2 дня)

**Задачи:**
- [ ] Реализация ParallelProcessor
- [ ] Параллельная обработка Git
- [ ] Параллельная обработка EDT
- [ ] Последовательная обработка 1С
- [ ] Управление потоками
- [ ] Тестирование производительности

**Результат:** Ускорение обработки в 2-3 раза

---

### Этап 7: Главный оркестратор (1 день)

**Задачи:**
- [ ] Реализация MaintenanceService
- [ ] Интеграция всех сервисов
- [ ] Обработка параметров командной строки
- [ ] Тихий режим
- [ ] Глобальная обработка ошибок

**Результат:** Полностью рабочая система end-to-end

---

### Этап 8: Установщик (2-3 дня)

**Задачи:**
- [ ] Реализация Install.ps1
- [ ] Интерактивный сбор конфигурации
- [ ] Автопоиск объектов
- [ ] Настройка планировщика задач
- [ ] Настройка ExecutionPolicy
- [ ] Реализация Uninstall.ps1

**Результат:** Автоматизированная установка и настройка

---

### Этап 9: Тестирование (2-3 дня)

**Задачи:**
- [ ] Unit-тесты для всех модулей
- [ ] Интеграционные тесты
- [ ] Тестирование на разных конфигурациях
- [ ] Тестирование параллелизации
- [ ] Нагрузочное тестирование
- [ ] Проверка безопасности

**Результат:** Протестированная и стабильная система

---

### Этап 10: Документация (2 дня)

**Задачи:**
- [ ] README.md - обзор
- [ ] INSTALLATION.md - установка
- [ ] CONFIGURATION.md - настройка
- [ ] TROUBLESHOOTING.md - решение проблем
- [ ] Комментарии в коде
- [ ] Примеры конфигураций

**Результат:** Полная документация проекта

---

## 5. ТЕХНИЧЕСКИЕ ДЕТАЛИ РЕАЛИЗАЦИИ

### 5.1. Обработка ошибок

**Стратегия:**
- Каждая функция возвращает результат с полями `Success`, `Data`, `Error`
- Ошибки логируются, но не прерывают выполнение
- Глобальный try-catch в MaintenanceService
- Все ошибки попадают в отчет

**Пример:**
```powershell
function Invoke-Operation {
    try {
        # Выполнение операции
        return @{
            Success = $true
            Data = $result
            Error = $null
        }
    }
    catch {
        Write-Log "ERROR" $_.Exception.Message
        return @{
            Success = $false
            Data = $null
            Error = $_.Exception.Message
        }
    }
}
```

---

### 5.2. Параллелизация

**Реализация через PowerShell Jobs:**
```powershell
$jobs = @()
foreach ($repo in $repositories) {
    while ((Get-Job -State Running).Count -ge $maxThreads) {
        Start-Sleep -Milliseconds 100
    }
    
    $jobs += Start-Job -ScriptBlock {
        param($repoPath)
        Invoke-GitMaintenance -RepoPath $repoPath
    } -ArgumentList $repo
}

$results = $jobs | Wait-Job | Receive-Job
$jobs | Remove-Job
```

---

### 5.3. Тихий режим

**Реализация:**
```powershell
$global:SilentMode = $false

function Write-Log {
    param($Level, $Message)
    
    # Всегда пишем в файл
    Add-Content -Path $logFile -Value "[$timestamp] [$Level] $Message"
    
    # В консоль только если не тихий режим
    if (-not $global:SilentMode -or $Level -eq "ERROR") {
        Write-Host "[$Level] $Message" -ForegroundColor $color
    }
}
```

---

### 5.4. Валидация конфигурации

**JSON Schema для валидации:**
```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["settings"],
  "properties": {
    "settings": {
      "type": "object",
      "required": ["general"],
      "properties": {
        "git": { "..." },
        "edt": { "..." },
        "database": { "..." },
        "general": { "..." }
      }
    }
  }
}
```

---

## 6. КОНТРОЛЬНЫЕ ТОЧКИ

### Минимально работающий продукт (MVP)
**Состав:**
- ConfigManager + LoggingService
- GitService с основными командами
- Простой отчет в JSON
- Ручной запуск через командную строку

**Срок:** 3-4 дня

### Базовая функциональность
**Состав:**
- MVP + EdtService + DatabaseService
- Автопоиск объектов
- Полные JSON-отчеты
- Установщик

**Срок:** 7-10 дней

### Полная функциональность
**Состав:**
- Базовая функциональность + Параллелизация
- Тихий режим
- Планировщик задач
- Полная документация
- Тесты

**Срок:** 12-15 дней

---

## 7. КРИТЕРИИ ГОТОВНОСТИ

### Функциональные критерии
- ✅ Обслуживание Git работает и освобождает место
- ✅ Обслуживание EDT работает корректно
- ✅ Обслуживание баз 1С работает без ошибок
- ✅ Автопоиск находит все объекты
- ✅ JSON-отчеты формируются правильно
- ✅ Параллелизация ускоряет обработку
- ✅ Установщик работает автоматически

### Качественные критерии
- ✅ Код покрыт комментариями
- ✅ Есть unit-тесты для критичных функций
- ✅ Обработка всех ошибок
- ✅ Логирование всех операций
- ✅ Документация полная и понятная

### Производственные критерии
- ✅ Пилотное внедрение прошло успешно
- ✅ Нет критических ошибок
- ✅ Достигнуты целевые показатели по освобождению места
- ✅ Положительная обратная связь от пользователей

---

## 8. РИСКИ И МИТИГАЦИЯ

### Технические риски

| Риск | Вероятность | Влияние | Митигация |
|------|-------------|---------|-----------|
| Повреждение Git-репозиториев | Низкая | Высокое | Использование только штатных команд Git, тестирование |
| Повреждение баз 1С | Низкая | Высокое | Использование штатного инструментария 1С |
| Конфликты лицензий 1С | Средняя | Среднее | Последовательная обработка баз |
| Недостаточная производительность | Средняя | Среднее | Параллелизация, оптимизация команд |
| Проблемы с правами доступа | Средняя | Среднее | Проверка прав при установке |

### Организационные риски

| Риск | Вероятность | Влияние | Митигация |
|------|-------------|---------|-----------|
| Сопротивление пользователей | Низкая | Среднее | Автоматическая работа, минимум вмешательства |
| Проблемы развертывания | Средняя | Среднее | Автоматический установщик |
| Недостаточное тестирование | Средняя | Высокое | Пилотное внедрение, поэтапный rollout |

---

## 9. МЕТРИКИ УСПЕХА

### Технические метрики
- **Освобождение дискового пространства:** 50-80 ГБ на станцию (цель: >50 ГБ)
- **Время выполнения:** <120 мин в последовательном режиме, <60 мин в параллельном
- **Стабильность:** 0 критических ошибок в пилоте
- **Доступность:** >99% успешных запусков

### Бизнес-метрики
- **Экономия времени администраторов:** 30 мин/неделю на станцию
- **Удовлетворенность пользователей:** >80% положительных отзывов
- **Охват:** 100% рабочих станций разработчиков в течение 2 месяцев

### Качественные метрики
- **Покрытие тестами:** >70% критичного кода
- **Документация:** 100% функций задокументированы
- **Обработка ошибок:** 100% функций с error handling

---

## 10. СЛЕДУЮЩИЕ ШАГИ

### Немедленные действия
1. ✅ Создать репозиторий проекта
2. ✅ Настроить структуру папок
3. [ ] Начать разработку с Этапа 1 (базовая инфраструктура)
4. [ ] Создать первый MVP через 3-4 дня

### Краткосрочные (1-2 недели)
1. [ ] Завершить все сервисы обслуживания
2. [ ] Реализовать отчетность
3. [ ] Создать установщик
4. [ ] Провести внутреннее тестирование

### Среднесрочные (2-4 недели)
1. [ ] Пилотное внедрение на 2-3 станции
2. [ ] Сбор обратной связи
3. [ ] Доработка по результатам
4. [ ] Расширенное внедрение

### Долгосрочные (1-2 месяца)
1. [ ] Полное развертывание
2. [ ] Мониторинг метрик
3. [ ] Оптимизация на основе данных
4. [ ] План развития v2.0

---

**Конец документа**