@echo off
set "ASTRA14_RUN=%TEMP%\Astra14Com-%RANDOM%-%RANDOM%"
if exist "%ASTRA14_RUN%" exit /b 12
mkdir "%ASTRA14_RUN%"
if errorlevel 1 exit /b 13
copy /b "%~dp0com-client.exe" "%ASTRA14_RUN%\com-client.exe" >nul
if errorlevel 1 exit /b 14
for %%L in (0 1 2) do copy /b "%~dp0com-provider-O%%L.dll" "%ASTRA14_RUN%\com-provider-O%%L.dll" >nul
if errorlevel 1 exit /b 15
cd /d "%ASTRA14_RUN%"
>COM1 echo ASTRA14_COM_BEGIN
(ver & echo architecture=%PROCESSOR_ARCHITECTURE% & echo test_directory=%CD%) >inventory.txt
certutil.exe -hashfile "%CD%\com-client.exe" SHA256 >>inventory.txt 2>&1
for %%L in (0 1 2) do certutil.exe -hashfile "%CD%\com-provider-O%%L.dll" SHA256 >>inventory.txt 2>&1
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
>COM1 echo ASTRA14_COM_EXIT=%ASTRA14_EXIT%
>COM1 echo ASTRA14_COM_END
exit /b %ASTRA14_EXIT%
:run
com-client.exe "%CD%\com-provider-O%1.dll" >com-O%1.txt 2>&1
set "ASTRA14_LEVEL_EXIT=%ERRORLEVEL%"
type com-O%1.txt>COM1
type com-O%1.txt
>COM1 echo ASTRA14_COM_O%1_EXIT=%ASTRA14_LEVEL_EXIT%
exit /b %ASTRA14_LEVEL_EXIT%
