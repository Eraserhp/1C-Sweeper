@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul 2>&1

REM ========== ЗНАЧЕНИЯ ПО УМОЛЧАНИЮ ==========
set "MAX_VERSION="
set "GIT_PATH=C:\git"
set "BASES_PATH=C:\bases"
set "EDT_PATH=C:\edt"
set "REPORT_DIR=%CD%\sweeper_reports"
set "CONFIG_FILE=sweeper.ini"

REM ========== ОБРАБОТКА ПАРАМЕТРОВ ==========
:parse_args
if "%~1"=="" goto :end_parse
if /i "%~1"=="/maxver" (
    set "MAX_VERSION=%~2"
    shift
    shift
    goto :parse_args
)
if /i "%~1"=="/git" (
    set "GIT_PATH=%~2"
    shift
    shift
    goto :parse_args
)
if /i "%~1"=="/bases" (
    set "BASES_PATH=%~2"
    shift
    shift
    goto :parse_args
)
if /i "%~1"=="/edt" (
    set "EDT_PATH=%~2"
    shift
    shift
    goto :parse_args
)
if /i "%~1"=="/reportdir" (
    set "REPORT_DIR=%~2"
    shift
    shift
    goto :parse_args
)
if /i "%~1"=="/config" (
    set "CONFIG_FILE=%~2"
    shift
    shift
    goto :parse_args
)
if /i "%~1"=="/?" goto :show_help
if /i "%~1"=="/help" goto :show_help
if /i "%~1"=="/skipgit" (
    set "SKIP_GIT=1"
    shift
    goto :parse_args
)
if /i "%~1"=="/skipdb" (
    set "SKIP_DB=1"
    shift
    goto :parse_args
)
if /i "%~1"=="/skipedt" (
    set "SKIP_EDT=1"
    shift
    goto :parse_args
)
if /i "%~1"=="/silent" (
    set "SILENT_MODE=1"
    shift
    goto :parse_args
)
if /i "%~1"=="/noreport" (
    set "NO_REPORT=1"
    shift
    goto :parse_args
)
shift
goto :parse_args

:end_parse

REM ========== ЗАГРУЗКА КОНФИГУРАЦИИ ИЗ ФАЙЛА ==========
if exist "%CONFIG_FILE%" (
    echo Loading configuration from %CONFIG_FILE%
    for /f "usebackq tokens=1,* delims==" %%A in ("%CONFIG_FILE%") do (
        set "LINE=%%A"
        if not "!LINE!"=="" (
            set "FIRST_CHAR=!LINE:~0,1!"
            if not "!FIRST_CHAR!"=="#" (
                set "VALUE=%%B"
                if defined VALUE (
                    for /f "tokens=* delims= " %%V in ("!VALUE!") do set "VALUE=%%V"
                    set "%%A=!VALUE!"
                )
            )
        )
    )
) else (
    if not "%CONFIG_FILE%"=="sweeper.ini" (
        echo WARNING: Configuration file %CONFIG_FILE% not found
    )
)

echo ========================================
echo 1C Git and Databases Cleanup Script
echo ========================================
echo.

REM ========== ПРОВЕРКА ПУТЕЙ ==========
echo Checking paths...

if not defined SKIP_GIT (
    if not exist "%GIT_PATH%" (
        echo WARNING: Git folder not found: %GIT_PATH%
        set "SKIP_GIT=1"
    ) else (
        echo [OK] Git repositories: %GIT_PATH%
    )
)

if not defined SKIP_DB (
    if not exist "%BASES_PATH%" (
        echo WARNING: Databases folder not found: %BASES_PATH%
        set "SKIP_DB=1"
    ) else (
        echo [OK] 1C Databases: %BASES_PATH%
    )
)

if not defined SKIP_EDT (
    if not exist "%EDT_PATH%" (
        echo WARNING: EDT folder not found: %EDT_PATH%
        set "SKIP_EDT=1"
    ) else (
        echo [OK] EDT workspace: %EDT_PATH%
    )
)

