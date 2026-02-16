@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul
cd /d "%~dp0"
set "ROOT_DIR=%~dp0"
if "%ROOT_DIR:~-1%"=="\" set "ROOT_DIR=%ROOT_DIR:~0,-1%"

echo ========================================
echo NCM 一键批量转换
echo ========================================
echo [[STAGE]] 1
echo.

if not exist "input_ncm" mkdir "input_ncm"
if not exist "output_mp3" mkdir "output_mp3"

echo Please input NetEase NCM source folder path
echo Tip: subfolders are supported, all .ncm files will be scanned recursively
set "SOURCE_DIR="
set "USE_SOURCE_FILE=0"
if defined NCM_SOURCE_FILE if exist "%NCM_SOURCE_FILE%" (
  set "USE_SOURCE_FILE=1"
  echo Source path from app file mode enabled
) else if defined NCM_SOURCE_DIR (
  set "SOURCE_DIR=%NCM_SOURCE_DIR%"
  echo Source path from app: %SOURCE_DIR%
) else (
  set /p SOURCE_DIR=Source path, Enter to use current input_ncm: 
)

for %%I in ("%ROOT_DIR%\input_ncm") do set "INPUT_DIR=%%~fI"

if "%USE_SOURCE_FILE%"=="0" (
  if "%SOURCE_DIR%"=="" set "SOURCE_DIR=%ROOT_DIR%\input_ncm"
  if not exist "%SOURCE_DIR%" (
    echo.
    echo 输入目录不存在：%SOURCE_DIR%
    exit /b 1
  )
  for %%I in ("%SOURCE_DIR%") do set "SOURCE_DIR=%%~fI"
)

set "NCM_COUNT=0"
if "%USE_SOURCE_FILE%"=="1" (
  echo.
  echo 正在递归收集 NCM 文件到 input_ncm...
  set "COUNT_FILE=%TEMP%\ncm_count_%RANDOM%%RANDOM%.txt"
  if exist "!COUNT_FILE!" del /f /q "!COUNT_FILE!" >nul 2>nul
  powershell -NoProfile -ExecutionPolicy Bypass -Command "$src=(Get-Content -LiteralPath $env:NCM_SOURCE_FILE -Raw -Encoding UTF8).Trim(); if(-not $src){throw 'empty source'}; Write-Output ('Source path from app file: ' + $src); & '%ROOT_DIR%\prepare_input_ncm.ps1' -SourceDir $src -InputDir '%INPUT_DIR%' -CountFile '!COUNT_FILE!'"
  if errorlevel 1 (
    echo.
    echo 收集 NCM 文件失败，请检查目录是否正确且可访问。
    exit /b 1
  )
  if not exist "!COUNT_FILE!" (
    echo.
    echo 收集 NCM 文件失败：未获取到文件计数。
    exit /b 1
  )
  set /p NCM_COUNT=<"!COUNT_FILE!"
  del /f /q "!COUNT_FILE!" >nul 2>nul
) else if /I not "%SOURCE_DIR%"=="%INPUT_DIR%" (
  echo.
  echo 正在递归收集 NCM 文件到 input_ncm...
  set "COUNT_FILE=%TEMP%\ncm_count_%RANDOM%%RANDOM%.txt"
  if exist "!COUNT_FILE!" del /f /q "!COUNT_FILE!" >nul 2>nul
  powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT_DIR%\prepare_input_ncm.ps1" -SourceDir "%SOURCE_DIR%" -InputDir "%INPUT_DIR%" -CountFile "!COUNT_FILE!"
  if errorlevel 1 (
    echo.
    echo 收集 NCM 文件失败，请检查路径是否正确且可访问：
    echo %SOURCE_DIR%
    exit /b 1
  )
  if not exist "!COUNT_FILE!" (
    echo.
    echo 收集 NCM 文件失败：未获取到文件计数。
    exit /b 1
  )
  set /p NCM_COUNT=<"!COUNT_FILE!"
  del /f /q "!COUNT_FILE!" >nul 2>nul
) else (
  for /f %%I in ('dir /a-d /s /b "%INPUT_DIR%\*.ncm" 2^>nul ^| find /c /v ""') do set "NCM_COUNT=%%I"
)

if "%NCM_COUNT%"=="0" (
  echo.
  echo 未找到可转换的 .ncm 文件。
  exit /b 1
)

echo [[NCM_TOTAL]] %NCM_COUNT%

set "RUNTIME_DIR=%ROOT_DIR%\_convert_runtime"
set "RUNTIME_INPUT=%RUNTIME_DIR%\input_ncm"
set "RUNTIME_OUT=%RUNTIME_DIR%\output_mp3"
set "RUNTIME_MAP=%RUNTIME_DIR%\name_map.json"
if exist "%RUNTIME_DIR%" rd /s /q "%RUNTIME_DIR%"
mkdir "%RUNTIME_INPUT%" >nul 2>nul
mkdir "%RUNTIME_OUT%" >nul 2>nul

set "CONVERT_COUNT_FILE=%TEMP%\ncm_convert_count_%RANDOM%%RANDOM%.txt"
if exist "%CONVERT_COUNT_FILE%" del /f /q "%CONVERT_COUNT_FILE%" >nul 2>nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT_DIR%\prepare_convert_pending.ps1" -InputDir "%INPUT_DIR%" -OutputDir "%ROOT_DIR%\output_mp3" -RuntimeInputDir "%RUNTIME_INPUT%" -CountFile "%CONVERT_COUNT_FILE%" -RuntimeMapFile "%RUNTIME_MAP%"
if errorlevel 1 (
  echo.
  echo 预检查转换任务失败。
  if exist "%RUNTIME_DIR%" rd /s /q "%RUNTIME_DIR%"
  exit /b 1
)

