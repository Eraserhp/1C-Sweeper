# 1C-Sweeper 🧹

**Система автоматизированного обслуживания Git-репозиториев, EDT workspace и информационных баз 1С**

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue)](https://github.com/PowerShell/PowerShell)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![Status](https://img.shields.io/badge/status-production-brightgreen)](README.md)

---

## 📋 Описание

1C-Sweeper - это автоматизированная система для регулярного обслуживания и оптимизации:

- **Git-репозиториев** - очистка, упаковка, сборка мусора
- **EDT Workspaces** - очистка кэшей, логов, индексов Eclipse/EDT
- **Баз данных 1С** - тестирование и исправление через штатные средства платформы

### 🎯 Проблема

В процессе разработки средствами 1С:EDT с использованием Git наблюдается систематическое раздувание дискового пространства:

- Git-репозитории разрастаются от 12 ГБ до 29 ГБ
- EDT Workspaces достигают 10 ГБ
- Базы данных 1С фрагментируются и растут без видимых причин

### ✅ Решение

1C-Sweeper автоматически выполняет регулярное обслуживание, освобождая:

- **50-80 ГБ** на каждой рабочей станции
- Git-репозитории сжимаются на **40-60%**
- EDT workspace уменьшаются на **60-80%**
- Базы 1С оптимизируются на **20-40%**

---

## 🚀 Быстрый старт

### Установка

1. **Клонируйте репозиторий:**
```powershell
git clone https://github.com/your-org/1C-Sweeper.git
cd 1C-Sweeper
```

2. **Запустите установщик с правами администратора:**
```powershell
PowerShell -ExecutionPolicy Bypass -File .\install\Install.ps1
```

3. **Следуйте инструкциям установщика:**
   - Установщик автоматически найдет Git-репозитории, EDT workspace и базы 1С
   - Настроит конфигурацию
   - Создаст задачу в планировщике Windows

### Ручной запуск

```powershell
PowerShell -ExecutionPolicy Bypass -File "C:\1C-Sweeper\src\MaintenanceService.ps1" -ConfigPath "C:\1C-Sweeper\config\maintenance-config.json"
```

### Тестовый запуск (DryRun)

```powershell
PowerShell -ExecutionPolicy Bypass -File "C:\1C-Sweeper\src\MaintenanceService.ps1" -ConfigPath "C:\1C-Sweeper\config\maintenance-config.json" -DryRun
```

---

## 📦 Системные требования

### Обязательные

- **Windows 10** (1809+) или **Windows 11** или **Windows Server 2016+**
- **PowerShell 5.1+** (встроен в Windows)
- **Права администратора** (для настройки планировщика)

### Опциональные

- **Git** - для обслуживания репозиториев
- **1С:Предприятие 8.3** - для обслуживания баз данных
- **Eclipse/EDT** - для обслуживания workspace

---

## 🎛️ Конфигурация

Конфигурация хранится в JSON-файле (по умолчанию: `C:\1C-Sweeper\config\maintenance-config.json`).

### Пример конфигурации

```json
{
  "settings": {
    "git": {
      "repos": ["C:\\Dev\\Project1"],
      "searchPaths": ["C:\\Dev", "D:\\Projects"],
      "sizeThresholdGB": 15
    },
    "edt": {
      "workspaces": ["C:\\EDT\\workspace1"],
      "searchPaths": ["C:\\EDT"],
      "sizeThresholdGB": 5
    },
    "database": {
      "databases": ["C:\\Bases\\Dev\\1Cv8.1CD"],
      "searchPaths": ["C:\\Bases"],
      "platformVersion": "8.3.27",
      "user": "",
      "password": "",
      "sizeThresholdGB": 3
    },
    "general": {
      "reportsPath": "C:\\1C-Sweeper\\reports",
      "silentMode": false,
      "parallelProcessing": true,
      "maxParallelTasks": 3
    }
  }
}
```

### Параметры конфигурации

#### Git

- `repos` - явно указанные репозитории
- `searchPaths` - папки для автопоиска репозиториев
- `sizeThresholdGB` - минимальный размер для запуска обслуживания (рекомендуется: 15 ГБ)

#### EDT

- `workspaces` - явно указанные workspace
- `searchPaths` - папки для автопоиска workspace
- `sizeThresholdGB` - минимальный размер для запуска обслуживания (рекомендуется: 5 ГБ)

#### Database

- `databases` - явно указанные базы
- `searchPaths` - папки для автопоиска баз
- `platformVersion` - маска версии платформы (`8.3.27`, `8.3.*`, пусто = любая)
- `user` / `password` - учетные данные (опционально, пароль в Base64)
- `sizeThresholdGB` - минимальный размер для запуска обслуживания (рекомендуется: 3 ГБ)

#### General

- `reportsPath` - путь для сохранения отчетов
- `silentMode` - тихий режим (отключает вывод INFO в консоль)
- `parallelProcessing` - параллельная обработка (рекомендуется: true)
- `maxParallelTasks` - максимум параллельных задач (рекомендуется: CPU_CORES - 1)

---

## 🔧 Использование

### Параметры командной строки

```powershell
MaintenanceService.ps1 [-ConfigPath <path>] [-DryRun] [-Silent] [-Force] [-Objects <types>]
```

**Параметры:**

- `-ConfigPath` - путь к конфигурационному файлу
- `-DryRun` - тестовый запуск без изменений
- `-Silent` - тихий режим (только ERROR в консоль)
- `-Force` - игнорировать пороги размера
- `-Objects` - обработать только определенные типы (`Git`, `EDT`, `Database`)

### Примеры использования

**Обычный запуск:**
```powershell
.\MaintenanceService.ps1 -ConfigPath "config.json"
```

**Тестовый запуск:**
```powershell
.\MaintenanceService.ps1 -ConfigPath "config.json" -DryRun
```

**Только Git-репозитории:**
```powershell
.\MaintenanceService.ps1 -ConfigPath "config.json" -Objects Git
```

**Тихий режим (для автоматизации):**
```powershell
.\MaintenanceService.ps1 -ConfigPath "config.json" -Silent
```

---

## 📊 Отчеты

Система генерирует детальные JSON-отчеты после каждого запуска.

### Структура отчета

```json
{
  "reportVersion": "1.0",
  "timestamp": "2025-10-06T20:15:30Z",
  "duration": 2340,
  "hostname": "WORKSTATION-01",
  "summary": {
    "totalSpaceSaved": 68.4,
    "gitReposProcessed": 4,
    "gitReposSuccess": 4,
    "gitReposFailed": 0,
    "workspacesProcessed": 4,
    "workspacesSuccess": 4,
    "workspacesFailed": 0,
    "databasesProcessed": 4,
    "databasesSuccess": 4,
    "databasesFailed": 0
  },
  "gitRepositories": [...],
  "edtWorkspaces": [...],
  "databases": [...],
  "errors": []
}
```

### Расположение отчетов

По умолчанию: `C:\1C-Sweeper\reports\`

Формат имени: `maintenance-report_HOSTNAME_YYYY-MM-DD_HH-mm-ss.json`

---

## 🔄 Обслуживание

### Что обслуживается

#### Git-репозитории

```powershell
git remote prune origin  # Очистка удаленных веток
git repack -ad           # Упаковка объектов
git prune --expire=now   # Удаление недостижимых объектов
git gc --prune=now       # Сборка мусора
```

**Результат:** Сжатие репозитория на 40-60% (типично: 25 ГБ → 12 ГБ)

#### EDT Workspace

- Удаление логов (`.metadata/.log`)
- Очистка кэшей плагинов
- Удаление индексов
- Очистка истории локальных изменений

**Результат:** Уменьшение workspace на 60-80% (типично: 8 ГБ → 2 ГБ)

#### Базы данных 1С

- Запуск "Тестирование и исправление" через платформу
- Дефрагментация базы
- Освобождение неиспользуемого пространства

**Результат:** Оптимизация базы на 20-40% (типично: 5 ГБ → 3 ГБ)

### Когда запускать

**Рекомендуется:**
- Еженедельно (по выходным)
- Вне рабочего времени
- При отсутствии активной разработки

**Длительность:**
- Последовательный режим: 60-120 минут
- Параллельный режим: 35-60 минут

---

## 🔐 Безопасность

- ✅ Использует только штатные средства Git и 1С
- ✅ Не изменяет данные в репозиториях и базах
- ✅ Проверяет доступность базы перед обслуживанием
- ✅ Изолирует ошибки (сбой одного объекта не прерывает обработку других)
- ✅ Пароли хранятся в Base64 (минимальная защита)
- ✅ Не передает данные по сети

---

## 🛠️ Разработка и тестирование

### Запуск тестов

```powershell
# Тест базовой инфраструктуры
.\tests\Test-Infrastructure.ps1

# Тест Git-сервиса
.\tests\Test-GitService.ps1

# Тест EDT-сервиса
.\tests\Test-EdtService.ps1

# Тест Database-сервиса
.\tests\Test-DatabaseService.ps1

# Тест отчетности
.\tests\Test-ReportService.ps1

# Тест главного оркестратора
.\tests\Test-MaintenanceService.ps1

# Запуск всех тестов
.\tests\Run-AllTests.ps1
```

### Структура проекта

```
1C-Sweeper/
├── src/
│   ├── MaintenanceService.ps1     # Главный скрипт
│   ├── core/                       # Ядро системы
│   │   ├── Common.ps1
│   │   ├── LoggingService.ps1
│   │   ├── ConfigManager.ps1
│   │   └── ReportService.ps1
│   ├── services/                   # Сервисы обслуживания
│   │   ├── GitService.ps1
│   │   ├── EdtService.ps1
│   │   └── DatabaseService.ps1
│   └── discovery/                  # Автопоиск
│       ├── GitDiscovery.ps1
│       ├── EdtDiscovery.ps1
│       ├── DatabaseDiscovery.ps1
│       └── PlatformDiscovery.ps1
├── install/
│   ├── Install.ps1                 # Установщик
│   ├── Uninstall.ps1              # Деинсталлятор
│   └── Update.ps1                  # Обновление
├── tests/                          # Тесты
├── docs/                           # Документация
└── config/                         # Конфигурация
```

---

## 🐛 Устранение проблем

### Git не найден

**Проблема:** Git не доступен из командной строки

**Решение:**
```powershell
# Проверьте установку Git
git --version

# Добавьте Git в PATH
$env:Path += ";C:\Program Files\Git\bin"
```

### Платформа 1С не найдена

**Проблема:** Система не может найти установленную платформу

**Решение:**
- Убедитесь, что 1С установлена в стандартный путь
- Укажите конкретную версию в `platformVersion`
- Проверьте наличие в реестре Windows

### База 1С занята

**Проблема:** "База данных занята (открыта в 1С)"

**Решение:**
- Закройте все сеансы 1С
- Запустите обслуживание вне рабочего времени
- Проверьте наличие файла блокировки `.1CL`

### Ошибки прав доступа

**Проблема:** Недостаточно прав для выполнения операций

**Решение:**
- Запустите PowerShell с правами администратора
- Проверьте права доступа к папкам репозиториев и баз
- Настройте ExecutionPolicy: `Set-ExecutionPolicy RemoteSigned`

---

## 📖 Дополнительная документация

- [Техническое задание](docs/TECHNICAL_SPECIFICATION.md)
- [План разработки](docs/DEVELOPMENT_PLAN.md)
- [Руководство по установке](docs/INSTALLATION.md)
- [Описание конфигурации](docs/CONFIGURATION.md)
- [Решение проблем](docs/TROUBLESHOOTING.md)

---

## 🤝 Участие в разработке

Мы приветствуем вклад в развитие проекта! Пожалуйста:

1. Форкните репозиторий
2. Создайте ветку для новой функциональности
3. Внесите изменения и протестируйте
4. Создайте Pull Request

### Стандарты кода

- PowerShell 5.1+ совместимость
- Используйте `Set-StrictMode -Version Latest`
- Комментируйте функции (синтаксис PowerShell Help)
- Покрывайте код тестами
- Следуйте архитектуре проекта

---

## 📝 Лицензия

MIT License - см. [LICENSE](LICENSE)

---

## 👥 Авторы

- Проект разработан для автоматизации обслуживания рабочих станций разработчиков 1С
- Основан на лучших практиках работы с Git и 1С:Предприятие

---

## 📧 Поддержка

- **Issues:** [GitHub Issues](https://github.com/your-org/1C-Sweeper/issues)
- **Wiki:** [Project Wiki](https://github.com/your-org/1C-Sweeper/wiki)
- **Discussions:** [GitHub Discussions](https://github.com/your-org/1C-Sweeper/discussions)

---

## 🎉 Благодарности

Спасибо всем, кто использует 1C-Sweeper и вносит вклад в его развитие!

---

**1C-Sweeper** - автоматизация обслуживания для продуктивной разработки! 🧹✨