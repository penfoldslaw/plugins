@echo off
rem PostToolUse hook: a tool just ran, so any pending permission prompt in this session was answered.
rem Runs after EVERY tool call, so it first checks (in ~10 ms, without starting PowerShell) whether any
rem permission reminder is running at all, and only then hands off to clear-permission.ps1.
setlocal
set "EL_HOME=%CLAUDE_EDGE_LIGHTING_HOME%"
if not defined EL_HOME set "EL_HOME=%USERPROFILE%\.claude\edge-lighting"
if not exist "%EL_HOME%\state\permission-*.json" exit /b 0
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0clear-permission.ps1"
exit /b 0
