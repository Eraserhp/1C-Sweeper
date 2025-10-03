# 1C-Sweeper
Комплексный инструмент для очистки и оптимизации инфраструктуры 1С-разработчика: сжатие Git-репозиториев, реструктуризация баз 1С, очистка EDT workspace. Освобождает место на диске, ускоряет работу. Конфигурируемый запуск, детальные отчёты, поддержка планировщика задач Windows.

Структура файлов:
1C-Sweeper\
├── sweeper.bat              # Основной скрипт очистки
├── sweeper.ini             # Файл конфигурации по умолчанию
├── sweeper_launcher.bat    # Интерактивный запуск
├── analyze_reports.bat     # Анализ отчётов
├── setup_scheduler.ps1     # Настройка планировщика
├── view_reports.bat        # Просмотр отчётов
├── sweeper_reports\       # Папка с отчётами
│   └── ...
└── README.md             # Документация

Примеры использования:
REM Использовать настройки по умолчанию
sweeper.bat

REM Указать свои пути
sweeper.bat /git D:\MyRepos /bases D:\1C_Bases /edt D:\EDT_Work

REM Использовать максимальную установленную версию 1С
sweeper.bat /git C:\git /bases C:\bases

REM Ограничить версию 1С
sweeper.bat /maxver 8.3.25 /git D:\repos

REM Только Git репозитории в другой папке
sweeper.bat /git E:\GitProjects /skipdb /skipedt

REM Тихий режим для планировщика
sweeper.bat /silent /noreport

REM Использовать файл конфигурации
sweeper.bat /config production.ini

REM Только очистка баз
D:\OneDrive\Projects\sweeper_tools\
sweeper.bat /config sweeper.ini /skipgit /skipedt

D:\OneDrive\Projects\sweeper_tools\
sweeper.bat /config sweeper.ini

"C:\Program Files\1cv8\8.3.27.1719\bin\1cv8.exe" DESIGNER /F"G:\Bases\Основные хранилища\LTS" /N"Администратор" /P"пароль" /TestAndRepair -IBCompression /DisableStartupDialogs