echo.

REM ========== ПОИСК ВЕРСИИ 1С ==========
if not defined SKIP_DB (
    set "ONEC_PATH="
    set "BEST_VERSION=0.0.0.0"
    set "SEARCH_PATH=%ProgramFiles%\1cv8"

    if not exist "!SEARCH_PATH!" (
        echo ERROR: Folder !SEARCH_PATH! not found!
        echo Please install 64-bit version of 1C
        goto :error_exit
    )

    echo Searching for 1C version...

    if not defined MAX_VERSION (
        echo No version limit specified, searching for maximum...
        
        for /d %%V in ("!SEARCH_PATH!\8.3.*") do (
            if exist "%%V\bin\1cv8.exe" (
                set "VERSION=%%~nxV"
                if "!VERSION!" GTR "!BEST_VERSION!" (
                    set "BEST_VERSION=!VERSION!"
                    set "ONEC_PATH=%%V\bin\1cv8.exe"
                )
            )
        )
        
        if defined ONEC_PATH (
            set "MAX_VERSION=!BEST_VERSION!"
        )
    ) else (
        echo Version limit: not higher than !MAX_VERSION!
        
        for /f "tokens=3 delims=." %%V in ("!MAX_VERSION!") do set "MAX_SUBVERSION=%%V"
        
        for /d %%V in ("!SEARCH_PATH!\8.3.*") do (
            set "VERSION=%%~nxV"
            
            if "!VERSION:~0,4!"=="8.3." (
                for /f "tokens=3 delims=." %%N in ("!VERSION!") do (
                    set "SUBVERSION=%%N"
                    
                    if !SUBVERSION! LEQ !MAX_SUBVERSION! (
                        if exist "%%V\bin\1cv8.exe" (
                            if "!VERSION!" GTR "!BEST_VERSION!" (
                                set "BEST_VERSION=!VERSION!"
                                set "ONEC_PATH=%%V\bin\1cv8.exe"
                            )
                        )
                    )
                )
            )
        )
    )

    if not defined ONEC_PATH (
        echo ERROR: Suitable 1C version not found!
        goto :error_exit
    )

    echo Found 1C version: !BEST_VERSION!
    echo Path: !ONEC_PATH!
)

echo.
echo ========================================
echo.

REM Создаём папку для отчётов
if not defined NO_REPORT (
    if not exist "%REPORT_DIR%" (
        mkdir "%REPORT_DIR%" 2>nul
    )
)

REM Создаём папку для логов 1С в текущей папке
if not exist "%CD%\1c_logs" (
    mkdir "%CD%\1c_logs" 2>nul
)

REM Инициализация глобальных счётчиков
set /a "GIT_COUNT=0"
set /a "GIT_PROCESSED=0"
set /a "GIT_ERRORS=0"
set /a "GIT_TOTAL_SAVED=0"
set /a "DB_COUNT=0"
set /a "DB_PROCESSED=0"
set /a "DB_ERRORS=0"
set /a "TOTAL_SAVED_MB=0"
set /a "EDT_CLEANED=0"

REM ========== ОЧИСТКА GIT ==========
if not defined SKIP_GIT (
    call :clean_git
)

REM ========== ОЧИСТКА БАЗ 1С ==========
if not defined SKIP_DB (
    call :clean_databases
)

REM ========== ОЧИСТКА EDT ==========
if not defined SKIP_EDT (
    call :clean_edt
)

REM ========== ЗАВЕРШЕНИЕ ==========
:finish
echo.
echo ========================================
echo Cleanup completed!
echo ========================================
echo.

REM ========== СОЗДАНИЕ ОТЧЁТА ==========
if not defined NO_REPORT (
    call :create_report
)

echo.
if not defined SILENT_MODE pause
exit /b 0

