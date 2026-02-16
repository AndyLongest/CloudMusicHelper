@echo off
cd /d %~dp0
if exist "_run_log.txt" del /f /q "_run_log.txt"
set NO_PAUSE=1
set "NCM_SOURCE_FILE=C:\Users\AndyLong\AppData\Local\Temp\ncm_source_dir.txt"
call "workflow.bat" > "_run_log.txt" 2>&1
