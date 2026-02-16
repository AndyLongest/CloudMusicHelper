@echo off
chcp 65001 >nul
cd /d "%~dp0"
set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
for %%I in ("%ROOT%\..") do set "MAIN_ROOT=%%~fI"
set "NO_PAUSE=1"

echo ========================================
echo NetEase local music one-click workflow
echo Step1: input NCM source folder, recursive scan enabled
echo Step2: convert ncm to mp3
echo Step3: export playlists and albums
echo Step4: organize mp3 by playlist or album
echo ========================================
echo.
set "FLOW_EXIT=0"

echo [1/3] 执行 NCM -> MP3 转换...
echo [[STAGE]] 1
call "%ROOT%\ncm_to_mp3\一键批量转换.bat"
if errorlevel 1 (
  echo.
  echo [[ERROR]] convert
  echo 转换步骤出现错误，流程终止。
  set "FLOW_EXIT=1"
  goto :END
)

echo.
echo [2/3] 导出歌单/专辑...
echo [[STAGE]] 2
call "%ROOT%\get_lists\run_export.bat"
if errorlevel 1 (
  echo.
  echo [[ERROR]] export
  echo 导出步骤出现错误，流程终止。
  set "FLOW_EXIT=1"
  goto :END
)

echo.
echo [3/3] 根据歌单/专辑整理 MP3...
echo [[STAGE]] 3
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\organize_by_lists.ps1" -ProjectRoot "%ROOT%" -OutputRoot "%MAIN_ROOT%" -SelectionFile "%LIST_SELECTION_FILE%"
if errorlevel 1 (
  echo.
  echo [[ERROR]] organize
  echo 整理步骤出现错误，请检查上方日志。
  set "FLOW_EXIT=1"
  goto :END
)

echo.
echo 全流程完成！
echo [[DONE]]
echo 整理结果目录：%MAIN_ROOT%\organized_music

:END
echo.
echo [[CLEANUP]] start
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\cleanup_intermediate.ps1" -ProjectRoot "%ROOT%" -OutputRoot "%MAIN_ROOT%"
if errorlevel 1 (
  echo [[CLEANUP_WARN]] 清理中间文件时发生异常
) else (
  echo [[CLEANUP_DONE]]
)

echo.
echo 按任意键退出...
if /I "%NO_PAUSE%"=="1" exit /b %FLOW_EXIT%
pause >nul
exit /b %FLOW_EXIT%
