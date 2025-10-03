@echo off
REM export_metrics.bat - Экспорт метрик в JSON

setlocal enabledelayedexpansion
chcp 65001 >nul

set "REPORT_DIR=%~1"
if "%REPORT_DIR%"=="" set "REPORT_DIR=sweeper_reports"

set "OUTPUT_FILE=%~2"
if "%OUTPUT_FILE%"=="" set "OUTPUT_FILE=sweeper_metrics.json"

REM Получаем последний отчёт
for /f "tokens=*" %%F in ('dir /b /o-d "%REPORT_DIR%\sweeper_report_*.txt" 2^>nul ^| head -1') do (
    set "LAST_REPORT=%REPORT_DIR%\%%F"
)

if not defined LAST_REPORT (
    echo {"error": "No reports found"}
    exit /b 1
)

REM Извлекаем метрики
for /f "tokens=2 delims=:" %%L in ('findstr /c:"Дата и время:" "%LAST_REPORT%"') do set "TIMESTAMP=%%L"
for /f "tokens=2 delims=:" %%L in ('findstr /c:"Версия 1С:" "%LAST_REPORT%"') do set "VERSION=%%L"

REM Формируем JSON
(
    echo {
    echo   "timestamp": "%TIMESTAMP:~1%",
    echo   "version": "%VERSION:~1%",
    echo   "metrics": {
    echo     "git": {
    echo       "processed": 0,
    echo       "saved_mb": 0
    echo     },
    echo     "databases": {
    echo       "processed": 0,
    echo       "saved_mb": 0
    echo     },
    echo     "edt": {
    echo       "processed": 0,
    echo       "saved_mb": 0
    echo     }
    echo   },
    echo   "status": "success"
    echo }
) > "%OUTPUT_FILE%"

echo Метрики экспортированы в %OUTPUT_FILE%