REM ========================================
REM ========== ФУНКЦИИ ==========
REM ========================================

:clean_git
pushd "%GIT_PATH%" 2>nul
if errorlevel 1 (
    echo ERROR: Cannot access Git path: %GIT_PATH%
    goto :eof
)

for /d %%G in (*) do (
    if exist "%%G\.git" set /a GIT_COUNT+=1
)

if !GIT_COUNT! GTR 0 (
    echo Found git repositories in %GIT_PATH%: !GIT_COUNT!
    echo Starting git cleanup...
    echo.
    
    for /d %%G in (*) do (
        if exist "%%G\.git" (
            echo ----------------------------------------
            echo Cleaning repository: %%G
            
            cd "%%G" 2>nul
            if not errorlevel 1 (
                if not defined SILENT_MODE (
                    echo Performing cleanup...
                )
                
                git gc --aggressive --prune=now >nul 2>&1
                if errorlevel 1 set /a GIT_ERRORS+=1
                
                git reflog expire --expire=7.days --all >nul 2>&1
                git remote prune origin >nul 2>&1
                git repack -a -d --depth=50 --window=100 >nul 2>&1
                
                echo Repository cleaned successfully
                
                set /a GIT_PROCESSED+=1
                cd ..
            )
            echo.
        )
    )
    
    echo Processed repositories: !GIT_PROCESSED! of !GIT_COUNT!
    if !GIT_ERRORS! GTR 0 echo WARNING: Errors in !GIT_ERRORS! repositories
    echo.
) else (
    echo No git repositories found in %GIT_PATH%
    echo.
)

popd
goto :eof

:clean_databases
pushd "%BASES_PATH%" 2>nul
if errorlevel 1 (
    echo ERROR: Cannot access databases path: %BASES_PATH%
    goto :eof
)

echo Searching for 1C databases...
echo Looking for 1Cv8.1CD files...

for /f "tokens=*" %%F in ('dir /s /b "1Cv8.1CD" 2^>nul') do (
    set /a DB_COUNT+=1
    for %%D in ("%%~dpF.") do (
        echo Found: %%~nxD
    )
)

echo.

if !DB_COUNT! GTR 0 (
    echo ========================================
    echo Found 1C databases: !DB_COUNT!
    echo Starting database restructuring...
    echo.
    
    for /f "tokens=*" %%F in ('dir /s /b "1Cv8.1CD" 2^>nul') do (
        for %%D in ("%%~dpF.") do (
            call :process_database "%%~nxD" "%%~fD"
        )
    )
    
    echo.
    echo Processed databases: !DB_PROCESSED! of !DB_COUNT!
    if !DB_ERRORS! GTR 0 echo WARNING: Errors in !DB_ERRORS! databases
    if !TOTAL_SAVED_MB! GTR 0 echo Total freed: !TOTAL_SAVED_MB! MB
    echo.
) else (
    echo No 1C databases found in %BASES_PATH%
    echo.
    echo Make sure your databases contain 1Cv8.1CD file
    echo.
    echo Example structure:
    echo   %BASES_PATH%\MyBase\1Cv8.1CD
    echo   %BASES_PATH%\Subfolder\AnotherBase\1Cv8.1CD
    echo.
)

popd
goto :eof

:process_database
set "DB_NAME=%~1"
set "DB_PATH=%~2"

echo ----------------------------------------
echo Restructuring database: %DB_NAME%
echo Path: %DB_PATH%

