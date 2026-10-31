@echo off
set "ASTRA14_RUN=%TEMP%\Astra14Import-%RANDOM%-%RANDOM%"
if exist "%ASTRA14_RUN%" exit /b 12
mkdir "%ASTRA14_RUN%"
if errorlevel 1 exit /b 13
copy /b "%~dp0import-provider.dll" "%ASTRA14_RUN%\import-provider.dll" >nul
if errorlevel 1 exit /b 14
for %%L in (0 1 2) do copy /b "%~dp0import-client-O%%L.exe" "%ASTRA14_RUN%\import-client-O%%L.exe" >nul
if errorlevel 1 exit /b 15
cd /d "%ASTRA14_RUN%"
>COM1 echo ASTRA14_IMPORT_BEGIN
(ver & echo architecture=%PROCESSOR_ARCHITECTURE% & echo test_directory=%CD%) >inventory.txt
certutil.exe -hashfile "%CD%\import-provider.dll" SHA256 >>inventory.txt 2>&1
for %%L in (0 1 2) do certutil.exe -hashfile "%CD%\import-client-O%%L.exe" SHA256 >>inventory.txt 2>&1
type inventory.txt>COM1
call :run 0
if errorlevel 1 goto failed
call :run 1
if errorlevel 1 goto failed
call :run 2
if errorlevel 1 goto failed
set "ASTRA14_EXIT=0"
goto finish
:failed
set "ASTRA14_EXIT=1"
:finish
>COM1 echo ASTRA14_IMPORT_EXIT=%ASTRA14_EXIT%
>COM1 echo ASTRA14_IMPORT_END
exit /b %ASTRA14_EXIT%
:run
import-client-O%1.exe "%CD%\import-provider.dll" >import-O%1.txt 2>&1
set "ASTRA14_LEVEL_EXIT=%ERRORLEVEL%"
type import-O%1.txt>COM1
type import-O%1.txt
>COM1 echo ASTRA14_IMPORT_O%1_EXIT=%ASTRA14_LEVEL_EXIT%
exit /b %ASTRA14_LEVEL_EXIT%
