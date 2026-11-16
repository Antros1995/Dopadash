@echo off
rem Avvia il sito locale di DopaDash e lo apre nel browser.
rem Lascia aperta questa finestra: chiudendola il sito si spegne.
cd /d "%~dp0"
if not exist "build\web\index.html" goto nobuild
echo Sito locale: http://localhost:7358
echo Lascia aperta questa finestra. Per spegnere il sito, chiudila.
start "" "http://localhost:7358"
node tool\serve-local.mjs build\web 7358
echo.
echo Il sito si e' fermato. Se la porta 7358 era gia' occupata, il sito e' gia' acceso: apri http://localhost:7358
pause
exit /b

:nobuild
echo Il sito non e' ancora stato compilato.
echo Apri PowerShell in questa cartella ed esegui:
echo   flutter build web --no-pub --dart-define-from-file=config/dart_defines.local.json
pause