set "DB_FILE=%DB_PATH%\1Cv8.1CD"
if exist "%DB_FILE%" (
    REM Получаем размер файла правильным способом
    for /f "usebackq" %%S in (`powershell -Command "'{0:N0}' -f [math]::Round((Get-Item '%DB_FILE%').Length / 1MB)" 2^>nul`) do (
        set "SIZE_BEFORE_MB=%%S"
    )
    
    if not defined SIZE_BEFORE_MB (
        REM Если PowerShell не работает, используем альтернативный метод
        set "SIZE_BEFORE_MB=Unknown"
        echo Size before: Large file (exact size unavailable)
    ) else (
        echo Size before: !SIZE_BEFORE_MB! MB
    )
    
    if not defined SILENT_MODE (
        echo Performing restructuring...
    )
    
    REM Создаём уникальный лог файл в папке скрипта с датой и временем
    for /f "tokens=2 delims==" %%T in ('wmic OS Get localdatetime /value 2^>nul') do set "DT_LOG=%%T"
    if not defined DT_LOG set "DT_LOG=%date:~-4%%date:~3,2%%date:~0,2%_%time:~0,2%%time:~3,2%%time:~6,2%"
    set "DT_LOG=!DT_LOG: =0!"
    set "TEMP_LOG=%CD%\1c_logs\1c_log_%DB_NAME%_!DT_LOG:~0,8!_!DT_LOG:~8,6!.txt"
    
    REM Пытаемся сначала без авторизации, затем с разными вариантами
    echo Attempting database restructure...
    
    REM Вариант 1: Без пользователя (для файловых баз)
    "!ONEC_PATH!" DESIGNER /F"%DB_PATH%" /IBCheckAndRepair -ReIndex -IBCompression /DisableStartupDialogs /Out "!TEMP_LOG!" 2>&1
    set "RESTRUCTURE_RESULT=!ERRORLEVEL!"
    
    REM Если ошибка авторизации, пробуем с пустым пользователем
    if !RESTRUCTURE_RESULT! EQU 1 (
        echo First attempt failed, trying with empty user credentials...
        "!ONEC_PATH!" DESIGNER /F"%DB_PATH%" /N"" /P"" /IBCheckAndRepair -ReIndex -IBCompression /DisableStartupDialogs /Out "!TEMP_LOG!" 2>&1
        set "RESTRUCTURE_RESULT=!ERRORLEVEL!"
        
        REM Если все еще ошибка, пробуем с Administrator
        if !RESTRUCTURE_RESULT! EQU 1 (
            echo Second attempt failed, trying with Administrator credentials...
            "!ONEC_PATH!" DESIGNER /F"%DB_PATH%" /N"Администратор" /P"" /IBCheckAndRepair -ReIndex -IBCompression /DisableStartupDialogs /Out "!TEMP_LOG!" 2>&1
            set "RESTRUCTURE_RESULT=!ERRORLEVEL!"
        )
    )
    
    REM Ждём немного для записи лога
    timeout /t 1 /nobreak >nul 2>&1
    
    echo Restructure completed with exit code: !RESTRUCTURE_RESULT!
    
    REM Анализируем лог для определения реального результата
    set "PROCESS_SUCCESS=0"
    if exist "!TEMP_LOG!" (
        type "!TEMP_LOG!" | find /i "Тестирование закончено" >nul
        if not errorlevel 1 set "PROCESS_SUCCESS=1"
        
        type "!TEMP_LOG!" | find /i "Исправление закончено" >nul  
        if not errorlevel 1 set "PROCESS_SUCCESS=1"
    )
    
    REM Если есть критические ошибки или процесс не завершился успешно
    if !RESTRUCTURE_RESULT! NEQ 0 if !PROCESS_SUCCESS! EQU 0 (
        set /a DB_ERRORS+=1
        echo ERROR: Failed to restructure (Error code: !RESTRUCTURE_RESULT!)
        
        REM Показываем содержимое лога
        if exist "!TEMP_LOG!" (
            for %%F in ("!TEMP_LOG!") do set "LOG_SIZE=%%~zF"
            if defined LOG_SIZE (
                if !LOG_SIZE! GTR 0 (
                    echo.
                    echo Error details:
                    echo ==================
                    type "!TEMP_LOG!"
                    echo ==================
                    echo.
                    
                    REM Анализируем ошибку и даем рекомендации
                    type "!TEMP_LOG!" | find /i "Пользователь ИБ не идентифицирован" >nul
                    if not errorlevel 1 (
                        echo SOLUTION: This database requires user authentication.
                        echo You need to:
                        echo 1. Find out the correct username/password
                        echo 2. Or use 1C interface to restructure manually
                        echo 3. Or disable user authentication in this database
                    )
                    
                    type "!TEMP_LOG!" | find /i "файл заблокирован" >nul
                    if not errorlevel 1 (
                        echo SOLUTION: Database file is locked.
                        echo Close all 1C applications and try again.
                    )
                )
            )
        )
        
        REM Проверяем процессы 1С
        tasklist /FI "IMAGENAME eq 1cv8.exe" 2>nul | find /i "1cv8.exe" >nul
        if not errorlevel 1 (
            echo WARNING: 1C processes are running! Close them and try again.
        )
        
        REM Не удаляем лог файл при ошибке для диагностики
        echo Log file saved: !TEMP_LOG!
        
    ) else (
        echo Database restructured successfully!
        
        REM Показываем информацию о процессе
        if exist "!TEMP_LOG!" (
            echo Process log:
            type "!TEMP_LOG!"
        )
        
        REM Получаем размер после обработки
        for /f "usebackq" %%S in (`powershell -Command "'{0:N0}' -f [math]::Round((Get-Item '%DB_FILE%').Length / 1MB)" 2^>nul`) do (
            set "SIZE_AFTER_MB=%%S"
        )
        
        if not defined SIZE_AFTER_MB set "SIZE_AFTER_MB=Unknown"
        
        echo Size after: !SIZE_AFTER_MB! MB
        
        REM Вычисляем экономию только если у нас есть числовые размеры
        if not "!SIZE_BEFORE_MB!"=="Unknown" if not "!SIZE_AFTER_MB!"=="Unknown" (
            if not "!SIZE_BEFORE_MB!"=="0" if not "!SIZE_AFTER_MB!"=="0" (
                set /a "SAVED_MB=!SIZE_BEFORE_MB!-!SIZE_AFTER_MB!" 2>nul
                if defined SAVED_MB (
                    if !SAVED_MB! GTR 0 (
                        echo Freed: !SAVED_MB! MB
                        set /a "TOTAL_SAVED_MB+=!SAVED_MB!"
                    ) else if !SAVED_MB! LSS 0 (
                        set /a "SAVED_MB=0-!SAVED_MB!"
                        echo Size increased by: !SAVED_MB! MB (normal after reindexing)
                    ) else (
                        echo No size change (database was already optimized)
                    )
                )
            )
        )
        
        REM Удаляем лог при успехе
        if exist "!TEMP_LOG!" del "!TEMP_LOG!" >nul 2>&1
    )
    
    set /a DB_PROCESSED+=1
) else (
    echo WARNING: Database file 1Cv8.1CD not found in %DB_PATH%!
    set /a DB_ERRORS+=1
)
echo.
goto :eof

