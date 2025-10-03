@echo off
REM analyze_reports.bat - Анализ отчётов очистки

setlocal enabledelayedexpansion
chcp 65001 >nul

set "REPORT_DIR=%~1"
if "%REPORT_DIR%"=="" set "REPORT_DIR=sweeper_reports"

echo ========================================
echo Анализ отчётов очистки
echo ========================================
echo.

if not exist "%REPORT_DIR%" (
    echo ОШИБКА: Папка отчётов не найдена: %REPORT_DIR%
    exit /b 1
)

REM Статистика по всем отчётам
set /a TOTAL_REPORTS=0
set /a TOTAL_GIT_SAVED=0
set /a TOTAL_DB_SAVED=0
set /a TOTAL_EDT_SAVED=0
set /a TOTAL_ERRORS=0

echo Анализ отчётов в %REPORT_DIR%...
echo.

for %%F in ("%REPORT_DIR%\sweeper_report_*.txt") do (
    set /a TOTAL_REPORTS+=1
    
    REM Извлекаем данные из отчёта
    for /f "tokens=2 delims=:" %%L in ('findstr /c:"Git.*Освобождено:" "%%F" 2^>nul') do (
        for /f "tokens=1" %%N in ("%%L") do (
            set /a TOTAL_GIT_SAVED+=%%N 2>nul
        )
    )
    
    for /f "tokens=2 delims=:" %%L in ('findstr /c:"Базы.*Освобождено:" "%%F" 2^>nul') do (
        for /f "tokens=1" %%N in ("%%L") do (
            set /a TOTAL_DB_SAVED+=%%N 2>nul
        )
    )
    
    for /f "tokens=2 delims=:" %%L in ('findstr /c:"EDT.*Освобождено:" "%%F" 2^>nul') do (
        for /f "tokens=1" %%N in ("%%L") do (
            set /a TOTAL_EDT_SAVED+=%%N 2>nul
        )
    )
    
    findstr /c:"Ошибок:" "%%F" >nul 2>&1
    if not errorlevel 1 set /a TOTAL_ERRORS+=1
)

set /a TOTAL_SAVED=TOTAL_GIT_SAVED+TOTAL_DB_SAVED+TOTAL_EDT_SAVED
set /a TOTAL_SAVED_GB=TOTAL_SAVED/1024

echo ========================================
echo ИТОГОВАЯ СТАТИСТИКА
echo ========================================
echo.
echo Проанализировано отчётов: %TOTAL_REPORTS%
echo.
echo Освобождено места:
echo   - Git репозитории: %TOTAL_GIT_SAVED% МБ
echo   - Базы 1С: %TOTAL_DB_SAVED% МБ
echo   - EDT workspace: %TOTAL_EDT_SAVED% МБ
echo   ────────────────────────
echo   ИТОГО: %TOTAL_SAVED% МБ (~%TOTAL_SAVED_GB% ГБ)
echo.
if %TOTAL_ERRORS% GTR 0 (
    echo ВНИМАНИЕ: Обнаружены ошибки в %TOTAL_ERRORS% отчётах!
)

REM График по месяцам
echo.
echo ========================================
echo СТАТИСТИКА ПО МЕСЯЦАМ
echo ========================================
echo.

for %%M in (01 02 03 04 05 06 07 08 09 10 11 12) do (
    set /a MONTH_SAVED_%%M=0
    set /a MONTH_COUNT_%%M=0
)

REM Подсчёт по месяцам
for %%F in ("%REPORT_DIR%\sweeper_report_*.txt") do (
    REM Извлекаем месяц из имени файла
    for /f "tokens=3 delims=_" %%N in ("%%~nF") do (
        set "DATE_STR=%%N"
        set "MONTH=!DATE_STR:~4,2!"
        
        set /a MONTH_COUNT_!MONTH!+=1
        
        for /f "tokens=2 delims=:" %%L in ('findstr /c:"ИТОГО.*Освобождено:" "%%F" 2^>nul') do (
            for /f "tokens=1" %%S in ("%%L") do (
                set /a MONTH_SAVED_!MONTH!+=%%S 2>nul
            )
        )
    )
)

REM Вывод статистики по месяцам
for %%M in (01 02 03 04 05 06 07 08 09 10 11 12) do (
    if !MONTH_COUNT_%%M! GTR 0 (
        set "MONTH_NAME="
        if "%%M"=="01" set "MONTH_NAME=Январь  "
        if "%%M"=="02" set "MONTH_NAME=Февраль "
        if "%%M"=="03" set "MONTH_NAME=Март    "
        if "%%M"=="04" set "MONTH_NAME=Апрель  "
        if "%%M"=="05" set "MONTH_NAME=Май     "
        if "%%M"=="06" set "MONTH_NAME=Июнь    "
        if "%%M"=="07" set "MONTH_NAME=Июль    "
        if "%%M"=="08" set "MONTH_NAME=Август  "
        if "%%M"=="09" set "MONTH_NAME=Сентябрь"
        if "%%M"=="10" set "MONTH_NAME=Октябрь "
        if "%%M"=="11" set "MONTH_NAME=Ноябрь  "
        if "%%M"=="12" set "MONTH_NAME=Декабрь "
        
        echo !MONTH_NAME!: !MONTH_COUNT_%%M! запусков, освобождено !MONTH_SAVED_%%M! МБ
    )
)

echo.
echo ========================================
pause