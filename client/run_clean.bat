@echo off
chcp 65001 >nul
echo ============================================
echo  Full clean rebuild + run
echo ============================================
echo.
echo [1/3] Stopping running instances...
taskkill /F /IM dart.exe 2>nul
taskkill /F /IM flutter.exe 2>nul
timeout /t 2 /nobreak >nul
echo.
echo [2/3] Flutter clean...
call flutter clean
echo.
echo [3/3] Flutter run...
echo.
call flutter run