:clean_edt
if not defined SILENT_MODE (
    echo ========================================
    set /p CLEAN_EDT=Clean EDT cache? (Y/N): 
) else (
    set "CLEAN_EDT=Y"
)

if /i "!CLEAN_EDT!"=="Y" (
    echo.
    echo Cleaning EDT cache in %EDT_PATH%...
    
    pushd "%EDT_PATH%" 2>nul
    if not errorlevel 1 (
        for /d %%W in (*) do (
            if exist "%%W\.metadata" (
                echo Cleaning workspace: %%W
                
                if exist "%%W\.metadata\.plugins\org.eclipse.jdt.core" (
                    rmdir /s /q "%%W\.metadata\.plugins\org.eclipse.jdt.core" 2>nul
                    echo - JDT cache cleared
                )
                
                if exist "%%W\.metadata\.plugins\com._1c.g5.v8.dt.metadata.md" (
                    rmdir /s /q "%%W\.metadata\.plugins\com._1c.g5.v8.dt.metadata.md" 2>nul
                    echo - 1C metadata cache cleared
                )
                
                set /a EDT_CLEANED+=1
            )
        )
        
        if !EDT_CLEANED! GTR 0 (
            echo.
            echo Cleaned workspaces: !EDT_CLEANED!
            echo WARNING: EDT will reindex on next start!
        ) else (
            echo No workspaces found
        )
        
        popd
    ) else (
        echo ERROR: Cannot access EDT path: %EDT_PATH%
    )
)
goto :eof

