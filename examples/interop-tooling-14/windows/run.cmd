@echo off
set "ASTRA14_RUN=%TEMP%\Astra14Apps-%RANDOM%-%RANDOM%"
if exist "%ASTRA14_RUN%" exit /b 12
mkdir "%ASTRA14_RUN%"
if errorlevel 1 exit /b 13
copy /b "%~dp0*.dll" "%ASTRA14_RUN%\" >nul
if errorlevel 1 exit /b 14
copy /b "%~dp0*.exe" "%ASTRA14_RUN%\" >nul
if errorlevel 1 exit /b 15
cd /d "%ASTRA14_RUN%"
>COM1 echo ASTRA14_APPS_BEGIN
(ver & echo architecture=%PROCESSOR_ARCHITECTURE% & echo test_directory=%CD%) >inventory.txt
for %%F in (*.exe *.dll) do certutil.exe -hashfile "%%F" SHA256 >>inventory.txt 2>&1
type inventory.txt>COM1
for %%L in (0 1 2) do (
call :run a123 %%L "a123-O%%L.exe" "%CD%\a123-provider.dll"
if errorlevel 1 goto failed
call :run a124 %%L "a124-client.exe" "%CD%\a124-O%%L.dll"
if errorlevel 1 goto failed
call :run a125 %%L "a125-client.exe" "%CD%\a125-O%%L.dll"
if errorlevel 1 goto failed
)
set "ASTRA14_EXIT=0"
goto finish
:failed
set "ASTRA14_EXIT=1"
:finish
>COM1 echo ASTRA14_APPS_EXIT=%ASTRA14_EXIT%
>COM1 echo ASTRA14_APPS_END
exit /b %ASTRA14_EXIT%
:run
%3 %4 >%1-O%2.txt 2>&1
set "ASTRA14_LEVEL_EXIT=%ERRORLEVEL%"
type %1-O%2.txt>COM1
type %1-O%2.txt
>COM1 echo ASTRA14_%1_O%2_EXIT=%ASTRA14_LEVEL_EXIT%
exit /b %ASTRA14_LEVEL_EXIT%