set "TOTAL_NCM=0"
set "EXISTING_DONE=0"
set "PENDING_COUNT=0"
if exist "%CONVERT_COUNT_FILE%" (
  for /f "usebackq tokens=1-3 delims=|" %%A in ("%CONVERT_COUNT_FILE%") do (
    set "TOTAL_NCM=%%A"
    set "EXISTING_DONE=%%B"
    set "PENDING_COUNT=%%C"
  )
  del /f /q "%CONVERT_COUNT_FILE%" >nul 2>nul
)

echo [[CONVERT_EXISTING]] !EXISTING_DONE!
echo [[CONVERT_PENDING]] !PENDING_COUNT!

set "CHECKPOINT_FILE=%ROOT_DIR%\.convert_checkpoint.txt"
set "SIG_FILE=%TEMP%\ncm_sig_%RANDOM%%RANDOM%.txt"
if exist "!SIG_FILE!" del /f /q "!SIG_FILE!" >nul 2>nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT_DIR%\build_ncm_signature.ps1" -InputDir "%INPUT_DIR%" -OutFile "!SIG_FILE!" >nul
if errorlevel 1 (
  echo.
  echo 计算输入快照失败，继续执行转换。
  set "CAN_CHECKPOINT=0"
) else (
  set "CAN_CHECKPOINT=1"
)

set "CURRENT_SIG="
if "!CAN_CHECKPOINT!"=="1" (
  if exist "!SIG_FILE!" set /p CURRENT_SIG=<"!SIG_FILE!"
)
if exist "!SIG_FILE!" del /f /q "!SIG_FILE!" >nul 2>nul

set "LAST_SIG="
if exist "%CHECKPOINT_FILE%" set /p LAST_SIG=<"%CHECKPOINT_FILE%"

set "MP3_COUNT=0"
for /f %%I in ('dir /a-d /s /b "%ROOT_DIR%\output_mp3\*.mp3" 2^>nul ^| find /c /v ""') do set "MP3_COUNT=%%I"

set "SKIP_CONVERT=0"
if "!CAN_CHECKPOINT!"=="1" (
  if not "!CURRENT_SIG!"=="" (
    if /I "!CURRENT_SIG!"=="!LAST_SIG!" (
      if not "%MP3_COUNT%"=="0" (
        set "SKIP_CONVERT=1"
      )
    )
  )
)

if "!SKIP_CONVERT!"=="1" (
  echo Found %NCM_COUNT% ncm files.
  echo Input unchanged and %MP3_COUNT% mp3 files already exist, skip convert.
  echo [[CONVERT_START]]
  echo [[SKIP_CONVERT]]
  echo [[CONVERT_END]]
  if exist "%RUNTIME_DIR%" rd /s /q "%RUNTIME_DIR%"
  goto :AFTER_CONVERT
)

if "!PENDING_COUNT!"=="0" (
  echo All files already converted, skip convert work.
  echo [[CONVERT_START]]
  echo [[SKIP_CONVERT]]
  echo [[CONVERT_END]]
  if "!CAN_CHECKPOINT!"=="1" if not "!CURRENT_SIG!"=="" >"%CHECKPOINT_FILE%" echo !CURRENT_SIG!
  if exist "%RUNTIME_DIR%" rd /s /q "%RUNTIME_DIR%"
  goto :AFTER_CONVERT
)

echo 已找到 %NCM_COUNT% 个 .ncm 文件，其中 !PENDING_COUNT! 个需要转换，开始转换...
echo [[CONVERT_START]]

set "PYTHONUTF8=1"
set "PYTHONIOENCODING=utf-8"
set "PYTHONLEGACYWINDOWSSTDIO=1"

if exist "dist\ncm_batch_convert.exe" (
  echo 使用免安装版执行中...
  "dist\ncm_batch_convert.exe" --base-dir "%RUNTIME_DIR%"
) else (
  echo 未找到免安装版 exe，且当前目录不存在 Python 兜底脚本。
  echo [[CONVERT_FAIL]]
  if exist "%RUNTIME_DIR%" rd /s /q "%RUNTIME_DIR%"
  exit /b 1
)

if errorlevel 1 (
  echo.
  echo 部分文件转换失败，请查看上面的日志。
  echo [[CONVERT_FAIL]]
  if exist "%RUNTIME_DIR%" rd /s /q "%RUNTIME_DIR%"
  if /I "%NO_PAUSE%"=="1" exit /b 1
  echo.
  echo 按任意键退出...
  pause >nul
  exit /b 1
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT_DIR%\finalize_convert_output.ps1" -RuntimeOutDir "%RUNTIME_OUT%" -FinalOutDir "%ROOT_DIR%\output_mp3" -RuntimeMapFile "%RUNTIME_MAP%"
  if errorlevel 1 (
    echo.
    echo 转换结果回填失败。
    echo [[CONVERT_FAIL]]
    if exist "%RUNTIME_DIR%" rd /s /q "%RUNTIME_DIR%"
    if /I "%NO_PAUSE%"=="1" exit /b 1
    echo.
    echo 按任意键退出...
    pause >nul
    exit /b 1
  )
  if "!CAN_CHECKPOINT!"=="1" if not "!CURRENT_SIG!"=="" >"%CHECKPOINT_FILE%" echo !CURRENT_SIG!
  echo.
  echo 全部转换完成。
  echo [[CONVERT_END]]
  if exist "%RUNTIME_DIR%" rd /s /q "%RUNTIME_DIR%"
)

set "PYTHONUTF8="
set "PYTHONIOENCODING="
set "PYTHONLEGACYWINDOWSSTDIO="

:AFTER_CONVERT

echo.
echo 按任意键退出...
if /I "%NO_PAUSE%"=="1" exit /b
pause >nul