:create_report
for /f "tokens=2 delims==" %%T in ('wmic OS Get localdatetime /value 2^>nul') do set "DT=%%T"
if not defined DT set "DT=%date:~-4%%date:~3,2%%date:~0,2%_%time:~0,2%%time:~3,2%%time:~6,2%"
set "DT=!DT: =0!"
set "REPORT_FILE=%REPORT_DIR%\sweeper_report_!DT:~0,8!_!DT:~8,6!.txt"

(
    echo Sweeper Report
    echo =====================================
    echo Date and time: %date% %time%
    echo 1C Version: !BEST_VERSION!
    echo =====================================
    echo.
    echo Used paths:
    echo   Git: %GIT_PATH%
    echo   Databases: %BASES_PATH%
    echo   EDT: %EDT_PATH%
    echo   Reports: %REPORT_DIR%
    echo.
    echo Results:
    if not defined SKIP_GIT (
        echo   Git repositories:
        echo     Processed: !GIT_PROCESSED! of !GIT_COUNT!
        if !GIT_ERRORS! GTR 0 echo     Errors: !GIT_ERRORS!
    )
    if not defined SKIP_DB (
        echo   1C Databases:
        echo     Processed: !DB_PROCESSED! of !DB_COUNT!
        if !DB_ERRORS! GTR 0 echo     Errors: !DB_ERRORS!
        if !TOTAL_SAVED_MB! GTR 0 echo     Freed: !TOTAL_SAVED_MB! MB
    )
    if not defined SKIP_EDT (
        if !EDT_CLEANED! GTR 0 (
            echo   EDT workspaces:
            echo     Cleaned: !EDT_CLEANED!
        )
    )
    echo =====================================
) > "!REPORT_FILE!"

echo Report saved: !REPORT_FILE!
goto :eof

:show_help
echo.
echo Usage: %~nx0 [options]
echo.
echo PATH OPTIONS:
echo   /git PATH         Path to Git repositories (default: C:\git)
echo   /bases PATH       Path to 1C databases (default: C:\bases)
echo   /edt PATH         Path to EDT workspaces (default: C:\edt)
echo   /reportdir PATH   Path for saving reports
echo   /config FILE      Load settings from file (default: sweeper.ini)
echo.
echo VERSION OPTIONS:
echo   /maxver X.X.XX    Maximum 1C version
echo                     (default: maximum installed)
echo.
echo CONTROL OPTIONS:
echo   /skipgit          Skip Git cleanup
echo   /skipdb           Skip database restructuring  
echo   /skipedt          Skip EDT cleanup
echo   /silent           Silent mode
echo   /noreport         Don't create report
echo   /? /help          Show this help
echo.
echo DATABASE STRUCTURE:
echo   Databases should contain 1Cv8.1CD file:
echo   C:\bases\MyBase\1Cv8.1CD
echo   C:\bases\Group\Base1\1Cv8.1CD
echo.
echo EXAMPLES:
echo   %~nx0
echo     Use default settings
echo.
echo   %~nx0 /config my_config.ini
echo     Load configuration from file
echo.
echo   %~nx0 /bases "D:\1C Bases" /skipgit
echo     Clean only databases from specific path
echo.
exit /b 0

:error_exit
echo.
echo Script completed with errors!
if not defined SILENT_MODE pause
exit /b 1