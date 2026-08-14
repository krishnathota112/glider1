@echo off
REM process_all.bat — Process all glider data and create databases
REM
REM Usage: process_all.bat T:\glider_data

if "%1"=="" (
    echo Usage: process_all.bat ^<glider_data_directory^>
    echo Example: process_all.bat T:\glider_data
    exit /b 1
)

set DATA_ROOT=%1

echo.
echo ============================================================
echo GLIDER DATA PROCESSING - FULL WORKFLOW
echo ============================================================
echo Data root: %DATA_ROOT%
echo.

REM Step 1: Batch process all deployments
echo.
echo [1/2] Processing all deployments...
echo ============================================================
python pipeline\batch_process.py "%DATA_ROOT%"

if errorlevel 1 (
    echo.
    echo ERROR: Batch processing failed
    exit /b 1
)

REM Step 2: Ingest to databases
echo.
echo [2/2] Creating databases...
echo ============================================================
python pipeline\ingest_to_db.py "%DATA_ROOT%"

if errorlevel 1 (
    echo.
    echo ERROR: Database ingestion failed
    exit /b 1
)

echo.
echo ============================================================
echo COMPLETE
echo ============================================================
echo.
echo Individual databases: %DATA_ROOT%\^<deployment^>\output\^<deployment^>.db
echo Combined database: %DATA_ROOT%\glider_data_combined.db
echo.

exit /b 0
