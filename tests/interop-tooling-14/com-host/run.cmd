@echo off
set "ASTRA14_RUN=%TEMP%\Astra14Native-%RANDOM%-%RANDOM%"
if exist "%ASTRA14_RUN%" exit /b 12
mkdir "%ASTRA14_RUN%"
if errorlevel 1 exit /b 13
copy /b "%~dp0host-client.exe" "%ASTRA14_RUN%\host-client.exe" >nul
if errorlevel 1 exit /b 14
copy /b "%~dp0host-provider.dll" "%ASTRA14_RUN%\host-provider.dll" >nul
if errorlevel 1 exit /b 15
cd /d "%ASTRA14_RUN%"
(ver & echo architecture=%PROCESSOR_ARCHITECTURE% & echo test_directory=%CD% & where.exe cl.exe & where.exe clang.exe & where.exe clang-cl.exe & where.exe gcc.exe & where.exe g++.exe & where.exe csc.exe & where.exe dotnet.exe & where.exe python.exe & where.exe cmake.exe & where.exe ninja.exe & where.exe curl.exe) >inventory.txt 2>&1
>COM1 echo ASTRA14_HOST_BEGIN
type inventory.txt>COM1
host-client.exe "%CD%\host-provider.dll" >com-result.txt 2>&1
set "ASTRA14_EXIT=%ERRORLEVEL%"
type com-result.txt>COM1
>COM1 echo ASTRA14_HOST_EXIT=%ASTRA14_EXIT%
>COM1 echo ASTRA14_HOST_END
type com-result.txt
exit /b %ASTRA14_EXIT%
