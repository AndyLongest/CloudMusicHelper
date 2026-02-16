@echo off
setlocal
chcp 65001 >nul
cd /d "%~dp0"
set "DB_PATH=%LOCALAPPDATA%\NetEase\CloudMusic\Library\webdb.dat"
set "OUT_DIR=%~dp0output"
set "CATALOG_FILE=%~dp0output\_list_catalog.txt"
if defined MAIN_ROOT set "CATALOG_FILE=%MAIN_ROOT%\_list_catalog.txt"

if not exist "%DB_PATH%" (
  echo 未找到数据库文件：
  echo %DB_PATH%
  echo.
  echo 请确认当前账号下已安装并登录过网易云音乐。
  pause
  exit /b 1
)

echo 开始导出歌单/专辑...
"%~dp0cloudmusic_export.exe" --db "%DB_PATH%" >nul 2>nul
if %errorlevel% neq 0 (
  echo.
  echo 导出失败，请确认网易云数据库存在且可访问。
  exit /b %errorlevel%
)

set "ALBUM_COUNT=0"
set "PLAYLIST_COUNT=0"
if exist "%OUT_DIR%\albums" for /f %%I in ('dir /a-d /b "%OUT_DIR%\albums\*.txt" 2^>nul ^| find /c /v ""') do set "ALBUM_COUNT=%%I"
if exist "%OUT_DIR%\playlists" for /f %%I in ('dir /a-d /b "%OUT_DIR%\playlists\*.txt" 2^>nul ^| find /c /v ""') do set "PLAYLIST_COUNT=%%I"

if exist "%CATALOG_FILE%" del /f /q "%CATALOG_FILE%" >nul 2>nul
if exist "%OUT_DIR%\albums" (
  for /f "delims=" %%F in ('dir /a-d /b "%OUT_DIR%\albums\*.txt" 2^>nul') do >>"%CATALOG_FILE%" echo albums^|%%~nF
)
if exist "%OUT_DIR%\playlists" (
  for /f "delims=" %%F in ('dir /a-d /b "%OUT_DIR%\playlists\*.txt" 2^>nul') do >>"%CATALOG_FILE%" echo playlists^|%%~nF
)

echo 导出完成
echo 专辑 txt 数量: %ALBUM_COUNT%
echo 歌单 txt 数量: %PLAYLIST_COUNT%
echo 输出目录: %OUT_DIR%
echo.
echo 导出成功。
if /I "%NO_PAUSE%"=="1" exit /b
pause
