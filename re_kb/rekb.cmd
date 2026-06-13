@echo off
REM rekb.cmd - query the MapleCast RE knowledge graph (SurrealDB ns=re db=kb).
REM Usage:
REM   tools\re_kb\rekb.cmd "SELECT * FROM field WHERE owner='char_struct';"
REM   tools\re_kb\rekb.cmd @tools\re_kb\02_char_struct.surql   (apply a file)
REM Reads SQL from the first arg; auto-prepends `USE NS re DB kb;`.
REM If the arg starts with '@' it is passed verbatim (the file carries its USE line).
setlocal
if "%REKB_URL%"=="" set REKB_URL=http://127.0.0.1:8001/sql
if "%REKB_AUTH%"=="" set REKB_AUTH=root:root

set "ARG=%~1"
if "%ARG:~0,1%"=="@" (
  curl -s -X POST %REKB_URL% -u %REKB_AUTH% -H "Accept: application/json" --data-binary "%~1"
) else (
  curl -s -X POST %REKB_URL% -u %REKB_AUTH% -H "Accept: application/json" --data-binary "USE NS re DB kb; %~1"
)
endlocal
