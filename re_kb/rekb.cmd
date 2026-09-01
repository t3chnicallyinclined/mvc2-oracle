@echo off
REM rekb.cmd - query the MapleCast RE knowledge graph (SurrealDB ns=re db=kb).
REM Usage:
REM   tools\re_kb\rekb.cmd "SELECT * FROM field WHERE owner='char_struct';"
REM   tools\re_kb\rekb.cmd @tools\re_kb\02_char_struct.surql   (apply a file)
REM Reads SQL from the first arg; auto-prepends `USE NS re DB kb;`.
REM `USE NS re DB kb;` is ALWAYS prepended, including for a file apply -- 5 of the
REM 87 seed files carry no USE line, and without this every statement in them
REM fails with "Specify a namespace to use" while curl still returns 200.
setlocal
if "%REKB_URL%"=="" set REKB_URL=http://127.0.0.1:8001/sql
if "%REKB_AUTH%"=="" set REKB_AUTH=root:root

set "ARG=%~1"
if "%ARG:~0,1%"=="@" (
  set "F=%ARG:~1%"
  (echo USE NS re DB kb;^& type "%F%") > "%TEMP%ekb_body.surql"
  curl -s -X POST %REKB_URL% -u %REKB_AUTH% -H "Accept: application/json" --data-binary "@%TEMP%ekb_body.surql"
) else (
  curl -s -X POST %REKB_URL% -u %REKB_AUTH% -H "Accept: application/json" --data-binary "USE NS re DB kb; %~1"
)
endlocal
