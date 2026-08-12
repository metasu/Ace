@echo off
chcp 65001 >nul 2>&1
title Hermes CLI + WebUI Launcher

:top
:: Resolve the folder where this batch file sits (ends with a backslash, e.g. "F:\hermes_ui\")
set "ROOT_DIR=%~dp0"
:: Remove trailing backslash for clean path joining where needed
set "ROOT_DIR_NO_SLASH=%ROOT_DIR:~0,-1%"
:: Portable dependencies live in a sibling directory (e.g. "F:\rely\") — no hardcoded drive letter
:: Use `for %%I` to resolve ..\rely to a fully-qualified absolute path (no ..\ in variables/PATH)
for %%I in ("%ROOT_DIR%..\rely") do set "RELY_DIR=%%~fI\"
for %%I in ("%ROOT_DIR%..\rely") do set "RELY_DIR_NO_SLASH=%%~fI"

set "HERMES_HOME=%ROOT_DIR%data"
set "HERMES_WEBUI_STATE_DIR=%ROOT_DIR%data\webui"
set "HERMES_GIT_BASH_PATH=%RELY_DIR%git\bin\bash.exe"
set "HERMES_WEBUI_PYTHON=%RELY_DIR%venv\Scripts\python.exe"
set "HERMES_WEBUI_AGENT_DIR=%ROOT_DIR%hermes-agent"

:: Only prepend to PATH once per window session. `:top` re-runs on every
:: "goto menu" round-trip (after each menu action), and unconditionally
:: prepending would grow PATH a little more each loop — after enough
:: menu round-trips in one long-lived window, PATH exceeds cmd's ~8191
:: char command-line limit and every command fails with "The input line
:: is too long". Guard with a sentinel so this only happens once.
if not defined _HERMES_PATH_INIT (
  set "PATH=%RELY_DIR%venv\Scripts;%RELY_DIR%node;%RELY_DIR%git\bin;%PATH%"
  set "_HERMES_PATH_INIT=1"
)

:: Safety: ensure HERMES_HOME is an absolute path (drive letter + backslash).
:: If %~dp0 fails (e.g. wrong line endings), HERMES_HOME would be relative
:: and the WebUI would resolve it against hermes-webui\ — wrong config, no
:: core tools. Abort early with a clear message instead of silently broken.
set "_SEP=%HERMES_HOME:~2,1%"
set "BS=\"
if not "%_SEP%"=="%BS%" goto bad_home
goto home_ok

:bad_home
echo ========================================
echo  FATAL: HERMES_HOME is not an absolute path!
echo  HERMES_HOME = %HERMES_HOME%
echo  ROOT_DIR    = %ROOT_DIR%
echo  start.bat may have wrong line endings: LF instead of CRLF.
echo  Fix: open in VS Code, set line endings to CRLF, save, retry.
echo ========================================
pause
exit /b 1

:home_ok

:: ===== Inject API keys as environment variables (key_env references in config.yaml) =====
:: Keys live here (start.bat), NOT in config.yaml — so config.yaml leaking alone exposes no key.
set "HERMES_ATLASCLOUD_KEY=apikey-YOUR_ATLASCLOUD_KEY"
set "HERMES_CCVIBE_GPT_KEY=sk-YOUR_CCVIBE_KEY"
set "HERMES_KUAIPAO_GPT_KEY=sk-YOUR_KUAIPAO_KEY"
set "MCP_ATLASCLOUD_KEY=apikey-YOUR_MCP_ATLASCLOUD_KEY"
:: Bound each upstream request so provider fallback cannot be held indefinitely.
set "HERMES_API_TIMEOUT=60"

:: ===== Pre-flight diagnostics: verify all critical paths exist =====
call :check_deps

:: Fix venv pyvenv.cfg to point at portable Python (anti-drive-drift)
call :fix_pyvenv
:: Fix editable-install finder paths to current drive (anti-drive-drift)
call :fix_editable_finder
:: Inject MCP server config into config.yaml (paths + keys from env vars)
call :inject_mcp_config
:: Maintain a failover chain using existing providers/models only.
call :configure_failover
if errorlevel 1 goto failover_config_error

echo ========================================
echo  Hermes Agent CLI + WebUI Launcher (Portable)
echo ========================================
echo.
echo  Detected Root  = %ROOT_DIR_NO_SLASH%
echo  Rely Dir       = %RELY_DIR_NO_SLASH%
echo  HERMES_HOME    = %HERMES_HOME%
echo  Python venv    = %RELY_DIR%venv
echo  WebUI          = http://localhost:8787
echo  API Server     = http://localhost:50001
echo.
echo  [1] Start Hermes Gateway (background)
echo  [2] Start Hermes WebUI (foreground)
echo  [3] Start both (gateway background + webui foreground)
echo  [4] Stop all Hermes processes
echo  [5] Test API connection
echo  [6] Exit
echo  [7] Test CURRENT configured channel API
echo  [8] Switch to kuaipao (gpt-5.6-sol)
echo  [9] Switch to atlascloud (zai-org/glm-5.2)
echo  [10] Switch to atlascloud (xai/grok-4.3)
echo  [11] Switch to cc-vibe-gpt (gpt-5.6-sol)
echo.
set "choice="
set /p choice="Select [1-11]: "
if not defined choice goto no_choice

if "%choice%"=="1" goto start_gateway
if "%choice%"=="2" goto start_webui
if "%choice%"=="3" goto start_both
if "%choice%"=="4" goto stop_all
if "%choice%"=="5" goto test_api
if "%choice%"=="6" exit
if "%choice%"=="7" goto test_current_api
if "%choice%"=="8" goto switch_kuaipao
if "%choice%"=="9" goto switch_atlascloud
if "%choice%"=="10" goto switch_atlascloud_grok
if "%choice%"=="11" goto switch_ccvibe_gpt
goto invalid_choice

:start_gateway
echo Starting Hermes Gateway...
set "HERMES_HOME=%ROOT_DIR%data"
set "HERMES_WEBUI_STATE_DIR=%ROOT_DIR%data\webui"
set "HERMES_GIT_BASH_PATH=%RELY_DIR%git\bin\bash.exe"
:: Re-verify the venv right before launch (defensive: pyvenv.cfg can get
:: re-poisoned if this same rely\ folder was just used on another drive
:: letter). Cheap check, avoids a silent crash in the new window below.
call :fix_pyvenv
:: Use `cmd /k` instead of launching python.exe directly as the window's
:: host process. If python.exe crashes immediately (broken venv, missing
:: module, blocked by AV, etc.) BEFORE it can print the startup banner,
:: a bare `start "title" python.exe ...` window closes the instant the
:: process exits — the user sees no window at all ("界面不出现"). Wrapping
:: in `cmd /k` keeps the window open after the command exits (success OR
:: crash) so the real error is always visible instead of a vanishing window.
start "Hermes Gateway" cmd /k ""%RELY_DIR%venv\Scripts\python.exe" -m hermes_cli.main gateway run --replace"
echo Gateway started in background window.
echo (If the window closes/shows an error immediately, that window now
echo  stays open with the exact error — read it before reporting "no window".)
pause
goto menu

:start_webui
echo Starting Hermes WebUI on port 8787...
cd /d "%ROOT_DIR%hermes-webui"
set "HERMES_HOME=%ROOT_DIR%data"
set "HERMES_WEBUI_STATE_DIR=%ROOT_DIR%data\webui"
call :fix_pyvenv
"%RELY_DIR%venv\Scripts\python.exe" server.py
pause
goto menu

:start_both
echo Starting Hermes Gateway (background)...
set "HERMES_HOME=%ROOT_DIR%data"
set "HERMES_WEBUI_STATE_DIR=%ROOT_DIR%data\webui"
set "HERMES_GIT_BASH_PATH=%RELY_DIR%git\bin\bash.exe"
call :fix_pyvenv
start "Hermes Gateway" cmd /k ""%RELY_DIR%venv\Scripts\python.exe" -m hermes_cli.main gateway run --replace"
timeout /t 3 /nobreak >nul
echo Starting Hermes WebUI on port 8787...
cd /d "%ROOT_DIR%hermes-webui"
set "HERMES_HOME=%ROOT_DIR%data"
set "HERMES_WEBUI_STATE_DIR=%ROOT_DIR%data\webui"
"%RELY_DIR%venv\Scripts\python.exe" server.py
pause
goto menu

:stop_all
echo Stopping all Hermes processes...
taskkill /f /im python.exe /fi "WINDOWTITLE eq Hermes Gateway" 2>nul
taskkill /f /im python.exe /fi "WINDOWTITLE eq Hermes WebUI" 2>nul
wmic process where "commandline like '%%hermes_cli.main%%' or commandline like '%%server.py%%'" call terminate >nul 2>&1
taskkill /f /im python.exe /fi "COMMANDLINE like '%%server.py%%'" 2>nul
taskkill /f /im python.exe /fi "COMMANDLINE like '%%hermes_cli.main%%'" 2>nul
echo Done.
pause
goto menu

:no_choice
echo No menu input received. Returning to menu safely...
pause
goto menu

:invalid_choice
echo Invalid menu choice. Returning to menu safely...
pause
goto menu

:test_api
echo Testing API connection...
set "HERMES_HOME=%ROOT_DIR%data"
"%RELY_DIR%venv\Scripts\python.exe" -m hermes_cli.main doctor
echo.
echo Testing kuaipao API...
"%RELY_DIR%venv\Scripts\python.exe" -c "import urllib.request,json; req=urllib.request.Request('https://kuaipao.ai/v1/models',headers={'Authorization':'Bearer sk-YOUR_KUAIPAO_KEY'}); r=urllib.request.urlopen(req); print('kuaipao OK:',[m['id'] for m in json.loads(r.read())['data'][:5]])"
echo.
pause
goto menu

:test_current_api
echo ===================================================
echo  Testing CURRENT configured API channel in config.yaml
echo ===================================================
"%RELY_DIR%venv\Scripts\python.exe" -c "import pathlib, yaml, urllib.request, json, os; p=pathlib.Path(r'%ROOT_DIR%data\config.yaml'); cfg=yaml.safe_load(p.read_text(encoding='utf-8')); m_cfg=cfg.get('model',{}); prov=m_cfg.get('provider'); url=m_cfg.get('base_url','').rstrip('/')+'/models'; key_var=cfg.get('providers',{}).get(prov,{}).get('key_env'); key=os.environ.get(key_var) if key_var else None; print('Provider:', prov); print('URL:', url); print('Key Env:', key_var); print('Key Value:', (key[:15]+'...') if key else 'None'); req=urllib.request.Request(url,headers={'Authorization':f'Bearer {key}'} if key else {}); r=urllib.request.urlopen(req, timeout=10); print('HTTP Status:', r.status); print('Models List:', [m['id'] for m in json.loads(r.read().decode('utf-8'))['data']][:8])"
if errorlevel 1 (
    echo.
    echo [FAIL] API Test failed! Please verify base_url and API key.
) else (
    echo.
    echo [SUCCESS] Current API channel is working perfectly!
)
pause
goto menu

:switch_kuaipao
echo Switching to kuaipao (gpt-5.6-sol)...
"%RELY_DIR%venv\Scripts\python.exe" -c "import pathlib,re; p=pathlib.Path(r'%ROOT_DIR%data\config.yaml'); t=p.read_text(encoding='utf-8'); t=re.sub(r'^  default:.*$','  default: \"gpt-5.6-sol\"',t,flags=re.M); t=re.sub(r'^  provider:.*$','  provider: \"kuaipao\"',t,flags=re.M); t=re.sub(r'^  base_url:.*$','  base_url: \"https://kuaipao.ai/v1\"',t,flags=re.M); p.write_text(t,encoding='utf-8',newline='\n'); print('Switched to kuaipao gpt-5.6-sol')"
call :configure_failover
pause
goto menu

:switch_atlascloud
echo Switching to atlascloud (zai-org/glm-5.2)...
"%RELY_DIR%venv\Scripts\python.exe" -c "import pathlib,re; p=pathlib.Path(r'%ROOT_DIR%data\config.yaml'); t=p.read_text(encoding='utf-8'); t=re.sub(r'^  default:.*$','  default: \"zai-org/glm-5.2\"',t,flags=re.M); t=re.sub(r'^  provider:.*$','  provider: \"atlascloud\"',t,flags=re.M); t=re.sub(r'^  base_url:.*$','  base_url: \"https://api.atlascloud.ai/v1\"',t,flags=re.M); p.write_text(t,encoding='utf-8',newline='\n'); print('Switched to atlascloud zai-org/glm-5.2')"
call :configure_failover
pause
goto menu

:switch_atlascloud_grok
echo Switching to atlascloud (xai/grok-4.3)...
"%RELY_DIR%venv\Scripts\python.exe" -c "import pathlib,re; p=pathlib.Path(r'%ROOT_DIR%data\config.yaml'); t=p.read_text(encoding='utf-8'); t=re.sub(r'^  default:.*$','  default: \"xai/grok-4.3\"',t,flags=re.M); t=re.sub(r'^  provider:.*$','  provider: \"atlascloud\"',t,flags=re.M); t=re.sub(r'^  base_url:.*$','  base_url: \"https://api.atlascloud.ai/v1\"',t,flags=re.M); p.write_text(t,encoding='utf-8',newline='\n'); print('Switched to atlascloud xai/grok-4.3')"
call :configure_failover
pause
goto menu

:switch_ccvibe_gpt
echo Switching to cc-vibe-gpt (gpt-5.6-sol)...
"%RELY_DIR%venv\Scripts\python.exe" -c "import pathlib,re; p=pathlib.Path(r'%ROOT_DIR%data\config.yaml'); t=p.read_text(encoding='utf-8'); t=re.sub(r'^  default:.*$','  default: \"gpt-5.6-sol\"',t,flags=re.M); t=re.sub(r'^  provider:.*$','  provider: \"cc-vibe-gpt\"',t,flags=re.M); t=re.sub(r'^  base_url:.*$','  base_url: \"https://cc-vibe.com/v1\"',t,flags=re.M); p.write_text(t,encoding='utf-8',newline='\n'); print('Switched to cc-vibe-gpt gpt-5.6-sol')"
call :configure_failover
pause
goto menu

:check_deps
:: Pre-flight check: verify all critical paths exist before proceeding
set "_DEPS_OK=1"
echo ========================================
echo  Pre-flight Dependency Check
echo ========================================
echo  ROOT_DIR    = %ROOT_DIR_NO_SLASH%
echo  RELY_DIR    = %RELY_DIR_NO_SLASH%
echo  HERMES_HOME = %HERMES_HOME%
echo.

:: Check rely directory itself
if not exist "%RELY_DIR%" (
  echo  [FAIL] rely directory not found: %RELY_DIR_NO_SLASH%
  echo         Expected at: %ROOT_DIR%..\rely
  echo         Please ensure the rely folder is at the same level as hermes_ui
  set "_DEPS_OK=0"
)

:: Check portable Python
if not exist "%RELY_DIR%python\python.exe" (
  echo  [FAIL] Portable Python not found: %RELY_DIR%python\python.exe
  set "_DEPS_OK=0"
) else (
  echo  [ OK ] Python: %RELY_DIR%python\python.exe
)

:: Check venv
if not exist "%RELY_DIR%venv\Scripts\python.exe" (
  echo  [FAIL] venv Python not found: %RELY_DIR%venv\Scripts\python.exe
  set "_DEPS_OK=0"
) else (
  echo  [ OK ] venv:  %RELY_DIR%venv\Scripts\python.exe
)

:: Check Node.js
if not exist "%RELY_DIR%node\node.exe" (
  echo  [FAIL] Node.js not found: %RELY_DIR%node\node.exe
  set "_DEPS_OK=0"
) else (
  echo  [ OK ] node:  %RELY_DIR%node\node.exe
)

:: Check Git/bash
if not exist "%RELY_DIR%git\bin\bash.exe" (
  echo  [FAIL] Git bash not found: %RELY_DIR%git\bin\bash.exe
  set "_DEPS_OK=0"
) else (
  echo  [ OK ] git:   %RELY_DIR%git\bin\bash.exe
)

:: Check config.yaml
if not exist "%ROOT_DIR%data\config.yaml" (
  echo  [FAIL] config.yaml not found: %ROOT_DIR%data\config.yaml
  set "_DEPS_OK=0"
) else (
  echo  [ OK ] config: %ROOT_DIR%data\config.yaml
)

:: Check .env
if not exist "%ROOT_DIR%data\.env" (
  echo  [WARN] .env not found: %ROOT_DIR%data\.env
  echo         API keys may be missing - LLM provider might not work
) else (
  echo  [ OK ] .env:   %ROOT_DIR%data\.env
)

:: Check fix scripts
if not exist "%ROOT_DIR%fix_pyvenv.py" (
  echo  [FAIL] fix_pyvenv.py not found: %ROOT_DIR%fix_pyvenv.py
  set "_DEPS_OK=0"
) else (
  echo  [ OK ] fix_pyvenv.py
)

if not exist "%ROOT_DIR%inject_mcp_config.py" (
  echo  [FAIL] inject_mcp_config.py not found: %ROOT_DIR%inject_mcp_config.py
  set "_DEPS_OK=0"
) else (
  echo  [ OK ] inject_mcp_config.py
)

if not exist "%ROOT_DIR%configure_failover.py" (
  echo  [FAIL] configure_failover.py not found: %ROOT_DIR%configure_failover.py
  set "_DEPS_OK=0"
) else (
  echo  [ OK ] configure_failover.py
)

if not exist "%ROOT_DIR%fix_editable_finder.py" (
  echo  [FAIL] fix_editable_finder.py not found: %ROOT_DIR%fix_editable_finder.py
  set "_DEPS_OK=0"
) else (
  echo  [ OK ] fix_editable_finder.py
)

echo.
if "%_DEPS_OK%"=="0" (
  echo  ========================================
  echo  CRITICAL: One or more dependencies are missing!
  echo  Hermes will NOT work correctly without these.
  echo  ========================================
  echo.
  echo  Press any key to continue anyway, or Ctrl+C to abort.
  pause >nul
) else (
  echo  All dependencies OK.
)
echo.
goto :eof

:fix_pyvenv
:: Rewrite venv/pyvenv.cfg home= line to point at portable Python (anti-drive-drift)
:: Use portable Python directly (not venv) to avoid chicken-and-egg if pyvenv.cfg is stale
"%RELY_DIR%python\python.exe" "%ROOT_DIR%fix_pyvenv.py" "%RELY_DIR_NO_SLASH%"
goto :eof

:inject_mcp_config
"%RELY_DIR%venv\Scripts\python.exe" "%ROOT_DIR%inject_mcp_config.py" "%ROOT_DIR_NO_SLASH%"
goto :eof

:configure_failover
"%RELY_DIR%venv\Scripts\python.exe" "%ROOT_DIR%configure_failover.py" "%ROOT_DIR_NO_SLASH%"
goto :eof

:fix_editable_finder
"%RELY_DIR%python\python.exe" "%ROOT_DIR%fix_editable_finder.py" "%RELY_DIR_NO_SLASH%" "%ROOT_DIR_NO_SLASH%"
goto :eof

:failover_config_error
echo.
echo ========================================
echo  FATAL: Provider failover configuration failed.
echo  Hermes was not started without fallback protection.
echo  Review the error above and data\config.yaml.
echo ========================================
pause
exit /b 1

:menu
cls
goto top
