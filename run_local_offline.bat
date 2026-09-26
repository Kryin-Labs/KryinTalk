@echo off
setlocal
set "ROOT=%~dp0"
set "PY=%ROOT%.venv\Scripts\python.exe"
if exist "%PY%" (
  "%PY%" --version >nul 2>&1
  if errorlevel 1 set "PY=C:\Users\Narco\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"
) else set "PY=C:\Users\Narco\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"
if not exist "%PY%" (
  echo Python runtime not found. Install Python 3.11+ or update PY in this script.
  exit /b 1
)
echo Starting KryinTalk Flutter web server...
start "ConnectHub Frontend" /D "%ROOT%" cmd /k ""%PY%" "%ROOT%src\server_web.py""
echo ConnectHub is running!
echo Frontend Web: http://127.0.0.1:8080
pause
