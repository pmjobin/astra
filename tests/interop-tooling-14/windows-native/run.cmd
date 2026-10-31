@echo off
set "ASTRA14_RUN=%TEMP%\Astra14Object-%RANDOM%-%RANDOM%"
if exist "%ASTRA14_RUN%" exit /b 12
mkdir "%ASTRA14_RUN%"
if errorlevel 1 exit /b 13
for %%L in (0 1 2) do copy /b "%~dp0native-O%%L.exe" "%ASTRA14_RUN%\native-O%%L.exe" >nul
if errorlevel 1 exit /b 14
cd /d "%ASTRA14_RUN%"
>COM1 echo ASTRA14_NATIVE_BEGIN
(ver & echo architecture=%PROCESSOR_ARCHITECTURE% & echo test_directory=%CD%) >inventory.txt
for %%L in (0 1 2) do certutil.exe -hashfile "%CD%\native-O%%L.exe" SHA256 >>inventory.txt 2>&1
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
>COM1 echo ASTRA14_NATIVE_EXIT=%ASTRA14_EXIT%
>COM1 echo ASTRA14_NATIVE_END
exit /b %ASTRA14_EXIT%
:run
native-O%1.exe >native-O%1.txt 2>&1
set "ASTRA14_LEVEL_EXIT=%ERRORLEVEL%"
type native-O%1.txt>COM1
type native-O%1.txt
>COM1 echo ASTRA14_NATIVE_O%1_EXIT=%ASTRA14_LEVEL_EXIT%
exit /b %ASTRA14_LEVEL_EXIT%
