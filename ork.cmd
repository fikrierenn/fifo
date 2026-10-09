@echo off
rem Orkestra CLI - ayrinti: ork yardim. Yol: ORKESTRA_HOME, yoksa kardes ..\orkestra (specs/007, A13).
setlocal
set "ORK_KOK=%ORKESTRA_HOME%"
if not defined ORK_KOK set "ORK_KOK=%~dp0..\orkestra"
if not exist "%ORK_KOK%\ci\ork.py" (
  echo Orkestra bulunamadi: ORKESTRA_HOME tanimlayin ya da Orkestra'yi bu projenin kardesi ..\orkestra olarak klonlayin. 1>&2
  exit /b 2
)
python "%ORK_KOK%\ci\ork.py" %*
exit /b %ERRORLEVEL%
