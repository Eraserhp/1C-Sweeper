@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul 2>&1

REM view_reports.bat - View sweeper reports

set "REPORT_DIR=%CD%\sweeper_reports"
set "CONFIG_FILE=sweeper.ini"

REM Load configuration if exists
if exist "%CONFIG_FILE%" (
    for /f "usebackq tokens=1,* delims==" %%A in ("%CONFIG_FILE%") do (
        set "LINE=%%A"
        if not "!LINE:~0,1!"=="#" if not "!LINE!"=="" (
            if "%%A"=="REPORT_DIR" set "REPORT_DIR=%%B"
        )
    )
)

REM Process parameters
:parse_args
if "%~1"=="" goto :end_parse
if /i "%~1"=="/?" goto :help
if /i "%~1"=="/help" goto :help
if /i "%~1"=="/dir" (
    set "REPORT_DIR=%~2"
    shift
    shift
    goto :parse_args
)
if /i "%~1"=="/config" (
    set "CONFIG_FILE=%~2"
    if exist "!CONFIG_FILE!" (
        for /f "usebackq tokens=1,* delims==" %%A in ("!CONFIG_FILE!") do (
            if "%%A"=="REPORT_DIR" set "REPORT_DIR=%%B"
        )
    )
    shift
    shift
    goto :parse_args
)
shift
goto :parse_args
:end_parse

echo ========================================
echo View Cleanup Reports
echo ========================================
echo.
echo Reports folder: %REPORT_DIR%
echo.

if not exist "%REPORT_DIR%" (
    echo ERROR: Folder does not exist!
    exit /b 1
)

REM Count reports
set /a COUNT=0
for %%F in ("%REPORT_DIR%\sweeper_report_*.txt") do (
    if exist "%%F" set /a COUNT+=1
)

if %COUNT%==0 (
    echo No reports found
    exit /b 0
)

echo Found reports: %COUNT%
echo.

REM Show last 10 reports
echo Last 10 reports:
echo ========================================

set /a SHOWN=0
for /f "tokens=*" %%F in ('dir /b /o-d "%REPORT_DIR%\sweeper_report_*.txt" 2^>nul') do (
    if !SHOWN! LSS 10 (
        echo - %%F
        set /a SHOWN+=1
    )
)

echo.
pause
exit /b 0

:help
echo.
echo Usage: %~nx0 [options]
echo.
echo Options:
echo   /dir PATH        Path to reports folder
echo   /config FILE     Load configuration file
echo   /? /help         Show this help
echo.
pause
exit /b 0